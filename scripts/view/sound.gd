extends Node
## Music, ambience, SFX and UI sounds, all chosen by name from
## data/audio.json, each on its own bus (default_bus_layout.tres: Music,
## Ambience, SFX, Voice, UI; voice blips are voice.gd's).
##
## - Music: one looping track at a time, crossfaded over audio
##   "crossfade_s" (tuning.json) by play_music(name). Day / night swap with
##   the time of day; a missing night track just keeps the day one.
## - Ambience: looping layers (wind always, crickets at night, water near the
##   pond) whose volumes follow set_time() and the pond distance, plus bird
##   chirps by day at random intervals.
## - SFX: footsteps (grass / path), rustle, pond laps. UI: box open, cursor
##   move, choice confirm, line advance.
## - Footsteps (polish P2): soft, low paw pads on their own "Footsteps" bus
##   (a low-pass on it, audio.json footsteps.lowpass_hz), one per paw
##   landing (paw_step(), rhythm from core/gait.gd): lower pitch, back paws
##   heavier than front, walk quieter than run, a different variation each
##   time with random pitch / volume. The old footstep() stays as the
##   "classic" style until the new one is approved (footstep_style()).
## A missing file warns once and stays silent; it never crashes.
## The game screen creates this node after tap-to-start, so nothing plays
## before the browser allows audio. Cosmetic randomness: own RNG.

const JsonData := preload("res://scripts/core/json_data.gd")
const AUDIO_PATH := "res://data/audio.json"
const BUSES := ["Music", "Ambience", "SFX", "Voice", "UI", "Footsteps"]
const STEPS_BUS := "Footsteps"
const SILENT_DB := -60.0

var data: Dictionary = {}
var crossfade := 2.5
var music_name := ""
## For tests and catRpgStats: how many sounds each kind played.
var played: Dictionary = {}

var _music: Array[AudioStreamPlayer] = []
var _music_on := 0
var _ambience: Dictionary = {}
## Target dB per ambience layer (eased towards).
var _amb_target: Dictionary = {}
var _oneshots: Dictionary = {}
var _streams: Dictionary = {}
var _warned: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _bird_wait := 3.0
## Inside a den (set_indoors()).
var indoors := false
var _indoors_db := -14.0
var _lap_wait := 1.0
var _bird_every: Array = [2.5, 6.0]
var _lap_every: Array = [1.6, 3.2]
var _day := 1.0
var _night := 0.0
var _pond_near := 0.0
## Soft footsteps: audio.json "footsteps" and a small pool of players.
var steps: Dictionary = {}
var _step_pool: Array[AudioStreamPlayer] = []
var _step_next := 0
var _step_last: Dictionary = {}
## The last paw step (tests, catRpgStats): paw, surface, pitch, volume_db.
var last_step: Dictionary = {}
## The last few paw steps, oldest first (tests): last_step entries.
var step_log: Array[Dictionary] = []


func _ready() -> void:
	name = "Sound"
	ensure_buses()
	_rng.randomize()
	data = JsonData.load_dict(AUDIO_PATH)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_music.append(p)
	for layer: String in data.get("ambience", {}):
		var spec: Dictionary = data["ambience"][layer]
		var p := AudioStreamPlayer.new()
		p.name = "Amb_" + layer
		p.bus = "Ambience"
		p.stream = _load(str(spec.get("file", "")), true)
		p.volume_db = SILENT_DB
		add_child(p)
		_ambience[layer] = p
		_amb_target[layer] = SILENT_DB
		if p.stream != null:
			p.play()
	for group in ["sfx", "ui"]:
		for kind: String in data.get(group, {}):
			var spec: Dictionary = data[group][kind]
			var pool: Array[AudioStreamPlayer] = []
			for i in 2:
				var p := AudioStreamPlayer.new()
				p.bus = str(spec.get("bus", "UI" if group == "ui" else "SFX"))
				add_child(p)
				pool.append(p)
			_oneshots[kind] = {"spec": spec, "pool": pool, "next": 0}
	steps = data.get("footsteps", {})
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.name = "Paw%d" % i
		p.bus = str(steps.get("bus", STEPS_BUS))
		add_child(p)
		_step_pool.append(p)
	set_steps_lowpass(float(steps.get("lowpass_hz", 2000.0)))
	_update_ambience_targets()


func configure(tuning: Dictionary) -> void:
	crossfade = float(tuning.get("crossfade_s", crossfade))
	_bird_every = tuning.get("bird_every", _bird_every)
	_lap_every = tuning.get("lap_every", _lap_every)
	_indoors_db = float(tuning.get("indoors_db", _indoors_db))


## The five buses normally come from default_bus_layout.tres; add any
## that are missing.
static func ensure_buses() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
			if b == STEPS_BUS:
				AudioServer.add_bus_effect(i, AudioEffectLowPassFilter.new())


## The Footsteps bus's low-pass cutoff (Hz). Desktop only in effect: web
## builds play samples, which skip bus effects (the files are dark already).
static func set_steps_lowpass(hz: float) -> void:
	var i := AudioServer.get_bus_index(STEPS_BUS)
	if i < 0:
		return
	for e in AudioServer.get_bus_effect_count(i):
		var fx := AudioServer.get_bus_effect(i, e)
		if fx is AudioEffectLowPassFilter:
			(fx as AudioEffectLowPassFilter).cutoff_hz = hz


## Crossfades to music track `n` (a data/audio.json "music" key). Does
## nothing if it is already playing or its file is missing.
func play_music(n: String) -> void:
	if n == music_name:
		return
	var spec: Dictionary = data.get("music", {}).get(n, {})
	var stream := _load(str(spec.get("file", "")), true)
	if stream == null:
		return
	music_name = n
	var old := _music[_music_on]
	_music_on = 1 - _music_on
	var p := _music[_music_on]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", float(spec.get("volume_db", -14.0)), crossfade).set_trans(Tween.TRANS_SINE)
	if old.playing:
		tw.tween_property(old, "volume_db", SILENT_DB, crossfade).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(old.stop)


func has_music(n: String) -> bool:
	return _load(str(data.get("music", {}).get(n, {}).get("file", "")), true) != null


## Time of day: `day` and `night` are 0..1 (day_cycle.gd). Ambience layers
## blend between their "day" and "night" volumes; music swaps to "night"
## once it is mostly night (if a night track exists).
func set_time(day: float, night: float) -> void:
	_day = day
	_night = night
	_update_ambience_targets()
	if night > 0.5 and has_music("night"):
		play_music("night")
	elif night <= 0.5:
		play_music("day")


## Inside a den: the outdoor ambience is muffled (audio.indoors_db) and no
## birds sing.
func set_indoors(on: bool) -> void:
	if on == indoors:
		return
	indoors = on
	_update_ambience_targets()


## How close Fern is to the water: 0 (far) .. 1 (at the bank).
func set_pond_near(amount: float) -> void:
	_pond_near = clampf(amount, 0.0, 1.0)
	_update_ambience_targets()


func _update_ambience_targets() -> void:
	for layer: String in _ambience:
		var spec: Dictionary = data["ambience"][layer]
		var db := float(spec.get("volume_db", -20.0))
		if spec.has("day") or spec.has("night"):
			db = lerpf(float(spec.get("day", db)), float(spec.get("night", db)), _night)
		if spec.get("near", false):
			db = lerpf(SILENT_DB, db, _pond_near)
		if indoors:
			db += _indoors_db
		_amb_target[layer] = db


func _process(dt: float) -> void:
	for layer: String in _ambience:
		var p: AudioStreamPlayer = _ambience[layer]
		p.volume_db = move_toward(p.volume_db, _amb_target[layer], dt * 30.0)
	# Birds by day, laps near the water.
	if _day > 0.2 and not indoors:
		_bird_wait -= dt
		if _bird_wait <= 0.0:
			play("bird", lerpf(-12.0, 0.0, _day))
			_bird_wait = _rng.randf_range(float(_bird_every[0]), float(_bird_every[1]))
	if _pond_near > 0.3:
		_lap_wait -= dt
		if _lap_wait <= 0.0:
			play("pond_lap", lerpf(-10.0, 0.0, _pond_near))
			_lap_wait = _rng.randf_range(float(_lap_every[0]), float(_lap_every[1]))


## Plays one-shot `kind` (an "sfx" or "ui" key), `db_offset` quieter or
## louder than its data volume.
func play(kind: String, db_offset: float = 0.0) -> void:
	var o: Dictionary = _oneshots.get(kind, {})
	if o.is_empty():
		return
	var spec: Dictionary = o["spec"]
	var files: Array = spec.get("files", [])
	if files.is_empty():
		return
	var stream := _load(str(files[_rng.randi_range(0, files.size() - 1)]), false)
	if stream == null:
		return
	var pool: Array[AudioStreamPlayer] = o["pool"]
	var p := pool[o["next"]]
	o["next"] = (int(o["next"]) + 1) % pool.size()
	p.stream = stream
	var jitter := float(spec.get("pitch_jitter", 0.0))
	p.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	p.volume_db = float(spec.get("volume_db", -18.0)) + db_offset
	p.play()
	played[kind] = int(played.get(kind, 0)) + 1


## The classic footsteps (one tap every audio.footstep_px).
func footstep(surface: String, db_offset: float = 0.0) -> void:
	play("step_path" if surface == "path" else "step_grass", db_offset)


## "soft" (P2, paw_step()) or "classic" (footstep()): Settings.footsteps
## (?steps= on the web) if set, else audio.json footsteps.style.
func footstep_style() -> String:
	var s := str(Settings.footsteps) if Settings.footsteps != "" else str(steps.get("style", "soft"))
	return "classic" if s == "classic" or steps.is_empty() else "soft"


## One paw landing (gait.gd paw names: back_left, front_right...) on
## `surface` ("path" / "grass"), walking or running, `db_offset` on top
## (stalking is quieter). Picks a variation other than the last one, with
## random pitch and volume, the way an AudioStreamRandomizer would (done here
## because web builds play plain samples).
func paw_step(surface: String, paw: String, running: bool, db_offset: float = 0.0) -> void:
	var key := "path" if surface == "path" else "grass"
	var spec: Dictionary = steps.get(key, {})
	var files: Array = spec.get("files", [])
	if files.is_empty() or _step_pool.is_empty():
		return
	var pick := _rng.randi_range(0, files.size() - 1)
	if files.size() > 1 and pick == int(_step_last.get(key, -1)):
		pick = (pick + 1 + _rng.randi_range(0, files.size() - 2)) % files.size()
	_step_last[key] = pick
	var stream := _load(str(files[pick]), false)
	if stream == null:
		return
	var foot: Dictionary = steps.get("back" if paw.begins_with("back") else "front", {})
	var pr := float(steps.get("pitch_random", 0.05))
	var vr := float(steps.get("volume_random_db", 2.0))
	var pitch := float(steps.get("pitch", 0.85)) * float(foot.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-pr, pr))
	var db := float(spec.get("volume_db", -21.0)) + float(steps.get("run_db" if running else "walk_db", 0.0)) \
		+ float(foot.get("db", 0.0)) + _rng.randf_range(-vr, vr) + db_offset
	var p := _step_pool[_step_next]
	_step_next = (_step_next + 1) % _step_pool.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()
	played["paw"] = int(played.get("paw", 0)) + 1
	last_step = {"paw": paw, "surface": key, "running": running, "pitch": pitch, "volume_db": db, "file": pick}
	step_log.append(last_step)
	if step_log.size() > 64:
		step_log.pop_front()


func _load(path: String, loop: bool) -> AudioStream:
	var key := path + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		if not _warned.has(path):
			_warned.append(path)
			push_warning("Sound: missing audio '%s'" % path)
	elif loop:
		# Loop whatever was dropped in (imported WAVs already loop).
		if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.data.size() / (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if w.stereo else 1)
			s = w
		elif "loop" in s:
			s.set("loop", true)
	_streams[key] = s
	return s

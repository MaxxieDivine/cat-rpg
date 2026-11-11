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
## A missing file warns once and stays silent; it never crashes.
## The game screen creates this node after tap-to-start, so nothing plays
## before the browser allows audio. Cosmetic randomness: own RNG.

const JsonData := preload("res://scripts/core/json_data.gd")
const AUDIO_PATH := "res://data/audio.json"
const BUSES := ["Music", "Ambience", "SFX", "Voice", "UI"]
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
var _lap_wait := 1.0
var _bird_every: Array = [2.5, 6.0]
var _lap_every: Array = [1.6, 3.2]
var _day := 1.0
var _night := 0.0
var _pond_near := 0.0


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
	_update_ambience_targets()


func configure(tuning: Dictionary) -> void:
	crossfade = float(tuning.get("crossfade_s", crossfade))
	_bird_every = tuning.get("bird_every", _bird_every)
	_lap_every = tuning.get("lap_every", _lap_every)


## The five buses normally come from default_bus_layout.tres; add any
## that are missing.
static func ensure_buses() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


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
		_amb_target[layer] = db


func _process(dt: float) -> void:
	for layer: String in _ambience:
		var p: AudioStreamPlayer = _ambience[layer]
		p.volume_db = move_toward(p.volume_db, _amb_target[layer], dt * 30.0)
	# Birds by day, laps near the water.
	if _day > 0.2:
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


func footstep(surface: String) -> void:
	play("step_path" if surface == "path" else "step_grass")


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

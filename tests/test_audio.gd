extends "res://tests/test_base.gd"
## Audio: every file has a CREDITS.md line with a license, data/audio.json
## points at real files, the six buses exist (Footsteps low-passed), and the sound node
## crossfades music and follows the time of day.

const JsonData := preload("res://scripts/core/json_data.gd")
const Sound := preload("res://scripts/view/sound.gd")
const AUDIO_EXT := ["wav", "ogg", "mp3"]


func _audio_files(dir: String = "res://audio") -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_audio_files(dir.path_join(sub)))
	for f in d.get_files():
		if AUDIO_EXT.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	return out


func test_every_audio_file_is_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	check(credits != "", "CREDITS.md exists")
	var files := _audio_files()
	check(files.size() >= 10, "found the audio files (%d)" % files.size())
	for f in files:
		var rel := f.trim_prefix("res://")
		var line := ""
		for l in credits.split("\n"):
			if l.contains("`%s`" % rel):
				line = l
		check(line != "", "%s has a line in CREDITS.md" % rel)
		var licensed := false
		for lic in ["CC0", "CC-BY", "CC BY", "OFL", "MIT", "public domain"]:
			if line.contains(lic):
				licensed = true
		check(licensed, "%s's CREDITS.md line names its license" % rel)


func test_audio_json_points_at_real_files() -> void:
	var data := JsonData.load_dict("res://data/audio.json")
	for group in ["music", "ambience"]:
		for k in data[group]:
			check(ResourceLoader.exists(data[group][k]["file"]), "%s.%s file exists" % [group, k])
	for group in ["sfx", "ui"]:
		for k in data[group]:
			for f in data[group][k]["files"]:
				check(ResourceLoader.exists(f), "%s.%s: %s exists" % [group, k, f])
	for k in ["open", "move", "confirm", "advance"]:
		check(data["ui"].has(k), "UI sound '%s'" % k)
	for k in ["step_grass", "step_path", "rustle", "pond_lap"]:
		check(data["sfx"].has(k), "SFX '%s'" % k)
	for k in ["wind", "crickets"]:
		check(data["ambience"].has(k), "ambience '%s'" % k)
	check(data["music"]["day"].get("placeholder", false), "the placeholder track is labelled as one")


func test_buses() -> void:
	for b in Sound.BUSES:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s (default_bus_layout.tres)" % b)


func test_loops_loop() -> void:
	var data := JsonData.load_dict("res://data/audio.json")
	for group in ["music", "ambience"]:
		for k in data[group]:
			var s: AudioStream = load(data[group][k]["file"])
			if s is AudioStreamWAV:
				check((s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s.%s loops (import edit/loop_mode)" % [group, k])


func test_music_crossfades_with_the_time_of_day() -> void:
	var s: Node = Sound.new()
	tree.root.add_child(s)
	s.configure({"crossfade_s": 0.2})
	s.play_music("day")
	check_eq(s.music_name, "day", "day music")
	s.set_time(1.0, 0.0)
	check_eq(s.music_name, "day", "still day")
	s.set_time(0.0, 1.0)
	check_eq(s.music_name, "night", "night music after dusk")
	await tree.create_timer(0.35).timeout
	var playing := 0
	for p in s._music:
		if p.playing:
			playing += 1
	check_eq(playing, 1, "the old track stopped after the crossfade")
	check(s._amb_target["crickets"] > s._amb_target["wind"] - 10.0, "crickets up at night")
	s.set_time(1.0, 0.0)
	check(s._amb_target["crickets"] <= -60.0, "crickets silent by day")
	s.play("step_grass")
	s.play("no_such_sound")
	check_eq(int(s.played.get("step_grass", 0)), 1, "one-shot played")
	s.free()


func test_footsteps_bus_is_low_passed() -> void:
	var i := AudioServer.get_bus_index(Sound.STEPS_BUS)
	if not check(i >= 0, "a Footsteps bus"):
		return
	var lp: AudioEffectLowPassFilter = null
	for e in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, e) is AudioEffectLowPassFilter:
			lp = AudioServer.get_bus_effect(i, e)
	if check(lp != null, "a low-pass filter on it"):
		var data := JsonData.load_dict("res://data/audio.json")
		var s: Node = Sound.new()
		tree.root.add_child(s)
		check_near(lp.cutoff_hz, float(data["footsteps"]["lowpass_hz"]), 0.1, "cutoff from audio.json")
		s.free()


## The new paw steps are dark (almost nothing above 2 kHz, unlike the old
## grass step) and fade in over a few ms instead of clicking.
func test_paw_steps_are_soft() -> void:
	var data := JsonData.load_dict("res://data/audio.json")
	for surface in ["grass", "path"]:
		var files: Array = data["footsteps"][surface]["files"]
		check(files.size() >= 4 and files.size() <= 6, "%s: 4-6 variations" % surface)
		for f: String in files:
			var w: AudioStreamWAV = load(f)
			if not check(w != null and w.format == AudioStreamWAV.FORMAT_16_BITS, f):
				continue
			var a := _samples(w)
			check(absf(a[0]) < 0.01 and absf(a[int(w.mix_rate * 0.001)]) < 0.15, "%s fades in (no click)" % f)
			check(_zero_crossings_per_s(a, w.mix_rate) < 900.0, "%s is low (%.0f crossings/s)" % [f, _zero_crossings_per_s(a, w.mix_rate)])
	var old := _samples(load("res://audio/sfx/step_grass_1.wav"))
	check(_zero_crossings_per_s(old, 22050) > 2000.0, "(the old grass step was bright: the test can tell)")


func test_paw_step_variation_and_weight() -> void:
	var data := JsonData.load_dict("res://data/audio.json")
	var spec: Dictionary = data["footsteps"]
	var s: Node = Sound.new()
	tree.root.add_child(s)
	check_eq(s._step_pool[0].bus, "Footsteps", "paw steps go to the Footsteps bus")
	var back_pitch := 0.0
	var front_pitch := 0.0
	var back_db := 0.0
	var front_db := 0.0
	var repeats := 0
	var last := -1
	for i in 200:
		var paw := "back_left" if i % 2 == 0 else "front_right"
		s.paw_step("grass", paw, false)
		var st: Dictionary = s.last_step
		if st["file"] == last:
			repeats += 1
		last = st["file"]
		if paw == "back_left":
			back_pitch += st["pitch"] / 100.0
			back_db += st["volume_db"] / 100.0
		else:
			front_pitch += st["pitch"] / 100.0
			front_db += st["volume_db"] / 100.0
		var base := float(spec["pitch"]) * float(spec["back" if paw == "back_left" else "front"]["pitch"])
		check(absf(st["pitch"] / base - 1.0) <= float(spec["pitch_random"]) + 0.0001, "pitch within +-5%")
	check_eq(repeats, 0, "never the same variation twice in a row")
	check(front_pitch < 0.9 and back_pitch < front_pitch, "lower than before, back paws lower (%.2f / %.2f)" % [back_pitch, front_pitch])
	check(back_db > front_db, "back paws a little heavier")
	s.paw_step("grass", "front_left", false)
	var walk_db: float = s.last_step["volume_db"]
	s.paw_step("grass", "front_left", true)
	check(s.last_step["volume_db"] > walk_db - float(spec["volume_random_db"]) * 2.0 + (float(spec["run_db"]) - float(spec["walk_db"])) - 0.01, "running is louder than walking")
	check_eq(int(s.played.get("paw", 0)), 202, "counted")
	Settings.footsteps = "classic"
	check_eq(s.footstep_style(), "classic", "?steps=classic brings the old ones back")
	Settings.footsteps = ""
	check_eq(s.footstep_style(), str(spec["style"]), "default from audio.json")
	s.free()


func _samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := w.data
	var step := 4 if w.stereo else 2
	for i in range(0, d.size() - 1, step):
		out.append(d.decode_s16(i) / 32768.0)
	return out


func _zero_crossings_per_s(a: PackedFloat32Array, rate: float) -> float:
	var n := 0
	for i in range(1, a.size()):
		if (a[i - 1] < 0.0) != (a[i] < 0.0):
			n += 1
	return n / (a.size() / rate)

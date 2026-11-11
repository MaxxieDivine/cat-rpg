extends "res://tests/test_base.gd"
## Audio: every file has a CREDITS.md line with a license, data/audio.json
## points at real files, the five buses exist, and the sound node
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

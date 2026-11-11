## Measures how long the game's own per-frame logic takes (all _process
## callbacks), separately from rendering. Numbers depend on the machine.
## Headless (logic only):  godot --headless --path . --script res://tools/perf_probe.gd
## With rendering:         xvfb-run -a godot --path . --script res://tools/perf_probe.gd
extends SceneTree
class Mark extends Node:
	var first := true
	var box: Dictionary
	func _process(_d):
		var now := Time.get_ticks_usec()
		if first: box["t0"] = now
		else: box["sum"] += now - box["t0"]; box["n"] += 1
func _initialize(): _go.call_deferred()
func _go():
	var SM = load("res://scripts/view/screen_metrics.gd")
	SM.override_dpr = 3.0; SM.override_touch = 1
	root.size = Vector2i(2250, 1026)
	await process_frame
	var box := {"t0": 0, "sum": 0, "n": 0}
	var a := Mark.new(); a.box = box; a.process_priority = -100000
	var b := Mark.new(); b.box = box; b.first = false; b.process_priority = 100000
	root.add_child(a); root.add_child(b)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.start_game()
	Input.action_press("move_right")
	for i in 60: await process_frame
	box["sum"] = 0; box["n"] = 0
	var t0 := Time.get_ticks_usec()
	for i in 300: await process_frame
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	print("display=%s  game_logic_ms_per_frame=%.3f  wall_ms_per_frame=%.2f" % [DisplayServer.get_name(), box["sum"] / 1000.0 / box["n"], wall])
	quit()

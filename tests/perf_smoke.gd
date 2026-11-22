extends "res://tests/test_base.gd"
## Fails when the game's per-frame cost regresses noticeably against the
## budgets in data/perf.json:
## - logic_ms: our own scripts' time per frame (all _process callbacks),
##   measured like app.gd does, in the busiest state we have: Fern trotting
##   through tall grass at a phone size, then night with fireflies. Budgets
##   are several times what a CI runner measures, so only a real regression
##   (an accidental per-frame get_image(), an O(n^2) loop...) trips them.
## - draw_calls / canvas items (with a display): what makes phones slow is
##   mostly the GPU side; more draw calls or nodes than budgeted means
##   batching broke or something spawns without limit.
## Real 60 fps can only be confirmed on the phone (fps in the corner).

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

var budget: Dictionary


class Mark extends Node:
	var first := true
	var box: Dictionary
	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		if first:
			box["t0"] = now
		else:
			box["sum"] += now - box["t0"]
			box["n"] += 1


func before_each() -> void:
	budget = JsonData.load_dict("res://data/perf.json")


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	for a in ["move_left", "move_right", "move_up", "move_down", "run"]:
		Input.action_release(a)


func test_frame_cost_stays_in_budget() -> void:
	ScreenMetrics.override_dpr = 3.0
	ScreenMetrics.override_insets_css = [0.0, 47.0, 21.0, 47.0]
	ScreenMetrics.override_touch = 1
	ScreenMetrics.override_fullscreen = 0
	tree.root.size = Vector2i(2532, 1170)
	await tree.process_frame
	var box := {"t0": 0, "sum": 0, "n": 0}
	var a := Mark.new()
	a.box = box
	a.process_priority = -1000000
	var b := Mark.new()
	b.box = box
	b.first = false
	b.process_priority = 1000000
	tree.root.add_child(a)
	tree.root.add_child(b)
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	app.start_game()
	var g: Control = app.game
	var areas_data: Dictionary = JsonData.load_dict("res://data/areas.json")["areas"]
	for area: String in areas_data:
		g.load_area(area, "start")
		g.day.set_t(0.0)
		await tree.process_frame
		var w = g.world
		for phase in ["day", "night"]:
			if phase == "night":
				g.day.set_t(1.0)
			# Trot back and forth through the area's first tall-grass patch
			# (a den has none: across the middle of the room).
			var ad := JsonData.load_dict(areas_data[area]["file"])
			var patch: Array = ad["tall_grass"]["patches"][0]["rect"] if ad.has("tall_grass") else [w.size.x * 0.3, w.size.y * 0.4, w.size.x * 0.4, w.size.y * 0.2]
			w.player_pos = Vector2(patch[0] - 10, patch[1] + patch[3] / 2.0)
			w.player_vel = Vector2.ZERO
			Input.action_press("run")
			for i in 30:
				await tree.process_frame
			box["sum"] = 0
			box["n"] = 0
			var draws := 0
			for leg in 4:
				var dir := "move_right" if leg % 2 == 0 else "move_left"
				Input.action_press(dir)
				for i in 45:
					await tree.process_frame
					draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				Input.action_release(dir)
			Input.action_release("run")
			var ms: float = box["sum"] / 1000.0 / maxi(1, box["n"])
			print("     perf %s %s: logic %.3f ms/frame, max draw calls %d (display %s)" % [area, phase, ms, draws, DisplayServer.get_name()])
			check(ms <= float(budget["logic_ms"]), "%s %s: game logic %.3f ms per frame, budget %s ms (data/perf.json)" % [area, phase, ms, budget["logic_ms"]])
			if not is_headless():
				check(draws <= int(budget["draw_calls"]), "%s %s: %d draw calls per frame, budget %s (data/perf.json)" % [area, phase, draws, budget["draw_calls"]])
		await tree.process_frame  # the previous area's view is freed at the end of a frame
		var nodes := _count(g)
		print("     perf %s: %d nodes under the game screen" % [area, nodes])
		check(nodes <= int(budget["nodes"]), "%s: %d nodes under the game screen, budget %s" % [area, nodes, budget["nodes"]])
	tree.root.remove_child(app)
	app.free()
	a.free()
	b.free()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

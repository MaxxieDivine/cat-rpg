extends "res://tests/test_base.gd"
## Polish P2, the footstep rhythm (scripts/core/gait.gd): walk = four even
## beats (back-left, front-left, back-right, front-right), run = paired
## beats with a gap, locked to the sprite cycle, never bursting.

const Gait := preload("res://scripts/core/gait.gd")
const JsonData := preload("res://scripts/core/json_data.gd")


func _gait() -> Gait:
	var tuning := JsonData.load_dict("res://data/tuning.json")
	var g := Gait.new()
	g.configure(tuning["audio"]["gait"], 36.0, 56.0)
	g.reset(0.0)
	return g


## Walks `px` in steps of `dt_px`, returning [[distance, paw], ...].
func _walk(g: Gait, from: float, px: float, running: bool, dt_px: float = 0.5) -> Array:
	var out: Array = []
	var d := from
	while d < from + px:
		d += dt_px
		for paw in g.step(d, running):
			out.append([d, paw])
	return out


func test_walk_is_four_even_beats() -> void:
	var g := _gait()
	var hits := _walk(g, 0.0, 36.0 * 3, false)
	check_eq(hits.size(), 12, "four paws per stride, three strides")
	var order: Array = hits.slice(0, 4).map(func(h): return h[1])
	check_eq(order, ["front_left", "back_right", "front_right", "back_left"], "walk order (starting a quarter stride in)")
	for i in range(1, hits.size()):
		check_near(hits[i][0] - hits[i - 1][0], 9.0, 0.51, "even walk beats (%d)" % i)


func test_run_is_paired() -> void:
	var g := _gait()
	g.step(0.0, true)  # switching gait restarts the count
	var hits := _walk(g, 0.0, 56.0 * 3, true)
	check_eq(hits.size(), 12, "four paws per stride")
	var gaps: Array = []
	for i in range(1, hits.size()):
		gaps.append(hits[i][0] - hits[i - 1][0])
	# back pair close, gap, front pair close, longer gap.
	for i in gaps.size():
		var paw: String = hits[i + 1][1]
		if paw == "back_right" or paw == "front_right":
			check(gaps[i] < 7.0, "the pair lands close together (%s %.1f px)" % [paw, gaps[i]])
		else:
			check(gaps[i] > 15.0, "a gap before the next pair (%s %.1f px)" % [paw, gaps[i]])
	check(Gait.is_back("back_left") and not Gait.is_back("front_right"), "back / front")


func test_beats_follow_the_sprite_frames() -> void:
	var g := _gait()
	# Fern's walk sheet: 8 frames, one every 4.5 px. Beats at frames 0, 2, 4, 6.
	var frames: Array = []
	for h in _walk(g, 0.0, 72.0, false, 0.25):
		frames.append(int(h[0] / 4.5) % 8)
	check_eq(frames, [2, 4, 6, 0, 2, 4, 6, 0], "walk paws land on frames 0, 2, 4, 6")
	var run: Array = []
	g.step(0.0, true)
	for h in _walk(g, 0.0, 56.0, true, 0.25):
		run.append(snappedf(fmod(h[0], 56.0) / 56.0, 0.01))
	check_eq(run, [0.1, 0.45, 0.55, 0.0], "run paws at the tuned phases")


func test_no_bursts() -> void:
	var g := _gait()
	check_eq(g.step(500.0, false).size(), 4, "a big jump plays each paw once at most")
	check_eq(g.step(500.0, false).size(), 0, "standing still plays nothing")
	check_eq(g.step(520.0, true).size(), 0, "switching to a run starts fresh")
	g.reset(1000.0)
	check_eq(g.step(1000.0, false).size(), 0, "nothing on a reset")
	check(g.step(1000.0 + 9.0, false).size() <= 1, "then the beats again")

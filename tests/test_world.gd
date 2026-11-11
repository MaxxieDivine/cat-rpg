extends "res://tests/test_base.gd"
## Core world rules: movement, collision, focus, interaction. Expected values
## come from data/world.json and data/tuning.json.

const World := preload("res://scripts/core/world.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var wdata: Dictionary
var tdata: Dictionary
var w


func before_each() -> void:
	wdata = JsonData.load_dict(World.WORLD_PATH)
	tdata = JsonData.load_dict(World.TUNING_PATH)
	w = World.new()


func _run(seconds: float, move: Vector2, run: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var n := roundi(seconds * 60.0)
	for i in n:
		events.append_array(w.step(1.0 / 60.0, move, run))
	return events


## Puts the player in open grass, clear of everything.
func _open_spot() -> void:
	w.player_pos = Vector2(150, 175)
	w.player_vel = Vector2.ZERO
	for s: Rect2 in w.solids:
		check(not s.grow(30).intersects(w.player_rect()), "test spot is in open grass")


func test_loads_from_data() -> void:
	check_eq(w.size, Vector2(wdata["size"][0], wdata["size"][1]), "world size")
	check_eq(w.npcs.size(), wdata["npcs"].size(), "npc count")
	check_eq(w.props.size(), wdata["props"].size(), "prop count")
	var decor := 0
	for k in wdata["decor"]["items"]:
		decor += int(wdata["decor"]["items"][k])
	check_eq(w.decor.size(), decor, "decor count")
	check(w.bounds.encloses(w.player_rect()), "player starts inside bounds")
	for s: Rect2 in w.solids:
		check(not s.intersects(w.player_rect()), "player does not start inside an obstacle")


func test_decor_is_deterministic() -> void:
	var w2 = World.new()
	check_eq(w2.decor, w.decor, "same seed gives the same decor")


func test_walk_reaches_walk_speed() -> void:
	_open_spot()
	var x0: float = w.player_pos.x
	_run(0.5, Vector2.RIGHT)
	check_near(w.speed(), float(tdata["player"]["walk_speed"]), 0.01, "walk speed")
	check(w.player_pos.x > x0, "moved right")
	check_eq(w.facing, 1, "facing right")
	_run(0.5, Vector2.LEFT)
	check_eq(w.facing, -1, "facing left")


func test_trot_is_faster() -> void:
	_open_spot()
	_run(0.5, Vector2.DOWN, true)
	check_near(w.speed(), float(tdata["player"]["run_speed"]), 0.01, "trot speed")
	check(w.running, "running flag")


func test_diagonal_is_not_faster() -> void:
	_open_spot()
	_run(0.4, Vector2(1, 1))
	check_near(w.speed(), float(tdata["player"]["walk_speed"]), 0.01, "diagonal speed")


func test_half_stick_walks_slowly() -> void:
	_open_spot()
	_run(0.4, Vector2(0.5, 0))
	check_near(w.speed(), float(tdata["player"]["walk_speed"]) * 0.5, 0.01, "half stick speed")


func test_stops_when_released() -> void:
	_open_spot()
	_run(0.5, Vector2.RIGHT, true)
	_run(0.25, Vector2.ZERO)
	check_eq(w.speed(), 0.0, "stopped")


func test_obstacle_blocks() -> void:
	var bush: Rect2 = w.props[0]["rect"]
	w.player_pos = Vector2(bush.position.x - 20, bush.end.y)
	_run(2.0, Vector2.RIGHT)
	check(not bush.intersects(w.player_rect()), "never inside the bush")
	check(w.player_rect().end.x <= bush.position.x + 0.01, "stopped at the bush's left side")


func test_slides_along_obstacle() -> void:
	var bush: Rect2 = w.props[1]["rect"]
	w.player_pos = Vector2(bush.position.x - 8, bush.get_center().y + 2)
	var y0: float = w.player_pos.y
	_run(0.5, Vector2(1, 1).normalized())
	check(not bush.intersects(w.player_rect()), "not inside the bush")
	check(w.player_pos.y > y0 + 5, "slid down along the bush")


func test_big_frame_does_not_tunnel() -> void:
	var bush: Rect2 = w.props[0]["rect"]
	w.player_pos = Vector2(bush.position.x - 10, bush.end.y)
	w.player_vel = Vector2(float(tdata["player"]["run_speed"]), 0)
	for i in 5:
		w.step(0.5, Vector2.RIGHT, true)
	check(w.player_rect().end.x <= bush.position.x + 0.01, "a slow frame does not skip through the bush")


func test_stays_in_bounds() -> void:
	for dir in [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]:
		_open_spot()
		_run(8.0, dir, true)
		check(w.bounds.encloses(w.player_rect()), "inside bounds after running %s" % dir)


func test_focus_and_interact() -> void:
	var cow: Dictionary = w.npcs[0]
	var spec: Dictionary = wdata["npcs"][0]
	_open_spot()
	check_eq(w.interact().size(), 0, "nothing to talk to in open grass")
	# Walk up to the cow from the left.
	w.player_pos = Vector2(cow["rect"].position.x - 30, cow["rect"].end.y)
	var events := _run(1.0, Vector2.RIGHT)
	check_eq(w.focus_id, spec["id"], "cow in focus when next to it")
	check(events.any(func(e): return e["type"] == "focus" and e["id"] == spec["id"]), "focus event sent")
	var said: Array = w.interact()
	check_eq(said.size(), 1, "one say event")
	if said.size() == 1:
		check_eq(said[0]["type"], "say", "event type")
		check_eq(said[0]["text_key"], spec["say"], "cow line from world.json")
	# Walk away: focus clears.
	events = _run(1.5, Vector2.LEFT)
	check_eq(w.focus_id, "", "focus cleared when walking away")
	check(events.any(func(e): return e["type"] == "focus" and e["id"] == ""), "focus-cleared event sent")

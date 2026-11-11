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
	check(w.props.size() > wdata["props"].size(), "world.json props plus the tree line (%d)" % w.props.size())
	for i in wdata["props"].size():
		check_eq(w.props[i]["pos"], Vector2(wdata["props"][i]["pos"][0], wdata["props"][i]["pos"][1]), "prop %d in world.json order" % i)
	var most := 0
	for k in wdata["decor"]["items"]:
		most += int(wdata["decor"]["items"][k])
	for cl in wdata["flowers"]["clusters"]:
		most += int(cl["count"])
	check(w.decor.size() <= most and w.decor.size() > most * 0.7, "decor count %d (of up to %d; spots on the path or pond are skipped)" % [w.decor.size(), most])
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


func _npc_spec(id: String) -> Dictionary:
	for n: Dictionary in wdata["npcs"]:
		if n["id"] == id:
			return n
	return {}


## Puts the player `gap` px left of an NPC's footprint, feet level with it.
func _beside(npc: Dictionary, gap: float = 4.0) -> void:
	var r: Rect2 = npc["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - gap, r.end.y)


func test_focus_and_interact() -> void:
	var cow: Dictionary = w.npc_by_id("cow")
	var spec := _npc_spec("cow")
	_open_spot()
	check_eq(w.interact().size(), 0, "nothing to talk to in open grass")
	# Walk up to the cow from the left.
	w.player_pos = Vector2(cow["rect"].position.x - 30, cow["rect"].end.y)
	var events := _run(1.0, Vector2.RIGHT)
	check_eq(w.focus_id, "cow", "cow in focus when next to it")
	check(events.any(func(e): return e["type"] == "focus" and e["id"] == "cow"), "focus event sent")
	var said: Array = w.interact()
	check_eq(said.size(), 1, "one talk event")
	if said.size() == 1:
		check_eq(said[0]["type"], "talk", "event type")
		check_eq(said[0]["dialogue"], spec["dialogue"], "cow's dialogue file from world.json")
	w.end_talk()
	# Walk away: focus clears.
	events = _run(1.5, Vector2.LEFT)
	check_eq(w.focus_id, "", "focus cleared when walking away")
	check(events.any(func(e): return e["type"] == "focus" and e["id"] == ""), "focus-cleared event sent")


func test_talk_radius_from_data() -> void:
	for spec: Dictionary in wdata["npcs"]:
		var npc: Dictionary = w.npc_by_id(spec["id"])
		var radius := float(spec["talk_radius"])
		check_near(radius, 22.0, 4.0, "%s talk radius is about 22 px" % spec["id"])
		_beside(npc, radius - 1.0)
		w.step(0.0, Vector2.ZERO, false)
		check_eq(w.focus_id, spec["id"], "%s in range at %s px" % [spec["id"], radius - 1.0])
		_beside(npc, radius + 2.0)
		w.step(0.0, Vector2.ZERO, false)
		check(w.focus_id != spec["id"], "%s out of range at %s px" % [spec["id"], radius + 2.0])


func test_only_the_nearest_npc_has_focus() -> void:
	var bram: Dictionary = w.npc_by_id("bram")
	var cow: Dictionary = w.npc_by_id("cow")
	# Move the cow next to Bram so both are in range of one spot.
	cow["pos"] = bram["pos"] + Vector2(40, 0)
	cow["rect"] = World.footprint_rect(cow["pos"], cow["footprint"])
	w.solids.assign([bram["rect"], cow["rect"]])
	var between: float = (bram["rect"].end.x + cow["rect"].position.x) / 2.0
	w.player_pos = Vector2(between - 3.0, bram["rect"].end.y)
	w.step(0.0, Vector2.ZERO, false)
	check(w.distance_to_rect(cow["rect"]) <= cow["talk_radius"], "cow in range too")
	check_eq(w.focus_id, "bram", "nearer Bram wins")
	w.player_pos.x = between + 3.0
	w.step(0.0, Vector2.ZERO, false)
	check_eq(w.focus_id, "cow", "nearer cow wins")


func test_talking_locks_movement_and_faces_each_other() -> void:
	var bram: Dictionary = w.npc_by_id("bram")
	_beside(bram)
	w.step(0.0, Vector2.ZERO, false)
	w.facing = -1
	var ev: Array = w.interact()
	check(w.is_talking() and w.talk_id == "bram", "talking to Bram")
	check_eq(w.facing, 1, "Fern turns right towards Bram")
	check_eq(bram["facing"], -1, "Bram turns left towards Fern")
	check_eq(w.interact().size(), 0, "no second conversation while talking")
	var before: Vector2 = w.player_pos
	_run(0.5, Vector2.LEFT, true)
	check_eq(w.player_pos, before, "can't move while talking")
	check_eq(w.speed(), 0.0, "standing still")
	w.end_talk()
	_run(0.3, Vector2.LEFT)
	check(w.player_pos.x < before.x, "moves again after the conversation")
	# From the other side, they face the other way.
	var r: Rect2 = bram["rect"]
	w.player_pos = Vector2(r.end.x + w.player_footprint.x / 2.0 + 3.0, r.end.y)
	w.player_vel = Vector2.ZERO
	w.step(0.0, Vector2.ZERO, false)
	w.interact()
	check(w.facing == -1 and bram["facing"] == 1, "facing each other from the right")


func test_wick_paces_a_loop_and_stops_to_talk() -> void:
	var wick: Dictionary = w.npc_by_id("wick")
	var spec := _npc_spec("wick")
	var path: Array = spec["path"]
	check(path.size() >= 2, "Wick has a pacing path")
	for pt in path:
		var r := World.footprint_rect(Vector2(pt[0], pt[1]), wick["footprint"])
		for p: Dictionary in w.props:
			check(not r.grow(4).intersects(p["rect"]), "path point %s is clear of bushes" % [pt])
	_open_spot()
	var visited := {}
	var start: Vector2 = wick["pos"]
	for i in 60 * 20:
		w.step(1.0 / 60.0, Vector2.ZERO, false)
		for j in path.size():
			if wick["pos"].distance_to(Vector2(path[j][0], path[j][1])) < 0.5:
				visited[j] = true
	check_eq(visited.size(), path.size(), "Wick reaches every point of his loop")
	check(w.solids.has(wick["rect"]), "Wick's footprint is solid where he is now")
	# Talk to him: he stops.
	_beside(wick, 3.0)
	w.step(0.0, Vector2.ZERO, false)
	if w.focus_id == "wick":
		w.interact()
	else:
		w.begin_talk("wick")
	var at: Vector2 = wick["pos"]
	_run(2.0, Vector2.ZERO)
	check_eq(wick["pos"], at, "Wick stands still while talking")
	check(not wick["moving"], "not walking")
	w.end_talk()
	_run(3.0, Vector2.ZERO)
	check(wick["pos"] != at or start == at, "paces again afterwards")


func test_pacer_never_walks_into_the_player() -> void:
	var wick: Dictionary = w.npc_by_id("wick")
	var path: Array = _npc_spec("wick")["path"]
	# Stand on his path, between the first two points.
	var a := Vector2(path[0][0], path[0][1])
	var b := Vector2(path[1][0], path[1][1])
	w.player_pos = (a + b) / 2.0
	w.player_vel = Vector2.ZERO
	for i in 60 * 10:
		w.step(1.0 / 60.0, Vector2.ZERO, false)
		check(not wick["rect"].intersects(w.player_rect()), "Wick never overlaps Fern")
		if failures.size() > 0:
			break


func test_ground_decals_load() -> void:
	check_eq(w.ground.size(), wdata.get("ground", []).size(), "ground decal count")


func test_camera_follows_player() -> void:
	_open_spot()
	var view := Vector2(480, 270)
	w.player_pos = w.size / 2.0
	var r: Rect2 = w.camera_rect(view)
	check(r.has_point(w.player_pos), "player on screen")
	check_near(r.get_center().x, w.player_pos.x, 1.0, "camera centred on the player (x)")
	check_eq(r.position, r.position.floor(), "camera on whole pixels")


func test_camera_limits_cover_every_view() -> void:
	# Every view the game shows stays inside the camera bounds (the meadow
	# plus its forest border) wherever the player is; a view bigger than the
	# bounds is centred on them. The forest is drawn FOREST_REACH further
	# out, so even view.max never shows past it.
	var v: Dictionary = tdata["view"]
	var base := Vector2(v["base"][0], v["base"][1])
	var biggest := Vector2(v["max"][0], v["max"][1])
	var lim: Rect2 = w.camera_bounds()
	check_eq(lim, Rect2(Vector2.ZERO, w.size).grow(float(wdata["border"])), "camera bounds = world + border")
	var WorldView := load("res://scripts/view/world_view.gd")
	check(lim.grow(WorldView.FOREST_REACH).size.x >= biggest.x and lim.grow(WorldView.FOREST_REACH).size.y >= biggest.y, "forest covers view.max %s" % biggest)
	for view in [base, Vector2(633, 293), Vector2(512, 384), Vector2(640, 512), Vector2(1024, 288), biggest]:
		for corner in [Vector2.ZERO, Vector2(w.size.x, 0), w.size, Vector2(0, w.size.y), w.size / 2.0]:
			w.player_pos = corner
			var r: Rect2 = w.camera_rect(view)
			for axis in 2:
				if view[axis] <= lim.size[axis]:
					check(r.position[axis] >= lim.position[axis] and r.end[axis] <= lim.end[axis], "view %s with player at %s stays inside the bounds on axis %d (got %s)" % [view, corner, axis, r])
				else:
					check_near(r.get_center()[axis], lim.get_center()[axis], 1.0, "view %s bigger than the bounds is centred on axis %d" % [view, axis])
			check(lim.grow(WorldView.FOREST_REACH).encloses(r), "forest drawn under view %s at %s" % [view, corner])


func test_the_edge_is_a_tree_line() -> void:
	# Trees on all four sides, at most `spacing` + jitter apart.
	var tl: Dictionary = wdata["tree_line"]
	var gap := float(tl["spacing"]) + float(tl["jitter"]) * 2.0 + 1.0
	var sides := {"top": [], "bottom": [], "left": [], "right": []}
	for p: Dictionary in w.props:
		if not p.has("canopy"):
			continue
		var pos: Vector2 = p["pos"]
		if pos.y < 30:
			sides["top"].append(pos.x)
		elif pos.y > w.size.y:
			sides["bottom"].append(pos.x)
		elif pos.x < 0:
			sides["left"].append(pos.y)
		elif pos.x > w.size.x:
			sides["right"].append(pos.y)
	for side in sides:
		var xs: Array = sides[side]
		xs.sort()
		check(xs.size() >= 8, "%s: a row of trees (%d)" % [side, xs.size()])
		for i in range(1, xs.size()):
			check(xs[i] - xs[i - 1] <= gap, "%s: no gap in the tree line between %s and %s" % [side, xs[i - 1], xs[i]])
	# Only the top row has trunks in the meadow.
	for p: Dictionary in w.props:
		if p.has("canopy") and p["trunk"]:
			check(Rect2(Vector2.ZERO, w.size).grow(1.0).has_point(p["pos"]), "trunk %s is in the meadow" % p["pos"])


func test_landmarks_block_and_npcs_stay_reachable() -> void:
	check(not w.pond.is_empty(), "there is a pond")
	check(w.solids.has(w.pond["rect"]), "the pond is solid")
	var kinds := {}
	for p: Dictionary in w.props:
		kinds[p["type"]] = true
		check(not p["rect"].intersects(w.player_rect()), "Fern doesn't start inside %s" % p["type"])
	for k in ["bush_round", "bush_wide", "bush_small", "rock_big", "log", "tree_a", "tree_b"]:
		check(kinds.has(k), "has a %s" % k)
	var flipped: Array = w.props.filter(func(p): return p["type"].begins_with("bush") and p["flip"])
	check(flipped.size() >= 2, "some bushes are mirrored")
	# Every NPC can be walked up to from the left, clear of every obstacle.
	for npc: Dictionary in w.npcs:
		var r: Rect2 = npc["rect"]
		var spot := World.footprint_rect(Vector2(r.position.x - w.player_footprint.x / 2.0 - 4.0, r.end.y), w.player_footprint)
		for s: Rect2 in w.solids:
			if s != r:
				check(not s.intersects(spot), "%s's talk spot %s is clear (blocked by %s)" % [npc["id"], spot, s])


func test_path_surface_and_tall_grass() -> void:
	var line: Array = wdata["path"]["lines"][0]
	var on := Vector2(line[3][0], line[3][1])
	w.player_pos = on
	check_eq(w.surface(), "path", "on the path at %s" % on)
	_open_spot()
	w.player_pos = Vector2(150, 175)
	check_eq(w.surface(), "grass", "open grass is grass")
	var patch: Array = wdata["tall_grass"]["patches"][0]["rect"]
	w.player_pos = Vector2(patch[0] + patch[2] / 2.0, patch[1] + patch[3] / 2.0)
	check(w.in_tall_grass(), "in the tall grass patch")
	var count := 0
	for p in wdata["tall_grass"]["patches"]:
		count += int(p["count"])
	check_eq(w.tall_grass.size(), count, "tall grass blades from world.json")
	for d: Dictionary in w.decor:
		check(not w.on_path(d["pos"], 1.0), "decor %s at %s is off the path" % [d["art"], d["pos"]])


func test_flowers_grow_in_clusters() -> void:
	var colors := {}
	var near := 0
	var flowers: Array = w.decor.filter(func(d): return str(d["art"]).begins_with("decor.flower_"))
	for d: Dictionary in flowers:
		colors[d["art"]] = true
		for cl in wdata["flowers"]["clusters"]:
			if (d["pos"] as Vector2).distance_to(Vector2(cl["pos"][0], cl["pos"][1])) <= float(cl["radius"]) + 1.0:
				near += 1
				break
	check(colors.size() >= 2 and colors.size() <= 3, "2-3 flower colours (%s)" % [colors.keys()])
	check_eq(near, flowers.size(), "every flower is in a cluster")


func test_brushing_a_bush() -> void:
	var bush: Dictionary = w.props[0]
	var r: Rect2 = bush["rect"]
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 1.0, r.end.y)
	check_eq(w.brushing_prop(), 0, "next to the bush")
	_open_spot()
	check_eq(w.brushing_prop(), -1, "open grass")

extends "res://tests/test_base.gd"
## Dens (C.2, core): the den template (scripts/core/den_layout.gd) for every
## size and nest count, the apprentices' den built from its area file, its
## walls, doorway and nest, and its entrance in camp. Expected values come
## from data/ (tuning.json den, the den file, world.json, strings.json).

const Areas := preload("res://scripts/core/areas.gd")
const World := preload("res://scripts/core/world.gd")
const DenLayout := preload("res://scripts/core/den_layout.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const DT := 1.0 / 60.0
const DEN := "apprentices_den"

var areas
var tuning: Dictionary
var strings: Dictionary


func before_each() -> void:
	areas = Areas.new()
	tuning = JsonData.load_dict("res://data/tuning.json")
	strings = JsonData.load_dict("res://data/strings.json")


func _den():
	return areas.load_world(DEN, tuning)


func _steps(w, seconds: float, move: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		out.append_array(w.step(DT, move, false))
	return out


func test_the_template_works_for_every_size_and_nest_count() -> void:
	for size_name in DenLayout.SIZES:
		for count in [0, 1, 3, 4, 8, 12]:
			var lay := DenLayout.build({"size": size_name, "nests": count, "player_nest": 0}, tuning["den"], {"to": "camp", "spawn": "x"})
			var what := "%s den, %d nests" % [size_name, count]
			var fr: Rect2 = lay["floor_rect"]
			check_eq(fr.size, Vector2(tuning["den"]["sizes"][size_name][0], tuning["den"]["sizes"][size_name][1]), "%s: floor size" % what)
			check_eq(lay["nests"].size(), count, "%s: nest count" % what)
			var rects: Array[Rect2] = []
			for n: Dictionary in lay["nests"]:
				var r: Rect2 = n["rect"]
				check(fr.encloses(r), "%s: nest %s on the floor" % [what, r])
				for w: Rect2 in lay["walls"]:
					check(not w.intersects(r), "%s: nest %s clear of the walls" % [what, r])
				for o in rects:
					check(not o.intersects(r), "%s: nests don't overlap (%s, %s)" % [what, o, r])
				rects.append(r)
			for p: Vector2 in lay["decor_slots"]:
				check(fr.has_point(p), "%s: decor slot %s on the floor" % [what, p])
				for r in rects:
					check(not r.has_point(p), "%s: decor slot %s not on a nest" % [what, p])
			check(lay["decor_slots"].size() >= 4, "%s: decor slots along the walls (%d)" % [what, lay["decor_slots"].size()])
			check_eq(lay["spawns"].has("nest"), count > 0, "%s: a nest spawn when Fern has a nest" % what)


func test_the_apprentices_den_is_built_from_its_file() -> void:
	var w = _den()
	if not check(w != null, "the den loads"):
		return
	var d := JsonData.load_dict(areas.file(DEN))
	check(w.is_indoors(), "a den is indoors")
	check_eq(w.display_name, "Apprentices' den", "its name")
	check_eq(w.interior["size_name"], d["interior"]["size"], "size from the file")
	check_eq(w.interior["nests"].size(), int(d["interior"]["nests"]), "nests from the file")
	check(w.interior["nests"].size() >= 3, "a few nests")
	check_eq(w.surface(), "path", "earth underfoot (footsteps)")
	check(w.hunt == null and w.pile.is_empty() and w.pond.is_empty(), "no mice, pile or pond inside")
	# About one screen: the phone sees most of it, a desktop a bit less.
	var view_rows := float(tuning["view"]["target_rows"])
	check(w.size.y <= view_rows * 1.4 and w.size.y >= view_rows * 0.8, "about one screen high (%s)" % w.size)


func test_walls_keep_fern_in_except_the_doorway() -> void:
	var w = _den()
	var fr: Rect2 = w.interior["floor_rect"]
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		w.player_pos = fr.get_center() + Vector2(-60, -10)
		w.player_vel = Vector2.ZERO
		var ev := _steps(w, 5.0, dir)
		check(fr.grow(1.0).encloses(w.player_rect()), "walking %s stays on the floor (%s)" % [dir, w.player_pos])
		check(not ev.any(func(e): return e["type"] == "exit"), "no way out but the doorway (%s)" % dir)


func test_the_doorway_leads_back_to_camp() -> void:
	var w = _den()
	var d := JsonData.load_dict(areas.file(DEN))
	check_eq(w.exits.size(), 1, "one way out")
	var e: Dictionary = w.exits[0]
	check_eq(e["to"], d["door"]["to"], "to camp")
	check_eq(e["spawn"], d["door"]["spawn"], "outside the entrance")
	var door: Rect2 = e["rect"]
	check(door.size.x + 6.0 >= 32.0, "the doorway is at least two tiles wide (%s)" % door.size.x)
	check(door.position.y > w.interior["floor_rect"].end.y - 1.0, "in the bottom wall")
	w.place_at_spawn("inside")
	var ev := _steps(w, 3.0, Vector2.DOWN)
	var out: Array = ev.filter(func(x): return x["type"] == "exit")
	check_eq(out.size(), 1, "walking down through the doorway leaves once")
	var camp = areas.load_world("camp", tuning)
	check(camp.spawns.has(e["spawn"]), "camp has the spawn outside the entrance")


func test_fern_has_her_nest() -> void:
	var w = _den()
	var mine: Array = w.interior["nests"].filter(func(n): return n["mine"])
	if not check_eq(mine.size(), 1, "one nest is marked as Fern's"):
		return
	w.place_at_spawn("nest")
	w.step(0.0, Vector2.ZERO, false)
	check_eq(w.focus_kind(), "spot", "her nest has the prompt")
	check_eq(w.focus_id, DenLayout.PLAYER_NEST_SPOT, "it's her nest")
	var ev: Array = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "message" and ev[0]["key"] == "den.your_nest", "interact: %s" % [ev])
	check_eq(str(strings["den.your_nest"]), "Your nest.", "the nest's line")
	# Other nests say nothing.
	for n: Dictionary in w.interior["nests"]:
		if not n["mine"]:
			w.player_pos = n["pos"]
			w.step(0.0, Vector2.ZERO, false)
			check(w.focus_id == "", "another cat's nest has no prompt")
			break


func test_apply_interior_rebuilds_the_room() -> void:
	var w = _den()
	var s: Dictionary = w.interior["settings"].duplicate()
	s["nests"] = 6
	s["size"] = "large"
	w.apply_interior(s)
	check_eq(w.interior["nests"].size(), 6, "six nests now")
	check_eq(w.interior["size_name"], "large", "large now")
	check(w.bounds.encloses(w.player_rect()), "Fern still inside")
	check_eq(w.exits.size(), 1, "still one doorway")
	check(w.spawns.has("nest"), "still a nest spawn")


func test_the_entrance_in_camp() -> void:
	var w = areas.load_world("camp", tuning)
	var den: Dictionary = {}
	for p: Dictionary in w.props:
		if p["type"] == "den_fern":
			den = p
	if not check(not den.is_empty(), "a fern-clump den in camp"):
		return
	# At the camp's edge.
	check(den["pos"].y < w.size.y * 0.3, "at the camp's (top) edge")
	var e: Dictionary = {}
	for x: Dictionary in w.exits:
		if x["to"] == DEN:
			e = x
	if not check(not e.is_empty(), "an exit into the den"):
		return
	# The gap between the clump's walls is at least two tiles wide.
	var left := -INF
	var right := INF
	for s: Rect2 in w.solids:
		if s.end.y > e["rect"].position.y and s.position.y < e["rect"].end.y:
			if s.end.x <= e["rect"].position.x + 1.0:
				left = maxf(left, s.end.x)
			elif s.position.x >= e["rect"].end.x - 1.0:
				right = minf(right, s.position.x)
	check(right - left >= 32.0, "the entrance gap is at least two tiles wide (%s px)" % (right - left))
	# Facing the clearing: the way in is from below, where the path comes.
	var sp: Dictionary = w.spawns["from_apprentices_den"]
	check(sp["pos"].y > e["rect"].end.y, "the spawn outside is in front of (below) the entrance")
	check(w.on_path(e["rect"].get_center(), 4.0), "a worn path leads in")
	# The prompt shows the den's name, and interact goes in.
	w.place_at_spawn("from_apprentices_den")
	w.player_pos.x = e["rect"].get_center().x
	w.step(0.0, Vector2.ZERO, false)
	var door: Dictionary = w.spot_by_id(w.focus_id)
	if check(not door.is_empty(), "the doorway has the prompt (focus %s)" % w.focus_id):
		check_eq(str(strings.get(door["label"], "")), "Apprentices' den", "the prompt names the den")
		var ev: Array = w.interact()
		check(ev.size() == 1 and ev[0]["type"] == "exit" and ev[0]["to"] == DEN, "interact goes in (%s)" % [ev])
	# Walking up into the gap goes in too.
	w.place_at_spawn("from_apprentices_den")
	var ev2 := _steps(w, 0.3, Vector2.LEFT)
	w.player_pos.x = e["rect"].get_center().x
	ev2 = _steps(w, 3.0, Vector2.UP)
	var ins: Array = ev2.filter(func(x): return x["type"] == "exit")
	check(ins.size() == 1 and ins[0]["to"] == DEN and ins[0]["spawn"] == "inside", "walking in enters the den (%s)" % [ins])


func test_the_door_prompt_keeps_clear_of_the_cats() -> void:
	var w = areas.load_world("camp", tuning)
	var sp: Dictionary = w.spot_by_id("apprentices_den_door")
	for npc: Dictionary in w.npcs:
		if World.talkable(npc):
			var gap: float = maxf(0.0, maxf(npc["rect"].position.y - sp["rect"].end.y, sp["rect"].position.y - w.npc_zone(npc).end.y))
			gap = maxf(gap, maxf(w.npc_zone(npc).position.x - sp["rect"].end.x, sp["rect"].position.x - w.npc_zone(npc).end.x))
			check(gap > sp["talk_radius"] + npc["talk_radius"] + w.player_footprint.x, "%s far from the den door (%s px)" % [npc["id"], gap])

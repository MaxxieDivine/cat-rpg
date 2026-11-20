extends "res://tests/test_base.gd"
## Hunger and thirst (scripts/core/needs.gd), the fresh-catch pile and
## drinking at the pond (scripts/core/world.gd). Expected values come from
## data/tuning.json "needs" and data/world.json.

const Needs := preload("res://scripts/core/needs.gd")
const World := preload("res://scripts/core/world.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var nt: Dictionary
var wdata: Dictionary
var n
var w


func before_each() -> void:
	nt = JsonData.load_dict("res://data/tuning.json")["needs"]
	wdata = JsonData.load_dict("res://data/world.json")
	n = Needs.new()
	w = World.new()


func _steps(seconds: float, dt: float = 1.0 / 60.0) -> void:
	for i in roundi(seconds / dt):
		n.step(dt)


# --- Needs


func test_needs_start_from_tuning() -> void:
	check_eq(n.hunger, int(nt["start"]), "hunger starts at tuning start")
	check_eq(n.thirst, int(nt["start"]), "thirst starts at tuning start")
	check_eq(n.max_value, int(nt["max"]), "max")


func test_needs_drop_one_point_per_interval() -> void:
	var he := float(nt["hunger_every_s"])
	var te := float(nt["thirst_every_s"])
	_steps(minf(he, te) - 0.1)
	check_eq(n.hunger, int(nt["start"]), "no hunger lost before %s s" % he)
	check_eq(n.thirst, int(nt["start"]), "no thirst lost before %s s" % te)
	n.reset()
	_steps(he * te * 2.0 + 0.1, 0.05)
	check_eq(n.hunger, int(nt["start"]) - int(te * 2.0), "hunger -1 every %s s" % he)
	check_eq(n.thirst, int(nt["start"]) - int(he * 2.0), "thirst -1 every %s s" % te)


func test_needs_long_frames_still_count_every_point() -> void:
	# A slow frame (or a tab coming back) must not drop points.
	n.step(float(nt["thirst_every_s"]) * 3.0)
	check_eq(n.thirst, int(nt["start"]) - 3, "three thirst points in one long step")


func test_needs_stop_at_zero_and_cap_at_max() -> void:
	_steps(1000.0, 0.5)
	check_eq(n.hunger, 0, "hunger stops at 0")
	check_eq(n.thirst, 0, "thirst stops at 0")
	check(n.is_low(n.hunger), "0 is low")
	n.eat()
	check_eq(n.hunger, int(nt["eat"]), "eating gives %s" % nt["eat"])
	n.drink()
	check_eq(n.thirst, int(nt["drink"]), "drinking gives %s" % nt["drink"])
	for i in 4:
		n.eat()
		n.drink()
	check_eq(n.hunger, int(nt["max"]), "hunger capped at max")
	check_eq(n.thirst, int(nt["max"]), "thirst capped at max")


func test_rates_can_change_while_running() -> void:
	n.hunger_every_s = 1.0
	_steps(3.05, 0.05)
	check_eq(n.hunger, int(nt["start"]) - 3, "a new rate applies at once")
	n.thirst_every_s = 0.0
	var t: int = n.thirst
	_steps(30.0, 0.5)
	check_eq(n.thirst, t, "rate 0 = no loss")


# --- The fresh-catch pile


func _next_to_pile() -> void:
	var r: Rect2 = w.pile["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 4.0, r.end.y)
	w.step(0.0, Vector2.ZERO, false)


func test_pile_loads_from_world_json() -> void:
	var fc: Dictionary = wdata["fresh_catch"]
	check(not w.pile.is_empty(), "the pile exists")
	check_eq(w.pile["prey"], int(fc["prey"]), "starts with world.json prey")
	check_eq(w.pile["max"], int(fc["max"]), "holds up to world.json max")
	check(int(fc["prey"]) < int(fc["max"]), "room on the pile for hunted prey")
	check_eq(w.pile["talk_radius"], float(fc["talk_radius"]), "same radius as the cats")
	check_near(float(fc["talk_radius"]), 22.0, 0.1, "radius 22 like the NPCs")
	check(w.solids.has(w.pile["rect"]), "its footprint (at its base) blocks Fern")


func test_pile_keeps_clear_of_the_cats() -> void:
	# No spot is in range of both the pile and a cat (wherever a pacer is
	# on its loop), so prompts don't fight.
	var start: Vector2 = w.player_pos
	var pr: float = w.pile["talk_radius"]
	var area: Rect2 = w.pile["rect"].grow(pr + w.player_footprint.x)
	for npc: Dictionary in w.npcs:
		var zone: Rect2 = w.npc_zone(npc)
		var both := 0
		for y in range(int(area.position.y), int(area.end.y)):
			for x in range(int(area.position.x), int(area.end.x)):
				w.player_pos = Vector2(x, y)
				if w.distance_to_rect(w.pile["rect"]) <= pr and w.distance_to_rect(zone) <= npc["talk_radius"]:
					both += 1
		check_eq(both, 0, "spots in range of both the pile and %s" % npc["id"])
	check(not w.on_path(w.pile["pos"], 4.0), "pile is off the path")
	w.player_pos = start
	check(w.distance_to_rect(w.pile["rect"]) > pr, "Fern doesn't start at the pile")


func test_pile_focus_at_the_npc_radius() -> void:
	var r: Rect2 = w.pile["rect"]
	var radius: float = w.pile["talk_radius"]
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - (radius - 1.0), r.end.y)
	w.step(0.0, Vector2.ZERO, false)
	check_eq(w.focus_id, World.PILE_ID, "pile in range at %s px" % (radius - 1.0))
	check_eq(w.focus_kind(), "pile", "focus kind")
	w.player_pos.x -= 3.0
	w.step(0.0, Vector2.ZERO, false)
	check(w.focus_id != World.PILE_ID, "pile out of range past %s px" % radius)


func test_eating_from_the_pile() -> void:
	_next_to_pile()
	n.hunger = 30
	w.facing = -1
	var ev: Array = w.interact(n)
	check(ev.any(func(e): return e["type"] == "eat"), "eat event")
	check_eq(n.hunger, 30 + int(nt["eat"]), "+%s hunger" % nt["eat"])
	check_eq(w.pile["prey"], int(wdata["fresh_catch"]["prey"]) - 1, "one prey gone")
	check_eq(w.facing, 1, "Fern faces the pile")
	check(w.is_busy(), "eating takes a moment")
	var x: float = w.player_pos.x
	for i in roundi(float(nt["eat_s"]) * 60.0) - 2:
		w.step(1.0 / 60.0, Vector2.LEFT, true)
	check_eq(w.player_pos.x, x, "can't walk off mid-bite")
	check_eq(w.interact(n).size(), 0, "no second bite while eating")
	var done: Array[Dictionary] = []
	for i in 4:
		done.append_array(w.step(1.0 / 60.0, Vector2.ZERO, false))
	check(not w.is_busy(), "done after eat_s")
	check(done.any(func(e): return e["type"] == "action_done"), "action_done event")


func test_eating_caps_hunger_at_max() -> void:
	_next_to_pile()
	n.hunger = int(nt["full_above"])
	w.interact(n)
	check_eq(n.hunger, int(nt["max"]), "capped at max")


func test_not_hungry_keeps_the_prey() -> void:
	_next_to_pile()
	n.hunger = int(nt["full_above"]) + 1
	var ev: Array = w.interact(n)
	check_eq(ev.size(), 1, "one event")
	check_eq(str(ev[0].get("key", "")), "needs.not_hungry", "'You're not hungry' line")
	check_eq(w.pile["prey"], int(wdata["fresh_catch"]["prey"]), "no prey wasted")
	check(not w.is_busy(), "no eating")


func test_empty_pile_says_so() -> void:
	_next_to_pile()
	for i in w.pile["max"]:
		n.hunger = 0
		w.interact(n)
		w.action_t = 0.0
		w.action = ""
	check_eq(w.pile["prey"], 0, "pile emptied")
	n.hunger = 10
	var ev: Array = w.interact(n)
	check_eq(str(ev[0].get("key", "")), "needs.pile_empty", "'The pile is empty' line")
	check_eq(n.hunger, 10, "nothing eaten")


func test_pile_never_refills_by_itself() -> void:
	check(not wdata["fresh_catch"].has("refill_s"), "no refill timer in world.json")
	w.pile["prey"] = 3
	for i in 60 * 10 * 3:
		w.step(0.1, Vector2.ZERO, false)
	check_eq(w.pile["prey"], 3, "only hunting refills the pile")

func test_strings_for_the_pile_exist() -> void:
	var s := JsonData.load_dict("res://data/strings.json")
	for k in ["needs.pile_empty", "needs.not_hungry"]:
		check(s.has(k) and str(s[k]) != "", "strings.json has %s" % k)


# --- Drinking


## Fern on each side of the pond, just outside its solid rect.
func _pond_sides() -> Dictionary:
	var r: Rect2 = w.pond["rect"]
	var fp: Vector2 = w.player_footprint
	var c := r.get_center()
	return {
		"north": Vector2(c.x, r.position.y - 2.0),
		"south": Vector2(c.x, r.end.y + fp.y + 2.0),
		"west": Vector2(r.position.x - fp.x / 2.0 - 2.0, c.y + fp.y / 2.0),
		"east": Vector2(r.end.x + fp.x / 2.0 + 2.0, c.y + fp.y / 2.0),
	}


func test_drink_from_every_side_of_the_pond() -> void:
	var sides := _pond_sides()
	for side: String in sides:
		w = World.new()
		n = Needs.new()
		w.player_pos = sides[side]
		w.player_vel = Vector2.ZERO
		for s: Rect2 in w.solids:
			check(not s.intersects(w.player_rect()), "%s: the spot is free" % side)
		w.step(0.0, Vector2.ZERO, false)
		check_eq(w.focus_id, World.POND_ID, "%s: pond in focus" % side)
		n.thirst = 20
		var ev: Array = w.interact(n)
		check(ev.any(func(e): return e["type"] == "drink"), "%s: drink event" % side)
		check_eq(n.thirst, 20 + int(nt["drink"]), "%s: +%s thirst" % [side, nt["drink"]])
		check(w.is_busy(), "%s: drinking takes a moment" % side)
		if side == "west":
			check_eq(w.facing, 1, "west: faces the water (right)")
		elif side == "east":
			check_eq(w.facing, -1, "east: faces the water (left)")


func test_pond_never_runs_out_and_caps_thirst() -> void:
	w.player_pos = _pond_sides()["north"]
	w.step(0.0, Vector2.ZERO, false)
	for i in 6:
		w.interact(n)
		w.action = ""
		w.action_t = 0.0
	check_eq(n.thirst, int(nt["max"]), "thirst capped; the pond still works")


func test_pond_out_of_reach_from_afar() -> void:
	var p: Vector2 = _pond_sides()["north"]
	w.player_pos = p - Vector2(0, w.drink_radius + 3.0)
	w.step(0.0, Vector2.ZERO, false)
	check(w.focus_id != World.POND_ID, "too far to drink")


# --- Priority


func test_nearest_of_cat_and_pile_wins() -> void:
	var bram: Dictionary = w.npc_by_id("bram")
	var pr: Rect2 = w.pile["rect"]
	# Bram sits just right of the pile, so one spot is in range of both.
	bram["pos"] = Vector2(pr.end.x + 40.0, pr.end.y)
	bram["rect"] = World.footprint_rect(bram["pos"], bram["footprint"])
	var between: float = (pr.end.x + bram["rect"].position.x) / 2.0
	w.player_pos = Vector2(between - 3.0, pr.end.y + 8.0)
	w.step(0.0, Vector2.ZERO, false)
	check(w.distance_to_rect(bram["rect"]) <= bram["talk_radius"], "Bram in range too")
	check_eq(w.focus_id, World.PILE_ID, "nearer pile wins")
	w.player_pos.x = between + 3.0
	w.step(0.0, Vector2.ZERO, false)
	check_eq(w.focus_id, "bram", "nearer Bram wins")
	var ev: Array = w.interact(n)
	check(ev.any(func(e): return e["type"] == "talk"), "interact talks to the focused cat")
	check_eq(w.pile["prey"], int(wdata["fresh_catch"]["prey"]), "and doesn't eat")


func test_collapsed_at_zero_and_restore() -> void:
	var t: Dictionary = JsonData.load_dict("res://data/tuning.json")["needs"]
	var n = Needs.new(t)
	check(not n.collapsed(), "not collapsed at the start")
	n.hunger = 0
	check(n.collapsed(), "hunger at 0 collapses")
	n.hunger = 40
	n.thirst = 0
	check(n.collapsed(), "thirst at 0 collapses")
	n.restore()
	check_eq(n.hunger, int(t["restore_hunger"]), "hunger restored")
	check_eq(n.thirst, int(t["restore_thirst"]), "thirst restored")
	check(not n.collapsed(), "rested")


## Milestone 1.1: a trip to the Hunting Grounds (about a minute of walking
## plus 3 minutes there) fits in a full bar of either need, with room left.
func test_full_bars_last_a_hunting_trip() -> void:
	var t: Dictionary = JsonData.load_dict("res://data/tuning.json")["needs"]
	var trip_s := 4.0 * 60.0
	check(float(t["max"]) * float(t["hunger_every_s"]) >= trip_s * 1.5, "a full hunger bar lasts 1.5 trips")
	check(float(t["max"]) * float(t["thirst_every_s"]) >= trip_s * 1.5, "a full thirst bar lasts 1.5 trips")

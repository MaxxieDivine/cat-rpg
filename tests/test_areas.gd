extends "res://tests/test_base.gd"
## Areas and walking between them (core, headless): every area in
## data/areas.json loads; spawns are clear, exits lead to real spawns and can
## be walked into; arriving never bounces Fern straight back; the Hunting
## Grounds has what Milestone 1.1 asks for; the scatter is deterministic and
## keeps clear of paths, colliders, exits and spawns. Plus travel.gd (fades,
## passing out) and player_state.gd.

const Areas := preload("res://scripts/core/areas.gd")
const World := preload("res://scripts/core/world.gd")
const Travel := preload("res://scripts/core/travel.gd")
const PlayerState := preload("res://scripts/core/player_state.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")
const DT := 1.0 / 60.0

var areas
var tuning: Dictionary


func before_each() -> void:
	areas = Areas.new()
	tuning = JsonData.load_dict("res://data/tuning.json")


func _world(id: String):
	return areas.load_world(id, tuning)


func test_every_area_loads() -> void:
	check(areas.has(areas.start_area()), "the start area is listed")
	check(areas.ids().size() >= 2, "camp and the Hunting Grounds (%s)" % [areas.ids()])
	for id in areas.ids():
		var w = _world(id)
		if not check(w != null, "%s loads" % id):
			continue
		check_eq(w.id, id, "%s: the file's id matches areas.json" % id)
		check(w.display_name != "", "%s has a name" % id)
		check(not AssetCatalog.is_placeholder(AssetCatalog.texture(w.ground_art)), "%s: ground art %s loads" % [id, w.ground_art])
		check(w.spawns.has("start"), "%s: has a start spawn" % id)


func test_spawns_are_clear() -> void:
	for id in areas.ids():
		var w = _world(id)
		for n: String in w.spawns:
			w.place_at_spawn(n)
			var r: Rect2 = w.player_rect()
			check(w.bounds.encloses(r), "%s/%s: inside the bounds" % [id, n])
			for s: Rect2 in w.solids:
				check(not s.intersects(r), "%s/%s: not inside a collider %s" % [id, n, s])
			check(w.exit_at_player().is_empty(), "%s/%s: not on an exit" % [id, n])
			check(w.exits_armed, "%s/%s: exits armed off an exit" % [id, n])


func test_exits_lead_to_real_spawns() -> void:
	for id in areas.ids():
		var w = _world(id)
		for e: Dictionary in w.exits:
			check(areas.has(e["to"]), "%s/%s leads to a listed area (%s)" % [id, e["id"], e["to"]])
			var there = _world(e["to"])
			if there != null:
				check(there.spawns.has(e["spawn"]), "%s/%s: spawn '%s' exists in %s" % [id, e["id"], e["spawn"], e["to"]])
			var r: Rect2 = e["rect"]
			check(w.bounds.intersects(r), "%s/%s: Fern can reach the exit rect" % [id, e["id"]])
			check(w.on_path(r.get_center(), 4.0), "%s/%s: a worn path leads into the exit" % [id, e["id"]])


## Arriving through an exit, Fern faces away from it, and walking straight
## back gets her there again: no stuck spawns. Every exit is walked into from
## the spawn the matching exit on the other side sends her to.
func test_round_trips_walk_into_every_exit() -> void:
	# The prisoner den is reached only by being caught (a story fade), so
	# its doorway has no exit leading back.
	var one_way := str(JsonData.load_dict("res://data/story.json").get("rescue", {}).get("prison_area", ""))
	for id in areas.ids():
		if id == one_way:
			continue
		var w = _world(id)
		for e: Dictionary in w.exits:
			var there = _world(e["to"])
			if there == null or not there.spawns.has(e["spawn"]):
				continue
			check(there.place_at_spawn(e["spawn"]), "%s: placed at %s" % [e["to"], e["spawn"]])
			# Facing away from the exit that leads back.
			var back := _exit_to(there, id)
			if check(not back.is_empty(), "%s has an exit back to %s" % [e["to"], id]):
				var away := signf(there.player_pos.x - (back["rect"] as Rect2).get_center().x)
				check_eq(there.facing, int(away), "%s/%s faces away from the exit back" % [e["to"], e["spawn"]])
				# Walking away isn't blocked.
				var from: Vector2 = there.player_pos
				for i in 30:
					there.step(DT, Vector2(away, 0), false)
				check(there.player_pos.distance_to(from) > 15.0, "%s/%s: Fern can walk away from the spawn" % [e["to"], e["spawn"]])
				# And walking back in leaves.
				var got := _walk_into(there, back)
				check(got, "%s: walking from %s reaches the exit to %s" % [e["to"], e["spawn"], id])


func _exit_to(w, area: String) -> Dictionary:
	for e: Dictionary in w.exits:
		if e["to"] == area:
			return e
	return {}


func _walk_into(w, e: Dictionary) -> bool:
	for i in 300:
		var to: Vector2 = (e["rect"] as Rect2).get_center() - w.player_pos
		for ev in w.step(DT, to.normalized(), false):
			if ev["type"] == "exit":
				return ev["id"] == e["id"]
	return false


func test_exit_fires_once_and_only_after_stepping_clear() -> void:
	var w = _world("camp")
	var e: Dictionary = w.exits[0]
	var r: Rect2 = e["rect"]
	# Dropped right on the exit (e.g. a bad spawn): no exit until she steps off.
	w.player_pos = Vector2(r.get_center().x, r.end.y - 1.0)
	w.exits_armed = false
	var fired := 0
	for i in 20:
		for ev in w.step(DT, Vector2.ZERO, false):
			fired += 1 if ev["type"] == "exit" else 0
	check_eq(fired, 0, "standing on an exit after arriving does nothing")
	for i in 40:
		w.step(DT, Vector2.LEFT, false)
	check(w.exits_armed, "stepping clear arms the exits")
	for i in 120:
		for ev in w.step(DT, Vector2.RIGHT, false):
			if ev["type"] == "exit":
				fired += 1
				check_eq(ev["to"], e["to"], "exit event names the area")
				check_eq(ev["spawn"], e["spawn"], "exit event names the spawn")
	check_eq(fired, 1, "pushing into the exit fires it once")


func test_camera_bounds_per_area() -> void:
	var camp = _world("camp")
	var hunt = _world("hunting_grounds")
	check(camp.camera_bounds() != hunt.camera_bounds(), "each area has its own camera bounds")
	check(hunt.camera_bounds().encloses(Rect2(Vector2.ZERO, hunt.size)), "camera bounds cover the Hunting Grounds")


func test_hunting_grounds_layout() -> void:
	var w = _world("hunting_grounds")
	var base := Vector2(480, 270)
	var screens: float = (w.size.x * w.size.y) / (base.x * base.y)
	check(screens >= 2.0 and screens <= 3.5, "about 2-3 screens big (%.1f)" % screens)
	check(w.pond.is_empty(), "no water here yet")
	check(w.pile.is_empty(), "no fresh-catch pile")
	check(w.npcs.is_empty(), "no cats")
	check(w.tall_grass_patches.size() >= 3, "patches of tall grass (%d)" % w.tall_grass_patches.size())
	var kinds := {}
	for p: Dictionary in w.props:
		kinds[p["type"]] = int(kinds.get(p["type"], 0)) + 1
	for k in ["bush_round", "rock_big", "rock_small", "log"]:
		check(kinds.has(k), "has a %s" % k)
	check(w.prey_spots.size() >= 3 and w.prey_spots.size() <= 4, "3-4 prey spots (%d)" % w.prey_spots.size())
	for ps: Dictionary in w.prey_spots:
		var near := false
		for r: Rect2 in w.tall_grass_patches:
			near = near or r.grow(24.0).has_point(ps["pos"])
		check(near, "prey spot %s is in or near tall grass" % ps["id"])
		check(w.bounds.has_point(ps["pos"]), "prey spot %s is inside the area" % ps["id"])
	# A different colour mood: golden ground and grade.
	var d: Dictionary = areas.area_data("hunting_grounds")
	check_eq(str(d["ground_paint"].get("ramp", "grass")), "grass_gold", "golden grass")
	var pal := JsonData.load_dict("res://data/palette.json")
	check(Color(str(w.grade.get("afternoon", "#ffffff"))) != Color(str(pal["grade"]["afternoon"])), "its own afternoon grade")


## Hunting Grounds 2 (Patrols Part A): joined to the first Hunting Grounds,
## hunting like it, and the edge of the territory: a stream Fern can't
## cross, another Clan's ground and a line of bracken past it.
func test_hunting_grounds_2_layout() -> void:
	var w = _world("hunting_grounds_2")
	if not check(w != null, "Hunting Grounds 2 loads"):
		return
	var hg = _world("hunting_grounds")
	check(not _exit_to(hg, "hunting_grounds_2").is_empty(), "the first Hunting Grounds leads to it")
	check(not _exit_to(w, "hunting_grounds").is_empty(), "and it leads back")
	check(_exit_to(w, "camp").is_empty(), "not straight to camp: through the first grounds")
	var base := Vector2(480, 270)
	var screens: float = (w.size.x * w.size.y) / (base.x * base.y)
	check(screens >= 2.0 and screens <= 3.5, "about 2-3 screens big (%.1f)" % screens)
	# Hunting works the same way.
	check(w.hunt != null, "it has mice")
	check(w.prey_spots.size() >= 3 and w.prey_spots.size() <= 4, "3-4 prey spots (%d)" % w.prey_spots.size())
	for ps: Dictionary in w.prey_spots:
		var near := false
		for r: Rect2 in w.tall_grass_patches:
			near = near or r.grow(24.0).has_point(ps["pos"])
		check(near, "prey spot %s is in or near tall grass" % ps["id"])
		check(w.bounds.has_point(ps["pos"]) and not w.beyond_border(ps["pos"]), "prey spot %s is on our side" % ps["id"])
	# The border: a stream all the way across, another Clan's ground past it.
	check(not w.stream.is_empty(), "a stream marks the border")
	check_eq(w.border_side, "north", "the far side is north")
	var pts: PackedVector2Array = w.stream["points"]
	check(pts[0].x <= 0.0 and pts[pts.size() - 1].x >= w.size.x, "the stream runs edge to edge")
	check(w.beyond_border(Vector2(400, 40)) and not w.beyond_border(Vector2(400, 300)), "north of the stream is past the border")
	var d: Dictionary = areas.area_data("hunting_grounds_2")
	check(str(d["territory"]["ramp"]) != str(d["ground_paint"]["ramp"]), "the far side has its own grass colour")
	var plants: Array = w.decor.filter(func(e): return e["art"] == "decor.bracken")
	check(plants.size() * 12 >= int(w.size.x), "bracken all along the far bank (%d)" % plants.size())
	for e: Dictionary in plants:
		check(w.beyond_border(e["pos"]) and absf(e["pos"].y - w.stream_y(e["pos"].x)) < 20.0, "bracken at %s is on the far bank" % e["pos"])
	for e: Dictionary in w.decor:
		check(not w.in_stream(e["pos"]), "no decor in the water (%s)" % e["pos"])
	# Fern can't cross: walking north anywhere stops at the near bank. (A
	# game with no story yet: the rogue isn't standing by the water.)
	w = areas.load_world("hunting_grounds_2", tuning, GameStateCore.new())
	for x in [60.0, 300.0, 520.0, 840.0]:
		w.place_at_spawn("start")
		w.player_pos = Vector2(x, w.stream_y(x) + 40.0)
		for i in 240:
			w.step(DT, Vector2.UP, false)
		check(not w.beyond_border(w.player_pos) and not w.in_stream(w.player_pos), "x=%d: stopped on the near bank (%s)" % [x, w.player_pos])
		check(w.player_pos.y - w.stream_y(x) < 20.0, "x=%d: right up at the water (%.0f px off)" % [x, w.player_pos.y - w.stream_y(x)])


## camp -> Hunting Grounds -> Hunting Grounds 2 and back, all on foot.
func test_walk_camp_to_hunting_grounds_2_and_back() -> void:
	var route := ["camp", "hunting_grounds", "hunting_grounds_2", "hunting_grounds", "camp"]
	var w = _world("camp")
	for i in range(1, route.size()):
		var e := _exit_to(w, route[i])
		if not check(not e.is_empty(), "%s has an exit to %s" % [route[i - 1], route[i]]):
			return
		# Walk there from wherever Fern arrived.
		var got := false
		for n in 2000:
			var to: Vector2 = (e["rect"] as Rect2).get_center() - w.player_pos
			var mv := to.normalized()
			for ev in w.step(DT, mv, true):
				got = got or (ev["type"] == "exit" and ev["to"] == route[i])
			if got:
				break
		check(got, "walked from %s into the exit to %s" % [route[i - 1], route[i]])
		var next = _world(route[i])
		next.place_at_spawn(e["spawn"])
		w = next


func test_scatter_is_deterministic_and_keeps_clear() -> void:
	var a = _world("hunting_grounds")
	var b = _world("hunting_grounds")
	check_eq(a.decor, b.decor, "same seed, same scatter")
	check_eq(a.props.size(), b.props.size(), "same scattered props")
	var hand: int = areas.area_data("hunting_grounds")["props"].size()
	var scattered: Array = a.props.slice(hand).filter(func(p): return not p.has("canopy"))
	check(scattered.size() >= 3, "small rocks scattered (%d)" % scattered.size())
	for p: Dictionary in scattered:
		check(not a.on_path(p["pos"], 2.0), "scattered %s at %s is off the path" % [p["type"], p["pos"]])
		for e: Dictionary in a.exits:
			check(not (e["rect"] as Rect2).grow(16).intersects(p["rect"]), "scattered %s clear of exit %s" % [p["type"], e["id"]])
		var hits := 0
		for s: Rect2 in a.solids:
			if s != p["rect"] and s.intersects(p["rect"].grow(4)):
				hits += 1
		check_eq(hits, 0, "scattered %s at %s doesn't touch another collider" % [p["type"], p["pos"]])
	for d: Dictionary in a.decor:
		check(not a.on_path(d["pos"], 1.0), "decor %s off the path" % d["pos"])


func test_fern_recovers_in_her_nest() -> void:
	var ra: String = str(tuning["collapse"]["recovery_area"])
	var rs: String = str(tuning["collapse"]["recovery_spawn"])
	check_eq(ra, "apprentices_den", "Fern recovers in the apprentices' den")
	check_eq(rs, "nest", "in her nest")
	var w = _world(ra)
	if not check(w != null and w.spawns.has(rs), "%s has the recovery spawn '%s'" % [ra, rs]):
		return
	var mine: Array = w.interior["nests"].filter(func(n): return n["mine"])
	check_eq(mine.size(), 1, "one nest is Fern's")
	if mine.size() == 1:
		check_eq(w.spawns[rs]["pos"], mine[0]["pos"], "the recovery spawn is her nest")


# --- travel.gd


func _run(t, seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in roundi(seconds * 60.0):
		out.append_array(t.step(DT))
	return out


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e["type"])


func test_exit_fade_out_load_fade_in() -> void:
	var t = Travel.new(tuning)
	check_eq(t.fade_s, float(tuning["travel"]["fade_s"]), "fade from tuning.json")
	check(t.go("hunting_grounds", "from_camp"), "starts")
	check(not t.go("camp", "start"), "a second exit can't start mid-fade")
	_run(t, t.fade_s / 2.0)
	check_near(t.black(), 0.5, 0.06, "half dark half way")
	var ev := _run(t, t.fade_s / 2.0 + 0.02)
	check_eq(_types(ev), ["load"], "load at full black")
	check_eq(ev[0]["area"], "hunting_grounds", "load names the area")
	check_eq(ev[0]["spawn"], "from_camp", "load names the spawn")
	check(not ev[0]["collapsed"], "not a collapse")
	ev = _run(t, t.fade_s)
	check(_types(ev).has("done"), "fades back in")
	check(not t.busy(), "control back")
	check_eq(t.black(), 0.0, "clear again")


func test_collapse_sequence() -> void:
	var t = Travel.new(tuning)
	check(t.collapse("camp", "den"), "starts")
	check(not t.collapse("camp", "den"), "only once at a time")
	check(not t.go("hunting_grounds", "from_camp"), "no exit while collapsing")
	check_eq(t.phase, "lie", "Fern sinks down first")
	check_eq(t.black(), 0.0, "not dark yet")
	var ev := _run(t, t.lie_s + t.collapse_fade_s + 0.05)
	check(_types(ev).has("load"), "loads the recovery spot at full black")
	var load: Dictionary = ev.filter(func(e): return e["type"] == "load")[0]
	check(load["collapsed"], "load says she collapsed")
	check_eq(load["area"], "camp", "home to camp")
	check_eq(load["spawn"], "den", "at the den")
	check_eq(t.phase, "message", "message on black")
	check_eq(t.black(), 1.0, "black")
	check(not t.confirm(), "a tap right away doesn't skip the message")
	_run(t, t.min_message_s)
	check(t.confirm(), "a tap continues")
	ev = _run(t, 0.05)
	check(_types(ev).has("wake"), "she wakes")
	ev = _run(t, t.collapse_fade_s + t.wake_s + 0.05)
	check(_types(ev).has("done"), "control comes back after waking")
	check(not t.busy(), "done")


func test_collapse_message_continues_on_its_own() -> void:
	var t = Travel.new(tuning)
	t.collapse("camp", "den")
	var ev := _run(t, t.lie_s + t.collapse_fade_s + t.message_s + 0.1)
	check(_types(ev).has("wake"), "continues after message_s without a tap")
	check(t.message_s >= 1.5 and t.message_s <= 3.0, "about 2 s (%.1f)" % t.message_s)


func test_long_frame_doesnt_skip_load() -> void:
	var t = Travel.new(tuning)
	t.go("camp", "start")
	var ev: Array[Dictionary] = t.step(5.0)
	check_eq(_types(ev), ["load", "done"], "a huge frame still loads before finishing")


# --- player_state.gd


func test_player_state_carries_and_drops() -> void:
	var p = PlayerState.new()
	p.reset("camp", "start")
	check_eq(p.carried_item, "", "carries nothing at first")
	p.carried_item = "mouse"
	p.arrive("hunting_grounds", "from_camp")
	check_eq(p.carried_item, "mouse", "carried item survives changing area")
	check_eq(p.area, "hunting_grounds", "area")
	check_eq(p.drop_carried(), "mouse", "drop returns what was carried")
	check_eq(p.carried_item, "", "dropped")

extends RefCounted
## One area (the camp meadow, the Hunting Grounds...): player movement,
## collision and interaction. Plain data, no
## Nodes, so it runs and tests headless. The view calls step() every frame with
## the input it read and interact() when the player presses interact; both
## return events (Dictionaries with a "type") for the view to show.
## While a conversation runs (begin_talk() .. end_talk()) the player can't
## move and the NPC being talked to stops; the two face each other.
## preload() this script; no class_name.
##
## Positions are "feet" positions in world pixels: the bottom-centre of a
## sprite. Footprints are small rects at the feet used for collision.
##
## Areas: each area is one JSON file like data/world.json (the camp), listed
## in data/areas.json. An area has named `spawns` ({"pos", "facing"}) and
## `exits` ({"id", "rect", "to" (area id), "spawn" (spawn name there)}).
## Walking into an exit gives an "exit" event once; an exit only fires after
## Fern has stood clear of every exit (so arriving next to one, or on one,
## can never bounce her straight back). place_at_spawn() moves her.

const JsonData := preload("res://scripts/core/json_data.gd")
const WORLD_PATH := "res://data/world.json"
const TUNING_PATH := "res://data/tuning.json"
## Longest distance the player moves in one collision sub-step (px).
const MAX_STEP_PX := 2.0
## Longest frame we simulate; slower frames are slowed down, not skipped.
const MAX_DT := 0.1

## Area id and display name (data/areas.json, the area file's "id" / "name").
var id := ""
var display_name := ""
var size := Vector2(480, 270)
## Where the player's footprint may be.
var bounds := Rect2()
var background := Color("#6fb35a")
## How far past the meadow's edge the forest is drawn and the camera may go
## (world px). The camera limits are the world grown by this.
var border := 0.0
## Art keys for the baked meadow floor and the forest tile around it.
var ground_art := ""
var forest_art := ""
## Worn path: polylines (world px) and their width.
var path_lines: Array[PackedVector2Array] = []
var path_width := 10.0
## The pond: {"art", "pos" (centre), "size", "rect" (solid), "lap_radius"}
## or empty.
var pond: Dictionary = {}
## Tall-grass blades Fern walks through. Each: {"art", "pos", "flip"}.
var tall_grass: Array[Dictionary] = []
var tall_grass_patches: Array[Rect2] = []

var player_pos := Vector2.ZERO
var player_vel := Vector2.ZERO
var player_footprint := Vector2(12, 5)
## 1 = facing right, -1 = facing left.
var facing := 1
var running := false
## Distance walked, for the view's walk animation.
var distance := 0.0

## Each: {"id", "art", "frames", "pos", "footprint", "talk_radius",
## "dialogue" (file path), "behavior" (sit / lie / pace / stand), "facing",
## "rect", and for pacers "path", "speed", "pause", "moving", "distance"}
var npcs: Array[Dictionary] = []
## Least gap (world px, x / y) between two NPCs' zones (footprint, or the
## whole pacing loop) and Fern's start: side-view cats are wider than their
## footprints, so closer than this their sprites overlap.
var npc_spacing := Vector2(24, 16)
## Flat decals under everything (Sorrel's sunny spot, the den, the trail
## out of an exit). Each: {"art", "pos" (centre), "flip"}
var ground: Array[Dictionary] = []
## id of the NPC the player is talking to, or "".
var talk_id := ""
## Each: {"art", "pos", "rect", "type", "flip", "shadow", "sway",
## "rustle", and for trees "canopy" + "canopy_offset"}. world.json "props"
## first (in order), then the generated tree line.
var props: Array[Dictionary] = []
## Each: {"art", "pos"}; cosmetic, placed with the seeded RNG.
var decor: Array[Dictionary] = []
## Collision rects (npc and prop footprints). Rebuilt when an NPC moves.
var solids: Array[Rect2] = []
var _prop_solids: Array[Rect2] = []
## What the player can interact with right now: an NPC id, PILE_ID (the
## fresh-catch pile), POND_ID, or "". The nearest one in range wins.
var focus_id := ""
const PILE_ID := "fresh_catch"
const POND_ID := "pond"
## The fresh-catch pile: {"id", "art", "pos", "footprint", "rect",
## "talk_radius", "prey", "max", "refill_s", "refill_t", "shadow"} or empty.
var pile: Dictionary = {}
## How close to the water's edge Fern must be to drink (world px).
var drink_radius := 12.0
## What Fern is busy doing ("eat", "drink" or ""), and seconds left. She
## can't move meanwhile.
var action := ""
var action_t := 0.0
var eat_s := 1.6
var drink_s := 1.6
## Named places Fern can appear: name -> {"pos", "facing"}. "start" is
## world.json's player.start.
var spawns: Dictionary = {}
## Each: {"id", "rect", "to", "spawn"}. Walking into one gives an "exit" event.
var exits: Array[Dictionary] = []
## False until Fern stands clear of every exit (set again on each exit).
var exits_armed := true
## Where prey will appear (next milestone): each {"id", "pos"}.
var prey_spots: Array[Dictionary] = []
## Optional colour grade for this area (palette.json grade keys ->
## colours), over the palette's own: the Hunting Grounds is more golden.
var grade: Dictionary = {}
## Gaps in the generated tree line: each [x, y, radius] (world px).
var tree_gaps: Array[Vector3] = []

var walk_speed := 70.0
var run_speed := 125.0
var accel := 900.0
var decel := 1200.0

## The one RNG for anything world-related. Seeded from data, so a given
## world.json always gives the same world.
var rng := RandomNumberGenerator.new()


func _init(world_data: Dictionary = {}, tuning_data: Dictionary = {}) -> void:
	if world_data.is_empty():
		world_data = JsonData.load_dict(WORLD_PATH)
	if tuning_data.is_empty():
		tuning_data = JsonData.load_dict(TUNING_PATH)
	_load(world_data, tuning_data)


func _load(w: Dictionary, t: Dictionary) -> void:
	var p: Dictionary = t.get("player", {})
	walk_speed = float(p.get("walk_speed", walk_speed))
	run_speed = float(p.get("run_speed", run_speed))
	accel = float(p.get("accel", accel))
	decel = float(p.get("decel", decel))
	var nd: Dictionary = t.get("needs", {})
	eat_s = float(nd.get("eat_s", eat_s))
	drink_s = float(nd.get("drink_s", drink_s))

	id = str(w.get("id", ""))
	display_name = str(w.get("name", id))
	grade = w.get("grade", {})
	size = _vec(w.get("size", [480, 270]))
	var margin := float(w.get("edge_margin", 0))
	bounds = Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	background = Color(str(w.get("background", "#6fb35a")))
	border = float(w.get("border", 0))
	ground_art = str(w.get("ground_art", ""))
	forest_art = str(w.get("forest_art", ""))
	var pth: Dictionary = w.get("path", {})
	path_width = float(pth.get("width", path_width))
	for line in pth.get("lines", []):
		var pts := PackedVector2Array()
		for pt in line:
			pts.append(_vec(pt))
		path_lines.append(pts)

	var pl: Dictionary = w.get("player", {})
	player_pos = _vec(pl.get("start", [size.x / 2, size.y / 2]))
	player_footprint = _vec(pl.get("footprint", [12, 5]))
	spawns["start"] = {"pos": player_pos, "facing": int(pl.get("facing", 1))}
	var sp: Dictionary = w.get("spawns", {})
	for n: String in sp:
		spawns[n] = {"pos": _vec(sp[n].get("pos", [0, 0])), "facing": int(sp[n].get("facing", 1))}
	for e: Dictionary in w.get("exits", []):
		var r: Array = e.get("rect", [0, 0, 0, 0])
		exits.append({"id": str(e.get("id", "")), "rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
			"to": str(e.get("to", "")), "spawn": str(e.get("spawn", ""))})
	for ps: Dictionary in w.get("prey_spots", []):
		prey_spots.append({"id": str(ps.get("id", "")), "pos": _vec(ps.get("pos", [0, 0]))})
	for g in w.get("tree_line", {}).get("gaps", []):
		tree_gaps.append(Vector3(float(g[0]), float(g[1]), float(g[2])))

	for n: Dictionary in w.get("npcs", []):
		var npc := {
			"id": str(n.get("id", "")),
			"art": str(n.get("art", "")),
			"frames": int(n.get("frames", 1)),
			"pos": _vec(n.get("pos", [0, 0])),
			"footprint": _vec(n.get("footprint", [16, 6])),
			"talk_radius": float(n.get("talk_radius", 22)),
			"dialogue": str(n.get("dialogue", "")),
			"behavior": str(n.get("behavior", "stand")),
			"facing": int(n.get("facing", 1)),
			"moving": false,
			"distance": 0.0,
		}
		var path: Array[Vector2] = []
		for pt in n.get("path", []):
			path.append(_vec(pt))
		if not path.is_empty():
			npc["path"] = path
			npc["pos"] = path[0]
			npc["leg"] = 1 % path.size()
			npc["speed"] = float(n.get("speed", 16))
			npc["pause"] = float(n.get("pause", 0.8))
			npc["wait"] = npc["pause"]
		npc["rect"] = footprint_rect(npc["pos"], npc["footprint"])
		npcs.append(npc)
	npc_spacing = _vec(w.get("npc_spacing", [24, 16]))
	_space_npcs()

	var types: Dictionary = w.get("prop_types", {})
	for pr: Dictionary in w.get("props", []):
		_add_prop(pr, types)
	_add_tree_line(w.get("tree_line", {}), types)
	var pd: Dictionary = w.get("pond", {})
	if not pd.is_empty():
		var c := _vec(pd.get("pos", [0, 0]))
		var sz := _vec(pd.get("size", [32, 16]))
		var inset := _vec(pd.get("footprint_inset", [4, 4]))
		pond = {"art": str(pd.get("art", "")), "pos": c, "size": sz,
			"rect": Rect2(c - sz / 2.0 + inset, sz - inset * 2.0),
			"lap_radius": float(pd.get("lap_radius", 40))}
		drink_radius = float(pd.get("drink_radius", drink_radius))
		_prop_solids.append(pond["rect"])
	var fc: Dictionary = w.get("fresh_catch", {})
	if not fc.is_empty():
		var fpos := _vec(fc.get("pos", [0, 0]))
		var ffp := _vec(fc.get("footprint", [18, 5]))
		var most := int(fc.get("max", 5))
		pile = {"id": PILE_ID, "art": str(fc.get("art", "")), "pos": fpos, "footprint": ffp,
			"rect": footprint_rect(fpos, ffp), "talk_radius": float(fc.get("talk_radius", 22)),
			"max": most, "prey": clampi(int(fc.get("prey", most)), 0, most),
			"refill_s": float(fc.get("refill_s", 60)), "refill_t": 0.0,
			"shadow": str(fc.get("shadow", ""))}
		_prop_solids.append(pile["rect"])
	_rebuild_solids()

	for g: Dictionary in w.get("ground", []):
		ground.append({"art": str(g.get("art", "")), "pos": _vec(g.get("pos", [0, 0])), "flip": bool(g.get("flip", false))})

	var tg: Dictionary = w.get("tall_grass", {})
	rng.seed = int(tg.get("seed", 0))
	for patch: Dictionary in tg.get("patches", []):
		var r: Array = patch.get("rect", [0, 0, 0, 0])
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		tall_grass_patches.append(rect)
		for i in int(patch.get("count", 0)):
			# Denser in the middle: average two samples.
			var pos := Vector2(
				(rng.randf_range(rect.position.x, rect.end.x) + rng.randf_range(rect.position.x, rect.end.x)) / 2.0,
				rng.randf_range(rect.position.y, rect.end.y)).round()
			tall_grass.append({"art": str(tg.get("art", "")), "pos": pos, "flip": rng.randf() < 0.5})

	# Flowers grow in clusters (denser near the centre), never on the path.
	var fl: Dictionary = w.get("flowers", {})
	rng.seed = int(fl.get("seed", 0))
	for cl: Dictionary in fl.get("clusters", []):
		var centre := _vec(cl.get("pos", [0, 0]))
		var radius := float(cl.get("radius", 10))
		var colors: Array = cl.get("colors", ["yellow"])
		for i in int(cl.get("count", 0)):
			var pos := (centre + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf()) * rng.randf_range(0.5, 1.0)).round()
			var col: String = colors[rng.randi_range(0, colors.size() - 1)]
			if _decor_spot_ok(pos):
				decor.append({"art": "decor.flower_" + col, "pos": pos})

	var d: Dictionary = w.get("decor", {})
	rng.seed = int(d.get("seed", 0))
	var items: Dictionary = d.get("items", {})
	for art: String in items:
		for i in int(items[art]):
			var pos := Vector2(rng.randi_range(4, int(size.x) - 4), rng.randi_range(8, int(size.y) - 2))
			if _decor_spot_ok(pos):
				decor.append({"art": art, "pos": pos})
	_scatter(w.get("scatter", {}), types)
	exits_armed = not _on_exit()
	_update_focus()


## Random fill for an area: decor (tufts, flowers) and small props (rocks)
## inside rects, never on the path, a collider, an exit or a spawn point.
## world.json "scatter": {"seed", "areas": [{"rect": [x, y, w, h],
## "decor": {art key: count}, "props": {prop type: count}}]}. Important
## things are placed by hand in "props"; this only fills in.
func _scatter(sc: Dictionary, types: Dictionary) -> void:
	if sc.is_empty():
		return
	rng.seed = int(sc.get("seed", 0))
	for a: Dictionary in sc.get("areas", []):
		var r: Array = a.get("rect", [0, 0, size.x, size.y])
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var items: Dictionary = a.get("decor", {})
		for art: String in items:
			for i in int(items[art]):
				var pos := _random_in(rect)
				if _decor_spot_ok(pos) and not _near_solid(Rect2(pos - Vector2(2, 2), Vector2(4, 3))):
					decor.append({"art": art, "pos": pos})
		var props_in: Dictionary = a.get("props", {})
		for kind: String in props_in:
			var fp := _vec(types.get(kind, {}).get("footprint", [8, 4]))
			for i in int(props_in[kind]):
				# A few tries per prop; a crowded rect just gets fewer.
				for attempt in 8:
					var pos := _random_in(rect)
					var fr := footprint_rect(pos, fp)
					if _decor_spot_ok(pos) and not on_path(pos, fp.x / 2.0 + 2.0) and not _near_solid(fr.grow(10.0)) and _clear_of_paths_in(fr.grow(12.0)):
						_add_prop({"type": kind, "pos": [pos.x, pos.y], "flip": rng.randf() < 0.5}, types)
						break
	_rebuild_solids()


func _random_in(rect: Rect2) -> Vector2:
	return Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y)).round()


func _near_solid(r: Rect2) -> bool:
	for s in _prop_solids:
		if s.intersects(r):
			return true
	for npc in npcs:
		if npc_zone(npc).intersects(r):
			return true
	return false


## Clear of exits and spawn points (so nothing ever blocks the way in or out).
func _clear_of_paths_in(r: Rect2) -> bool:
	for e in exits:
		if (e["rect"] as Rect2).grow(16.0).intersects(r):
			return false
	for n: String in spawns:
		if footprint_rect(spawns[n]["pos"], player_footprint).grow(16.0).intersects(r):
			return false
	return true


## Puts Fern at spawn `name`, standing still and facing its way. Exits stay
## quiet until she has stepped clear of them. False (and nothing moves) if
## there is no such spawn.
func place_at_spawn(name: String) -> bool:
	if not spawns.has(name):
		return false
	player_pos = spawns[name]["pos"]
	player_vel = Vector2.ZERO
	running = false
	facing = 1 if int(spawns[name]["facing"]) >= 0 else -1
	talk_id = ""
	action = ""
	action_t = 0.0
	exits_armed = not _on_exit()
	_update_focus()
	return true


## The exit Fern's footprint touches, or {}.
func exit_at_player() -> Dictionary:
	var pr := player_rect()
	for e in exits:
		if (e["rect"] as Rect2).intersects(pr):
			return e
	return {}


func _on_exit() -> bool:
	return not exit_at_player().is_empty()


func _check_exits(events: Array[Dictionary]) -> void:
	var e := exit_at_player()
	if e.is_empty():
		exits_armed = true
		return
	if exits_armed and not is_talking() and not is_busy():
		exits_armed = false
		events.append({"type": "exit", "id": e["id"], "to": e["to"], "spawn": e["spawn"]})


func _add_prop(pr: Dictionary, types: Dictionary) -> void:
	var spec: Dictionary = types.get(str(pr.get("type", "")), {}).duplicate()
	spec.merge(pr, true)
	var prop := {
		"type": str(spec.get("type", "")),
		"art": str(spec.get("art", "")),
		"pos": _vec(spec.get("pos", [0, 0])),
		"flip": bool(spec.get("flip", false)),
		"shadow": str(spec.get("shadow", "")),
		"sway": str(spec.get("sway", "")),
		"rustle": bool(spec.get("rustle", false)),
		"trunk": bool(spec.get("trunk", true)),
	}
	if spec.has("canopy"):
		prop["canopy"] = str(spec["canopy"])
		prop["canopy_offset"] = _vec(spec.get("canopy_offset", [0, 0]))
	prop["rect"] = footprint_rect(prop["pos"], _vec(spec.get("footprint", [16, 6])))
	props.append(prop)
	_prop_solids.append(prop["rect"])


## Trees all round the meadow, so the edge is a wood, not a cliff: a row
## along the top (Fern walks in front of the trunks), and rows just past the
## bottom, left and right edges whose canopies hang over the meadow.
func _add_tree_line(tl: Dictionary, types: Dictionary) -> void:
	if tl.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = int(tl.get("seed", 0))
	var spacing := float(tl.get("spacing", 30))
	var jitter := float(tl.get("jitter", 6))
	var kinds: Array = tl.get("types", [])
	if kinds.is_empty():
		return
	var spots: Array[Vector2] = []
	var x := -spacing
	while x <= size.x + spacing:
		spots.append(Vector2(x, float(tl.get("top_y", 8))))
		spots.append(Vector2(x + spacing / 2.0, float(tl.get("bottom_y", size.y + 30))))
		x += spacing
	var y := spacing / 2.0
	while y <= size.y + spacing:
		spots.append(Vector2(float(tl.get("left_x", -16)), y))
		spots.append(Vector2(float(tl.get("right_x", size.x + 16)), y + spacing / 3.0))
		y += spacing
	for p in spots:
		var j := Vector2(r.randf_range(-jitter, jitter), r.randf_range(-jitter, jitter) * 0.5)
		# Only the top row stands in the meadow; the others are canopies
		# over the forest floor (no trunk, no shadow).
		var inside := p.y >= 0.0 and p.y < size.y and p.x >= 0.0 and p.x <= size.x
		if _in_tree_gap(p):
			continue
		_add_prop({"type": kinds[r.randi_range(0, kinds.size() - 1)], "pos": [roundf(p.x + j.x), roundf(p.y + j.y)], "flip": r.randf() < 0.5, "trunk": inside}, types)


## Inside one of tree_line "gaps" (where a path leaves the area).
func _in_tree_gap(p: Vector2) -> bool:
	for g in tree_gaps:
		if p.distance_to(Vector2(g.x, g.y)) <= g.z:
			return true
	return false


func _decor_spot_ok(p: Vector2) -> bool:
	if on_path(p, 2.0):
		return false
	if not pond.is_empty() and Rect2(pond["pos"] - pond["size"] / 2.0, pond["size"]).grow(3).has_point(p):
		return false
	if not pile.is_empty() and Rect2(pile["pos"] - Vector2(16, 16), Vector2(32, 18)).has_point(p):
		return false
	return true


## Whether `p` is on the worn path (`grow` px of slack).
func on_path(p: Vector2, grow: float = 0.0) -> bool:
	var half := path_width / 2.0 + grow
	for line in path_lines:
		for i in range(line.size() - 1):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])) <= half:
				return true
	return false


## What Fern is standing on: "path" or "grass" (footstep sounds).
func surface() -> String:
	return "path" if on_path(player_pos) else "grass"


## Whether Fern's feet are in a tall-grass patch.
func in_tall_grass() -> bool:
	for r in tall_grass_patches:
		if r.has_point(player_pos):
			return true
	return false


## Index into props of a rustly prop (bush) Fern is brushing against, or -1.
func brushing_prop() -> int:
	var pr := player_rect().grow(2.0)
	for i in props.size():
		if props[i]["rustle"] and pr.intersects(props[i]["rect"]):
			return i
	return -1


## Distance from Fern to the pond's water edge (INF without a pond).
func pond_distance() -> float:
	if pond.is_empty():
		return INF
	return distance_to_rect(pond["rect"])


## The area the camera may show: the meadow plus the forest border.
## The ground an NPC can stand on: its footprint, or its whole pacing loop.
func npc_zone(npc: Dictionary) -> Rect2:
	var r: Rect2 = footprint_rect(npc["pos"], npc["footprint"])
	for pt: Vector2 in npc.get("path", []):
		r = r.merge(footprint_rect(pt, npc["footprint"]))
	return r


## True when zones `a` and `b` are at least npc_spacing apart on x or on y.
func zones_apart(a: Rect2, b: Rect2) -> bool:
	var dx := maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var dy := maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	return dx >= npc_spacing.x or dy >= npc_spacing.y


## Keeps NPCs from spawning on top of each other (or of Fern): an NPC too
## close to one placed before it moves sideways, a little further each try,
## and a warning names it so world.json can be fixed.
func _space_npcs() -> void:
	var taken: Array[Rect2] = [footprint_rect(player_pos, player_footprint)]
	for npc in npcs:
		var shift := Vector2.ZERO
		var tries := 0
		while tries < 40 and not taken.all(func(r: Rect2) -> bool: return zones_apart(_shifted_zone(npc, shift), r)):
			tries += 1
			shift = Vector2(8.0 * ceili(tries / 2.0) * (1 if tries % 2 == 1 else -1), 0)
		if shift != Vector2.ZERO and tries < 40:
			push_warning("world.json: NPC '%s' too close to another; moved %s" % [npc["id"], shift])
			npc["pos"] += shift
			if npc.has("path"):
				var moved: Array[Vector2] = []
				for pt: Vector2 in npc["path"]:
					moved.append(pt + shift)
				npc["path"] = moved
			npc["rect"] = footprint_rect(npc["pos"], npc["footprint"])
		taken.append(npc_zone(npc))


func _shifted_zone(npc: Dictionary, shift: Vector2) -> Rect2:
	var r := npc_zone(npc)
	r.position += shift
	return r


func camera_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(border)


static func footprint_rect(feet: Vector2, fp: Vector2) -> Rect2:
	return Rect2(feet.x - fp.x / 2.0, feet.y - fp.y, fp.x, fp.y)


## The part of the world a camera of `view_size` shows: centred on the
## player, clamped to camera_bounds() (the meadow plus the forest border:
## the camera limits). If the view is bigger than that on an axis, it is
## centred (the forest is drawn further out, so it still fills the view).
## Whole pixels, so pixel art stays crisp.
## `center` (world px) overrides the point to centre on (the view frames a
## conversation above the dialogue box with it).
## `whole` = false leaves the position unrounded (game.gd rounds it itself).
func camera_rect(view_size: Vector2, center: Vector2 = Vector2.INF, whole: bool = true) -> Rect2:
	if center == Vector2.INF:
		center = player_pos - Vector2(0, player_footprint.y * 2.0)
	var top_left := center - view_size / 2.0
	var lim := camera_bounds()
	for axis in 2:
		if view_size[axis] >= lim.size[axis]:
			top_left[axis] = lim.position[axis] + (lim.size[axis] - view_size[axis]) / 2.0
		else:
			top_left[axis] = clampf(top_left[axis], lim.position[axis], lim.end[axis] - view_size[axis])
	return Rect2(top_left.floor() if whole else top_left, view_size)


func player_rect() -> Rect2:
	return footprint_rect(player_pos, player_footprint)


func speed() -> float:
	return player_vel.length()


## Advances the world by dt seconds. `move` is the wanted direction; its
## length (0..1) scales speed, so a half-pushed stick walks slowly.
func step(dt: float, move: Vector2, run: bool) -> Array[Dictionary]:
	dt = clampf(dt, 0.0, MAX_DT)
	var events: Array[Dictionary] = []
	if is_talking() or is_busy():
		move = Vector2.ZERO
		run = false
	if is_busy():
		action_t = maxf(0.0, action_t - dt)
		if action_t <= 0.0:
			events.append({"type": "action_done", "action": action})
			action = ""
	_step_pile(dt, events)
	_step_npcs(dt)
	if move.length() > 1.0:
		move = move.normalized()
	running = run and move.length() > 0.0
	var top := run_speed if running else walk_speed
	var target := move * top
	var rate := accel if target.length() > 0.0 else decel
	player_vel = player_vel.move_toward(target, rate * dt)
	if absf(move.x) > 0.01:
		facing = 1 if move.x > 0.0 else -1

	var travel := player_vel * dt
	var steps := maxi(1, ceili(travel.length() / MAX_STEP_PX))
	var before := player_pos
	for i in steps:
		_move_axis(Vector2(travel.x / steps, 0.0))
		_move_axis(Vector2(0.0, travel.y / steps))
	distance += before.distance_to(player_pos)

	var old_focus := focus_id
	_update_focus()
	if focus_id != old_focus:
		events.append({"type": "focus", "id": focus_id})
	_check_exits(events)
	return events


## The player pressed interact, on whatever has focus:
## - an NPC: starts talking; a "talk" event with its dialogue file.
## - the fresh-catch pile: eats one prey ("eat", needs.eat()), or a
##   "message" (strings.json key) when the pile is empty or Fern is full.
## - the pond: drinks ("drink", needs.drink()); it never runs out.
## Eating and drinking face the thing and lock movement for eat_s / drink_s.
## `needs` is a scripts/core/needs.gd (null: eat / drink change nothing).
func interact(needs = null) -> Array[Dictionary]:
	if is_talking() or is_busy():
		return []
	if focus_id == PILE_ID:
		if needs != null and needs.is_full():
			return [{"type": "message", "key": "needs.not_hungry"}]
		if pile["prey"] <= 0:
			return [{"type": "message", "key": "needs.pile_empty"}]
		pile["prey"] -= 1
		if needs != null:
			needs.eat()
		_begin_action("eat", eat_s, pile["pos"])
		return [{"type": "eat", "prey": pile["prey"]}, {"type": "pile", "prey": pile["prey"]}]
	if focus_id == POND_ID:
		if needs != null:
			needs.drink()
		_begin_action("drink", drink_s, pond_point())
		return [{"type": "drink", "pos": pond_point()}]
	var npc := npc_by_id(focus_id)
	if npc.is_empty() or npc["dialogue"] == "":
		return []
	begin_talk(npc["id"])
	return [{"type": "talk", "id": npc["id"], "dialogue": npc["dialogue"]}]


func is_talking() -> bool:
	return talk_id != ""


## Eating or drinking (movement locked).
func is_busy() -> bool:
	return action != ""


## "npc", "pile", "pond" or "" for what has focus.
func focus_kind() -> String:
	if focus_id == "":
		return ""
	if focus_id == PILE_ID:
		return "pile"
	if focus_id == POND_ID:
		return "pond"
	return "npc"


## The point on the pond's water edge nearest Fern (world px).
func pond_point() -> Vector2:
	if pond.is_empty():
		return Vector2.ZERO
	var r: Rect2 = pond["rect"]
	return Vector2(clampf(player_pos.x, r.position.x, r.end.x), clampf(player_pos.y, r.position.y, r.end.y))


func _begin_action(kind: String, seconds: float, toward: Vector2) -> void:
	action = kind
	action_t = maxf(0.01, seconds)
	player_vel = Vector2.ZERO
	running = false
	if absf(toward.x - player_pos.x) >= 2.0:
		facing = 1 if toward.x > player_pos.x else -1


## Temporary refill: one prey every refill_s while the pile isn't full
## (hunting and patrols replace this later). Emits "pile" when it grows.
func _step_pile(dt: float, events: Array[Dictionary]) -> void:
	if pile.is_empty():
		return
	if pile["prey"] >= pile["max"] or pile["refill_s"] <= 0.0:
		pile["refill_t"] = 0.0
		return
	pile["refill_t"] += dt
	if pile["refill_t"] >= pile["refill_s"]:
		pile["refill_t"] -= pile["refill_s"]
		pile["prey"] += 1
		events.append({"type": "pile", "prey": pile["prey"]})


## Locks movement, stops the cat and the NPC, and turns them to face each other.
func begin_talk(id: String) -> void:
	var npc := npc_by_id(id)
	if npc.is_empty():
		return
	talk_id = id
	player_vel = Vector2.ZERO
	running = false
	npc["moving"] = false
	facing = 1 if npc["pos"].x >= player_pos.x else -1
	npc["facing"] = -facing


func end_talk() -> void:
	talk_id = ""


## Wick-style pacing: walk the path's points in a loop, pausing at each.
## A pacer waits instead of walking into the player, and stands still while
## being talked to.
func _step_npcs(dt: float) -> void:
	var moved := false
	for npc in npcs:
		if not npc.has("path"):
			continue
		npc["moving"] = false
		if npc["id"] == talk_id:
			continue
		if npc["wait"] > 0.0:
			npc["wait"] = maxf(0.0, npc["wait"] - dt)
			continue
		var path: Array[Vector2] = npc["path"]
		var target: Vector2 = path[npc["leg"]]
		var pos: Vector2 = npc["pos"]
		var next := pos.move_toward(target, npc["speed"] * dt)
		var r := footprint_rect(next, npc["footprint"])
		if r.intersects(player_rect().grow(1.0)):
			continue
		if absf(next.x - pos.x) > 0.001:
			npc["facing"] = 1 if next.x > pos.x else -1
		npc["distance"] += pos.distance_to(next)
		npc["pos"] = next
		npc["rect"] = r
		npc["moving"] = true
		moved = true
		if next.is_equal_approx(target):
			npc["pos"] = target
			npc["leg"] = (npc["leg"] + 1) % path.size()
			npc["wait"] = npc["pause"]
	if moved:
		_rebuild_solids()


func _rebuild_solids() -> void:
	solids = []
	for npc in npcs:
		solids.append(npc["rect"])
	solids.append_array(_prop_solids)


func npc_by_id(id: String) -> Dictionary:
	for npc in npcs:
		if npc["id"] == id and id != "":
			return npc
	return {}


## Distance from the player's footprint to a rect (0 when touching).
func distance_to_rect(r: Rect2) -> float:
	var pr := player_rect()
	var dx := maxf(0.0, maxf(r.position.x - pr.end.x, pr.position.x - r.end.x))
	var dy := maxf(0.0, maxf(r.position.y - pr.end.y, pr.position.y - r.end.y))
	return Vector2(dx, dy).length()


func _move_axis(delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	var next := player_pos + delta
	var r := footprint_rect(next, player_footprint)
	if not bounds.encloses(r):
		# Slide along the edge instead of stopping short of it.
		next.x = clampf(next.x, bounds.position.x + player_footprint.x / 2.0, bounds.end.x - player_footprint.x / 2.0)
		next.y = clampf(next.y, bounds.position.y + player_footprint.y, bounds.end.y)
		r = footprint_rect(next, player_footprint)
		if delta.x != 0.0:
			player_vel.x = 0.0
		else:
			player_vel.y = 0.0
	for s in solids:
		if s.intersects(r):
			if delta.x != 0.0:
				player_vel.x = 0.0
			else:
				player_vel.y = 0.0
			return
	player_pos = next


func _update_focus() -> void:
	var best := ""
	var best_d := INF
	for npc in npcs:
		var d := distance_to_rect(npc["rect"])
		if d <= npc["talk_radius"] and d < best_d:
			best = npc["id"]
			best_d = d
	if not pile.is_empty():
		var d := distance_to_rect(pile["rect"])
		if d <= pile["talk_radius"] and d < best_d:
			best = PILE_ID
			best_d = d
	if not pond.is_empty():
		var d := distance_to_rect(pond["rect"])
		if d <= drink_radius and d < best_d:
			best = POND_ID
			best_d = d
	focus_id = best


static func _vec(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO

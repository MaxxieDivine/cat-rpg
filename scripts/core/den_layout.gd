extends RefCounted
## Turns a den's settings into its room: the den template (C.2). A den area
## file has "interior" (the settings) and "door" (where the way out leads);
## build() returns everything World needs in world px: the room size, the
## walls (solids), the doorway exit, spawns, nests, the "Your nest." spot,
## decor slots and a worn trail from the door. Plain data, no Nodes; the
## same settings always give the same room. scripts/view/den_interior.gd
## draws it. preload() this script; no class_name.
##
## Settings ("interior"):
##   size        "small" / "medium" / "large" (floor sizes in tuning.json den.sizes)
##   floor_color tint over the floor tile (view only)
##   walls       wall material: art keys den.wall_<walls>_top / _side / _bottom
##   nests       how many nests
##   player_nest which nest is Fern's (0-based), or -1 for none
##   nest_message (optional) her nest's line (strings.json key; default
##               "den.your_nest"); feather (optional, default true): her nest
##               shows the feather (the prisoner den's bedding doesn't)
## Layout (tuning.json "den"): walls `wall` {top, side, bottom} px thick
## round the floor; the doorway (`door_w` wide) in the middle of the bottom
## wall; nests along the back wall, then down the sides; corners rounded by
## `corner` px of extra wall.

const SIZES := ["small", "medium", "large"]
const PLAYER_NEST_SPOT := "my_nest"

static func defaults() -> Dictionary:
	return {"size": "medium", "floor_color": "#ffffff", "walls": "fern_moss", "nests": 3, "player_nest": 0}


## The room for `interior` (settings), with tuning.json "den" numbers in
## `t` and the way out in `door` ({"to": area id, "spawn": spawn there}).
static func build(interior: Dictionary, t: Dictionary, door: Dictionary = {}) -> Dictionary:
	var s := defaults()
	s.merge(interior, true)
	var sizes: Dictionary = t.get("sizes", {"small": [224, 128], "medium": [288, 152], "large": [368, 184]})
	var size_name: String = str(s["size"]) if sizes.has(str(s["size"])) else "medium"
	var fl: Array = sizes[size_name]
	var floor_size := Vector2(float(fl[0]), float(fl[1]))
	var wall: Dictionary = t.get("wall", {"top": 26, "side": 14, "bottom": 12})
	var top := float(wall.get("top", 26))
	var side := float(wall.get("side", 14))
	var bottom := float(wall.get("bottom", 12))
	var corner := float(t.get("corner", 6))
	var size := floor_size + Vector2(side * 2.0, top + bottom)
	var floor_rect := Rect2(Vector2(side, top), floor_size)
	var door_w := float(t.get("door_w", 36))
	var door_x := roundf(size.x / 2.0 - door_w / 2.0)

	var walls: Array[Rect2] = [
		Rect2(0, 0, size.x, top),
		Rect2(0, 0, side, size.y),
		Rect2(size.x - side, 0, side, size.y),
		Rect2(0, size.y - bottom, door_x, bottom),
		Rect2(door_x + door_w, size.y - bottom, size.x - door_x - door_w, bottom),
		# Rounded corners.
		Rect2(side, top, corner, corner),
		Rect2(size.x - side - corner, top, corner, corner),
		Rect2(side, size.y - bottom - corner, corner, corner),
		Rect2(size.x - side - corner, size.y - bottom - corner, corner, corner),
	]
	var door_rect := Rect2(door_x + 3.0, size.y - bottom + 4.0, door_w - 6.0, bottom - 4.0)

	# Nests: along the back wall, then down the sides (left, right, ...),
	# then in rows across the middle (nests aren't solid: the way stays open).
	var count := maxi(0, int(s["nests"]))
	var nest_size := _vec(t.get("nest_size", [24, 10]))
	var gap := float(t.get("nest_gap", 12))
	var step_y := nest_size.y + gap * 1.5
	var row_y := floor_rect.position.y + nest_size.y + float(t.get("nest_from_wall", 8))
	var lowest := floor_rect.end.y - nest_size.y - 24.0
	var spots_free: Array[Vector2] = []
	var per_row := maxi(1, int((floor_size.x - 2.0 * corner) / (nest_size.x + gap)))
	var back := mini(count, per_row)
	for i in back:
		spots_free.append(Vector2(floor_rect.position.x + floor_size.x * (float(i) + 0.5) / float(back), row_y))
	var y := row_y + step_y
	while y <= lowest:
		spots_free.append(Vector2(floor_rect.position.x + nest_size.x / 2.0 + 6.0, y))
		spots_free.append(Vector2(floor_rect.end.x - nest_size.x / 2.0 - 6.0, y))
		y += step_y
	var inner_l := floor_rect.position.x + nest_size.x + 6.0 + gap
	var inner_w := floor_rect.end.x - nest_size.x - 6.0 - gap - inner_l
	var per_inner := maxi(1, int(inner_w / (nest_size.x + gap)))
	y = row_y + step_y
	while y <= lowest - step_y:
		for i in per_inner:
			var x := inner_l + inner_w * (float(i) + 0.5) / float(per_inner)
			spots_free.append(Vector2(x, y))
		y += step_y
	if count > spots_free.size():
		push_warning("den_layout: only %d nests fit a %s den (asked for %d)" % [spots_free.size(), size_name, count])
	var nests: Array[Dictionary] = []
	for i in mini(count, spots_free.size()):
		nests.append({"pos": spots_free[i].round()})
	var mine := int(s["player_nest"])
	for i in nests.size():
		nests[i]["mine"] = i == mine
		nests[i]["feather"] = i == mine and bool(s.get("feather", true))
		nests[i]["rect"] = Rect2(nests[i]["pos"] - Vector2(nest_size.x / 2.0, nest_size.y - 2.0), nest_size)

	var inside := Vector2(size.x / 2.0 + float(t.get("spawn_offset_x", 14)), size.y - bottom - 10.0)
	var spawns := {"start": {"pos": inside, "facing": 1}, "inside": {"pos": inside, "facing": 1}}
	var spots: Array[Dictionary] = []
	var markers := {}
	if mine >= 0 and mine < nests.size():
		var n: Dictionary = nests[mine]
		spawns["nest"] = {"pos": n["pos"], "facing": 1}
		spots.append({"id": PLAYER_NEST_SPOT, "rect": n["rect"], "talk_radius": float(t.get("nest_radius", 4)),
			"prompt": n["pos"] - Vector2(0, nest_size.y + 2.0), "message": str(s.get("nest_message", "den.your_nest"))})
		markers["PlayerNest"] = n["pos"]

	# Decor slots: along the back wall and the side walls, and beside each
	# nest; never on a nest or near the doorway.
	var slots: Array[Vector2] = []
	var every := float(t.get("decor_every", 40))
	var keep := float(t.get("decor_clear", 16))
	var x0 := floor_rect.position.x + corner + 6.0
	while x0 <= floor_rect.end.x - corner - 6.0:
		_add_slot(slots, Vector2(x0, floor_rect.position.y + 3.0).round(), nests, keep)
		x0 += every
	var y0 := floor_rect.position.y + corner + every / 2.0
	while y0 <= floor_rect.end.y - corner - 6.0:
		_add_slot(slots, Vector2(floor_rect.position.x + 4.0, y0).round(), nests, keep)
		_add_slot(slots, Vector2(floor_rect.end.x - 4.0, y0).round(), nests, keep)
		y0 += every
	for n: Dictionary in nests:
		for dx in [-1.0, 1.0]:
			var p: Vector2 = n["pos"] + Vector2(dx * (nest_size.x / 2.0 + 8.0), -2.0)
			if floor_rect.grow(-4.0).has_point(p):
				_add_slot(slots, p.round(), nests, keep * 0.75)
	var door_c := Vector2(size.x / 2.0, size.y - bottom)
	slots = slots.filter(func(p: Vector2) -> bool: return p.distance_to(door_c) > door_w)

	# A worn trail from the doorway into the room.
	var trail := [[size.x / 2.0, size.y], [size.x / 2.0, size.y - bottom - 6.0], [size.x / 2.0 - 4.0, floor_rect.get_center().y]]
	return {
		"settings": s,
		"size_name": size_name,
		"size": size,
		"floor_rect": floor_rect,
		"wall": {"top": top, "side": side, "bottom": bottom, "corner": corner},
		"walls": walls,
		"door_rect": door_rect,
		"exit": {"id": "out", "rect": door_rect, "to": str(door.get("to", "")), "spawn": str(door.get("spawn", ""))},
		"spawns": spawns,
		"nests": nests,
		"nest_size": nest_size,
		"spots": spots,
		"markers": markers,
		"decor_slots": slots,
		"trail": trail,
		"trail_width": float(t.get("trail_w", 10)),
	}


static func _add_slot(slots: Array[Vector2], p: Vector2, nests: Array[Dictionary], keep: float) -> void:
	for n: Dictionary in nests:
		if (n["pos"] as Vector2).distance_to(p) < keep:
			return
	for q in slots:
		if q.distance_to(p) < 8.0:
			return
	slots.append(p)


static func _vec(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO

extends RefCounted
## The meadow: player movement, collision and interaction. Plain data, no
## Nodes, so it runs and tests headless. The view calls step() every frame with
## the input it read and interact() when the player presses interact; both
## return events (Dictionaries with a "type") for the view to show.
## While a conversation runs (begin_talk() .. end_talk()) the player can't
## move and the NPC being talked to stops; the two face each other.
## preload() this script; no class_name.
##
## Positions are "feet" positions in world pixels: the bottom-centre of a
## sprite. Footprints are small rects at the feet used for collision.

const JsonData := preload("res://scripts/core/json_data.gd")
const WORLD_PATH := "res://data/world.json"
const TUNING_PATH := "res://data/tuning.json"
## Longest distance the player moves in one collision sub-step (px).
const MAX_STEP_PX := 2.0
## Longest frame we simulate; slower frames are slowed down, not skipped.
const MAX_DT := 0.1

var size := Vector2(480, 270)
## Where the player's footprint may be.
var bounds := Rect2()
var background := Color("#6fb35a")

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
## Flat decals under everything (Sorrel's sunny spot). Each: {"art", "pos"}
var ground: Array[Dictionary] = []
## id of the NPC the player is talking to, or "".
var talk_id := ""
## Each: {"art", "pos", "rect"}
var props: Array[Dictionary] = []
## Each: {"art", "pos"}; cosmetic, placed with the seeded RNG.
var decor: Array[Dictionary] = []
## Collision rects (npc and prop footprints). Rebuilt when an NPC moves.
var solids: Array[Rect2] = []
var _prop_solids: Array[Rect2] = []
## id of the NPC the player can interact with right now, or "".
var focus_id := ""

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

	size = _vec(w.get("size", [480, 270]))
	var margin := float(w.get("edge_margin", 0))
	bounds = Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	background = Color(str(w.get("background", "#6fb35a")))

	var pl: Dictionary = w.get("player", {})
	player_pos = _vec(pl.get("start", [size.x / 2, size.y / 2]))
	player_footprint = _vec(pl.get("footprint", [12, 5]))

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

	for pr: Dictionary in w.get("props", []):
		var prop := {"art": str(pr.get("art", "")), "pos": _vec(pr.get("pos", [0, 0]))}
		prop["rect"] = footprint_rect(prop["pos"], _vec(pr.get("footprint", [16, 6])))
		props.append(prop)
		_prop_solids.append(prop["rect"])
	_rebuild_solids()

	for g: Dictionary in w.get("ground", []):
		ground.append({"art": str(g.get("art", "")), "pos": _vec(g.get("pos", [0, 0]))})

	var d: Dictionary = w.get("decor", {})
	rng.seed = int(d.get("seed", 0))
	var items: Dictionary = d.get("items", {})
	for art: String in items:
		for i in int(items[art]):
			var pos := Vector2(rng.randi_range(4, int(size.x) - 4), rng.randi_range(8, int(size.y) - 2))
			decor.append({"art": art, "pos": pos})
	_update_focus()


static func footprint_rect(feet: Vector2, fp: Vector2) -> Rect2:
	return Rect2(feet.x - fp.x / 2.0, feet.y - fp.y, fp.x, fp.y)


## The part of the world a camera of `view_size` shows: centred on the
## player, clamped so it never shows past the world's edges (the camera
## limits). If the view is bigger than the world on an axis, it is centred.
## Whole pixels, so pixel art stays crisp.
## `center` (world px) overrides the point to centre on (the view frames a
## conversation above the dialogue box with it).
func camera_rect(view_size: Vector2, center: Vector2 = Vector2.INF) -> Rect2:
	if center == Vector2.INF:
		center = player_pos - Vector2(0, player_footprint.y * 2.0)
	var top_left := center - view_size / 2.0
	for axis in 2:
		if view_size[axis] >= size[axis]:
			top_left[axis] = (size[axis] - view_size[axis]) / 2.0
		else:
			top_left[axis] = clampf(top_left[axis], 0.0, size[axis] - view_size[axis])
	return Rect2(top_left.floor(), view_size)


func player_rect() -> Rect2:
	return footprint_rect(player_pos, player_footprint)


func speed() -> float:
	return player_vel.length()


## Advances the world by dt seconds. `move` is the wanted direction; its
## length (0..1) scales speed, so a half-pushed stick walks slowly.
func step(dt: float, move: Vector2, run: bool) -> Array[Dictionary]:
	dt = clampf(dt, 0.0, MAX_DT)
	if is_talking():
		move = Vector2.ZERO
		run = false
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

	var events: Array[Dictionary] = []
	var old_focus := focus_id
	_update_focus()
	if focus_id != old_focus:
		events.append({"type": "focus", "id": focus_id})
	return events


## The player pressed interact. If an NPC is in range, starts talking to it
## and returns a "talk" event with its dialogue file.
func interact() -> Array[Dictionary]:
	if is_talking():
		return []
	var npc := npc_by_id(focus_id)
	if npc.is_empty() or npc["dialogue"] == "":
		return []
	begin_talk(npc["id"])
	return [{"type": "talk", "id": npc["id"], "dialogue": npc["dialogue"]}]


func is_talking() -> bool:
	return talk_id != ""


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
	focus_id = best


static func _vec(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO

extends RefCounted
## The meadow: player movement, collision and interaction. Plain data, no
## Nodes, so it runs and tests headless. The view calls step() every frame with
## the input it read and interact() when the player presses interact; both
## return events (Dictionaries with a "type") for the view to show.
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

## Each: {"id", "art", "pos", "footprint", "talk_radius", "say", "rect"}
var npcs: Array[Dictionary] = []
## Each: {"art", "pos", "rect"}
var props: Array[Dictionary] = []
## Each: {"art", "pos"}; cosmetic, placed with the seeded RNG.
var decor: Array[Dictionary] = []
## Collision rects (npc and prop footprints).
var solids: Array[Rect2] = []
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
			"pos": _vec(n.get("pos", [0, 0])),
			"footprint": _vec(n.get("footprint", [16, 6])),
			"talk_radius": float(n.get("talk_radius", 16)),
			"say": str(n.get("say", "")),
		}
		npc["rect"] = footprint_rect(npc["pos"], npc["footprint"])
		npcs.append(npc)
		solids.append(npc["rect"])

	for pr: Dictionary in w.get("props", []):
		var prop := {"art": str(pr.get("art", "")), "pos": _vec(pr.get("pos", [0, 0]))}
		prop["rect"] = footprint_rect(prop["pos"], _vec(pr.get("footprint", [16, 6])))
		props.append(prop)
		solids.append(prop["rect"])

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
func camera_rect(view_size: Vector2) -> Rect2:
	var top_left := player_pos - Vector2(0, player_footprint.y * 2.0) - view_size / 2.0
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


## The player pressed interact. Returns a "say" event if an NPC is in range.
func interact() -> Array[Dictionary]:
	var npc := npc_by_id(focus_id)
	if npc.is_empty():
		return []
	# Turn to face who we talk to.
	facing = 1 if npc["pos"].x >= player_pos.x else -1
	return [{"type": "say", "id": npc["id"], "text_key": npc["say"]}]


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

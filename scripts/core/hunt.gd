extends RefCounted
## Mice at an area's prey spots, and the rules for stalking them. Plain data,
## no Nodes: World owns one per area that has prey_spots and calls step()
## every frame with what Fern is doing; the view only shows the mice.
## preload(), no class_name. Numbers: hunt_tuning.gd (tuning.json "hunt").
##
## A mouse switches on a random timer between head down ("feed", feed_s) and
## head up ("look", look_s). Its alert (0..1) rises while Fern moves and the
## head is up, while she walks (not crouched) within noise_px, or moves (not
## crouched) within close_px; it falls while she holds still. Holding still
## never raises it. Full alert: it squeaks and runs ("flee") into the nearest
## tall grass and is gone; the spot then stays empty for respawn_s. At most
## max_mice at once; new ones appear at a ready spot at least spawn_min_px
## from Fern (the farther, the likelier).
##
## Pouncing: pounce_target() is the nearest mouse within pounce_range (not
## fleeing). land() decides: a catch if its head is down and its alert isn't
## full when Fern lands, else it runs.

const HuntTuning := preload("res://scripts/core/hunt_tuning.gd")

var tuning
## Each: {"id", "pos", "cooldown" (s until a mouse may appear), "mouse" (id or 0)}
var spots: Array[Dictionary] = []
## Each: {"id", "spot" (index), "home", "pos", "state" ("feed" / "look" /
## "flee"), "t" (s left in this state), "alert", "facing", "moving",
## "wander_to", "wander_t", "squeak_t", "flee_to"}
var mice: Array[Dictionary] = []
## Tall-grass patches, where a scared mouse hides.
var hideouts: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var _next_id := 1
var _spawn_t := 0.0


func _init(prey_spots: Array, grass: Array, seed: int = 0, t = null) -> void:
	tuning = t if t != null else HuntTuning.new()
	rng.seed = seed
	for ps: Dictionary in prey_spots:
		spots.append({"id": str(ps["id"]), "pos": ps["pos"], "cooldown": 0.0, "mouse": 0})
	for r in grass:
		hideouts.append(r)


## Fills the area up to max_mice (when Fern arrives).
func fill(player_pos: Vector2) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in tuning.max_mice:
		var ev := _try_spawn(player_pos)
		if ev.is_empty():
			break
		events.append(ev)
	return events


func mouse_by_id(id: int) -> Dictionary:
	for m in mice:
		if m["id"] == id:
			return m
	return {}


## Advances the mice. `p` = {"pos", "moving", "crouched"} for Fern.
func step(dt: float, p: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for s in spots:
		s["cooldown"] = maxf(0.0, s["cooldown"] - dt)
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 1.0
		if mice.size() < tuning.max_mice:
			var ev := _try_spawn(p["pos"])
			if not ev.is_empty():
				events.append(ev)
	for m in mice.duplicate():
		_step_mouse(m, dt, p, events)
	return events


func _step_mouse(m: Dictionary, dt: float, p: Dictionary, events: Array[Dictionary]) -> void:
	m["moving"] = false
	if m["state"] == "flee":
		var to: Vector2 = m["flee_to"]
		m["pos"] = (m["pos"] as Vector2).move_toward(to, tuning.flee_speed * dt)
		m["moving"] = true
		m["t"] -= dt
		if (m["pos"] as Vector2).distance_to(to) < 1.0 or m["t"] <= 0.0:
			_remove(m)
			events.append({"type": "mouse_gone", "id": m["id"], "pos": m["pos"]})
		return
	m["t"] -= dt
	if m["t"] <= 0.0:
		_set_state(m, "look" if m["state"] == "feed" else "feed")
		events.append({"type": "mouse_state", "id": m["id"], "state": m["state"]})
	# Tiny wanders while feeding.
	if m["state"] == "feed":
		m["wander_t"] -= dt
		if m["wander_t"] <= 0.0:
			m["wander_t"] = _between(tuning.wander_every)
			var a := rng.randf() * TAU
			m["wander_to"] = ((m["home"] as Vector2) + Vector2.from_angle(a) * Vector2(1.0, 0.5) * rng.randf_range(0.0, tuning.wander_px)).round()
		var to: Vector2 = m["wander_to"]
		var before: Vector2 = m["pos"]
		m["pos"] = before.move_toward(to, tuning.wander_speed * dt)
		if absf(to.x - before.x) > 0.1:
			m["facing"] = 1 if to.x > before.x else -1
		m["moving"] = not before.is_equal_approx(m["pos"])
	# Alert.
	var d: float = (p["pos"] as Vector2).distance_to(m["pos"])
	if d <= tuning.notice_px:
		if p["moving"]:
			var rise := 0.0
			if m["state"] == "look":
				rise += tuning.look_rise
			if not p["crouched"] and d <= tuning.noise_px:
				rise += tuning.walk_rise
			if not p["crouched"] and d <= tuning.close_px:
				rise += tuning.close_rise
			m["alert"] = minf(1.0, m["alert"] + rise * dt)
		else:
			m["alert"] = maxf(0.0, m["alert"] - tuning.alert_fall * dt)
	elif not p["moving"]:
		m["alert"] = maxf(0.0, m["alert"] - tuning.alert_fall * dt)
	if m["alert"] >= 1.0:
		scare(m)
		events.append({"type": "mouse_flee", "id": m["id"], "pos": m["pos"]})
		return
	m["squeak_t"] -= dt
	if m["squeak_t"] <= 0.0:
		m["squeak_t"] = _between(tuning.squeak_every)
		events.append({"type": "squeak", "id": m["id"], "pos": m["pos"]})


## Sends a mouse running for the nearest tall grass (or away from Fern).
func scare(m: Dictionary) -> void:
	if m["state"] == "flee":
		return
	m["state"] = "flee"
	m["alert"] = 1.0
	var pos: Vector2 = m["pos"]
	var best := pos + Vector2(m["facing"] * 40.0, 0)
	var best_d := INF
	for r in hideouts:
		var c := r.get_center()
		if c.distance_to(pos) < best_d:
			best_d = c.distance_to(pos)
			best = c
	m["flee_to"] = best
	m["facing"] = 1 if best.x >= pos.x else -1
	# Gone after reaching the grass, or after a while at most.
	m["t"] = maxf(0.5, best_d / maxf(1.0, tuning.flee_speed) + 0.2)


## The nearest mouse Fern could pounce on from `from`, or {}: within
## pounce_range and not running.
func pounce_target(from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for m in mice:
		if m["state"] == "flee":
			continue
		var d := from.distance_to(m["pos"])
		if d <= tuning.pounce_range and d < best_d:
			best = m
			best_d = d
	return best


## Fern lands on mouse `id`: true = caught (head down, alert not full); the
## mouse is removed. Otherwise it runs. Spot cooldown starts either way.
func land(id: int) -> bool:
	var m := mouse_by_id(id)
	if m.is_empty() or m["state"] == "flee":
		return false
	if m["state"] == "feed" and m["alert"] < 1.0:
		_remove(m)
		return true
	scare(m)
	return false


## Debug: a mouse at spot `index` now (no cooldown, distance or max check).
func spawn_at(index: int) -> Dictionary:
	if index < 0 or index >= spots.size():
		return {}
	var s: Dictionary = spots[index]
	if s["mouse"] != 0:
		return {}
	return _spawn(index)


## Index of the spot nearest `pos` (-1 without spots).
func nearest_spot(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in spots.size():
		var d := pos.distance_to(spots[i]["pos"])
		if d < best_d:
			best = i
			best_d = d
	return best


func _try_spawn(player_pos: Vector2) -> Dictionary:
	if mice.size() >= tuning.max_mice:
		return {}
	var ready: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	for i in spots.size():
		var s: Dictionary = spots[i]
		var d := player_pos.distance_to(s["pos"])
		if s["mouse"] == 0 and s["cooldown"] <= 0.0 and d >= tuning.spawn_min_px:
			ready.append(i)
			weights.append(d)
			total += d
	if ready.is_empty():
		return {}
	var pick := rng.randf() * total
	for j in ready.size():
		pick -= weights[j]
		if pick <= 0.0 or j == ready.size() - 1:
			return _spawn(ready[j])
	return {}


func _spawn(index: int) -> Dictionary:
	var s: Dictionary = spots[index]
	var m := {"id": _next_id, "spot": index, "home": s["pos"], "pos": s["pos"], "state": "feed",
		"t": 0.0, "alert": 0.0, "facing": 1 if rng.randf() < 0.5 else -1, "moving": false,
		"wander_to": s["pos"], "wander_t": _between(tuning.wander_every),
		"squeak_t": rng.randf_range(1.0, tuning.squeak_every.y), "flee_to": s["pos"]}
	_next_id += 1
	_set_state(m, "feed")
	s["mouse"] = m["id"]
	mice.append(m)
	return {"type": "mouse_spawn", "id": m["id"], "spot": s["id"], "pos": m["pos"]}


func _remove(m: Dictionary) -> void:
	mice.erase(m)
	var s: Dictionary = spots[m["spot"]]
	if s["mouse"] == m["id"]:
		s["mouse"] = 0
		s["cooldown"] = tuning.respawn_s


func _set_state(m: Dictionary, st: String) -> void:
	m["state"] = st
	m["t"] = _between(tuning.feed_s if st == "feed" else tuning.look_s)


func _between(r: Vector2) -> float:
	return rng.randf_range(minf(r.x, r.y), maxf(r.x, r.y))

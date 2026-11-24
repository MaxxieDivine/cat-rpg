extends RefCounted
## Patrols: the deputy sends Fern out on a hunting patrol (bring prey home
## to the fresh-catch pile) or a border patrol (scent-mark spots along the
## territory's edge, then tell the deputy), alone or with 1-2 clanmates.
## Plain data, no Nodes; the Patrols autoload (scripts/autoload/patrols.gd)
## holds one. Numbers and lists: data/patrols.json. preload(), no class_name.
##
## Life of a patrol:
##   roll_offer()  the deputy picks a kind and mates (`offer`)
##   accept()      it starts: phase "gather" (meet at the camp entrance)
##   left_camp()   Fern leaves through the entrance: phase "out"
##   delivered()   hunting: prey reaches the pile; enough of it = done
##   mark()        border: a spot marked; all marked = phase "report"
##   report()      border: told the deputy = done
## Each returns events ({"type": "patrol_*"}) for the view.

const JsonData := preload("res://scripts/core/json_data.gd")
const CONFIG_PATH := "res://data/patrols.json"
const PLAYER := "fern"

var config: Dictionary = {}
var rng := RandomNumberGenerator.new()
## What the deputy offers now: {"kind", "mates" (cat ids), "prey_goal",
## "marks" ([{"area", "id"}])}, or {} (nothing offered yet).
var offer: Dictionary = {}
## The running patrol: offer's keys plus "phase" ("gather", "out",
## "report"), "prey" (delivered so far) and "marked" ("area/id" -> true),
## or {}.
var active: Dictionary = {}
## Patrols finished this game.
var completed := 0
## The last patrol that finished (for tests and the debug label).
var last: Dictionary = {}


func _init(cfg: Dictionary = {}) -> void:
	config = cfg if not cfg.is_empty() else JsonData.load_dict(CONFIG_PATH)
	reset()


func reset() -> void:
	rng.seed = int(config.get("seed", 1))
	offer = {}
	active = {}
	completed = 0
	last = {}


func deputy() -> String:
	return str(config.get("deputy", "rook"))


## Whether cat `id` (rank `rank`) could be sent on a patrol: Fern always,
## others if listed in patrols.json "cats" with a rank in "ranks".
func could_go(id: String, rank: String) -> bool:
	if id == PLAYER:
		return true
	return (config.get("cats", []) as Array).has(id) and (config.get("ranks", []) as Array).has(rank)


## The cats that could go with Fern now, in patrols.json order. `ranks`:
## cat id -> rank id (GameState).
func candidates(ranks: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in config.get("cats", []):
		if could_go(str(id), str(ranks.get(id, ""))):
			out.append(str(id))
	return out


## Fern or a cat on the running patrol (or in the offer being made, while
## `with_offer`).
func picked(id: String, with_offer: bool = false) -> bool:
	if not active.is_empty():
		return id == PLAYER or (active["mates"] as Array).has(id)
	if with_offer and not offer.is_empty():
		return id == PLAYER or (offer["mates"] as Array).has(id)
	return false


func is_active() -> bool:
	return not active.is_empty()


func phase() -> String:
	return str(active.get("phase", ""))


func kind() -> String:
	return str(active.get("kind", offer.get("kind", "")))


func mates() -> Array:
	return active.get("mates", [])


## The deputy picks a patrol (if none is running or offered): a kind by
## weight, mates from `cands` (none with solo_chance), and for a border
## patrol the spots to mark. `spots`: area id -> [spot id, ...] (the areas'
## scent_spots).
func roll_offer(cands: Array, spots: Dictionary) -> Dictionary:
	if is_active():
		return {}
	if not offer.is_empty():
		return offer
	var kinds: Dictionary = config.get("kinds", {"hunting": 1, "border": 1})
	var total := 0.0
	for k: String in kinds:
		total += float(kinds[k])
	var pick := rng.randf() * total
	var kd := "hunting"
	for k: String in kinds:
		pick -= float(kinds[k])
		kd = k
		if pick < 0.0:
			break
	var pool: Array = cands.duplicate()
	var mates_out: Array[String] = []
	if not pool.is_empty() and rng.randf() >= float(config.get("solo_chance", 0.35)):
		var n := rng.randi_range(1, mini(int(config.get("max_mates", 2)), pool.size()))
		for i in n:
			var j := rng.randi_range(0, pool.size() - 1)
			mates_out.append(str(pool[j]))
			pool.remove_at(j)
	var goals: Dictionary = config.get("prey_goal", {})
	offer = {"kind": kd, "mates": mates_out,
		"prey_goal": int(goals.get("solo" if mates_out.is_empty() else "group", 1)),
		"marks": _roll_marks(spots) if kd == "border" else []}
	return offer


func _roll_marks(spots: Dictionary) -> Array:
	var bd: Dictionary = config.get("border", {})
	var out: Array = []
	var main := str(bd.get("area", ""))
	for sid in spots.get(main, []):
		out.append({"area": main, "id": str(sid)})
	var extra := str(bd.get("extra_area", ""))
	var pool: Array = (spots.get(extra, []) as Array).duplicate()
	if not pool.is_empty() and rng.randf() < float(bd.get("extra_chance", 0.4)):
		var n := rng.randi_range(1, mini(int(bd.get("extra_max", 2)), pool.size()))
		for i in n:
			var j := rng.randi_range(0, pool.size() - 1)
			out.append({"area": extra, "id": str(pool[j])})
			pool.remove_at(j)
	return out


## Fern turned the offer down: the deputy thinks again next time.
func decline() -> void:
	offer = {}


## Fern takes the offered patrol: it starts at the camp entrance.
func accept() -> Array[Dictionary]:
	if offer.is_empty() or is_active():
		return []
	active = offer.duplicate(true)
	active["phase"] = "gather"
	active["prey"] = 0
	active["marked"] = {}
	offer = {}
	return [{"type": "patrol_start", "kind": active["kind"], "mates": active["mates"]}]


## Fern went out through the camp entrance.
func left_camp() -> Array[Dictionary]:
	if phase() != "gather":
		return []
	active["phase"] = "out"
	return [{"type": "patrol_out"}]


## Prey reached the fresh-catch pile. A hunting patrol counts it.
func delivered() -> Array[Dictionary]:
	if not is_active() or active["kind"] != "hunting":
		return []
	active["prey"] = int(active["prey"]) + 1
	if int(active["prey"]) >= int(active["prey_goal"]):
		return _finish()
	return [{"type": "patrol_progress", "n": active["prey"], "of": active["prey_goal"]}]


static func mark_key(area: String, id: String) -> String:
	return area + "/" + id


## Whether the running border patrol still needs spot `id` in `area` marked.
func needs_mark(area: String, id: String) -> bool:
	return is_active() and active["kind"] == "border" and wants_mark(area, id) and not is_marked(area, id)


## Whether spot `id` in `area` is one of this patrol's (marked or not).
func wants_mark(area: String, id: String) -> bool:
	if not is_active():
		return false
	for m: Dictionary in active["marks"]:
		if m["area"] == area and m["id"] == id:
			return true
	return false


func is_marked(area: String, id: String) -> bool:
	return is_active() and (active["marked"] as Dictionary).has(mark_key(area, id))


func marks_done() -> int:
	return (active.get("marked", {}) as Dictionary).size()


func marks_total() -> int:
	return (active.get("marks", []) as Array).size()


## Leaves a scent mark. The last one sends Fern back to report.
func mark(area: String, id: String) -> Array[Dictionary]:
	if not needs_mark(area, id):
		return []
	active["marked"][mark_key(area, id)] = true
	var ev: Array[Dictionary] = [{"type": "patrol_mark", "area": area, "id": id, "n": marks_done(), "of": marks_total()}]
	if marks_done() >= marks_total():
		active["phase"] = "report"
		ev.append({"type": "patrol_report"})
	return ev


## Fern told the deputy the border is marked.
func report() -> Array[Dictionary]:
	if phase() != "report":
		return []
	return _finish()


func _finish() -> Array[Dictionary]:
	last = active
	active = {}
	completed += 1
	return [{"type": "patrol_done", "kind": last["kind"], "mates": last["mates"]}]


## What the patrol needs now, for the hud: {"key" (strings.json), "n",
## "of"} or {} with no patrol.
func goal() -> Dictionary:
	match phase():
		"gather":
			return {"key": "patrol.goal_gather", "n": 0, "of": 0}
		"out":
			if active["kind"] == "hunting":
				return {"key": "patrol.goal_prey", "n": active["prey"], "of": active["prey_goal"]}
			return {"key": "patrol.goal_marks", "n": marks_done(), "of": marks_total()}
		"report":
			return {"key": "patrol.goal_report", "n": marks_done(), "of": marks_total()}
	return {}


## The flags the deputy's conversation branches on (data/state.json):
## patrol_offer (kind offered or null), patrol_group, patrol (phase or null).
func dialogue_flags() -> Dictionary:
	var src := active if is_active() else offer
	return {
		"patrol_offer": null if offer.is_empty() else offer["kind"],
		"patrol_group": not (src.get("mates", []) as Array).is_empty(),
		"patrol": null if not is_active() else active["phase"],
	}

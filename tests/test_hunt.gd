extends "res://tests/test_base.gd"
## Hunting rules (core, headless): mice switch head down / head up within
## their time ranges; alert only rises while Fern moves (head up, walking
## close, very close uncrouched) and falls while she holds still; a full
## alert sends the mouse into the tall grass and the spot respawns after
## respawn_s; mice never spawn near Fern; pounce range, the leap, catch and
## miss; carrying, delivering to the pile, eating, giving to Sorrel; the
## pile never refills by itself. Expected numbers come from tuning.json.

const Hunt := preload("res://scripts/core/hunt.gd")
const HuntTuning := preload("res://scripts/core/hunt_tuning.gd")
const World := preload("res://scripts/core/world.gd")
const Areas := preload("res://scripts/core/areas.gd")
const NeedsCore := preload("res://scripts/core/needs.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const DT := 1.0 / 60.0

var tuning: Dictionary
var ht
var spot := Vector2(300, 200)


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	ht = HuntTuning.new(tuning["hunt"])


## One spot, one mouse, Fern far away; `seed` for the timers.
func _hunt(seed: int = 3):
	var h = Hunt.new([{"id": "a", "pos": spot}], [Rect2(340, 180, 40, 30)], seed, ht)
	h.fill(spot + Vector2(500, 0))
	return h


func _mouse(h) -> Dictionary:
	return h.mice[0] if not h.mice.is_empty() else {}


func _run(h, seconds: float, p: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in roundi(seconds * 60.0):
		out.append_array(h.step(DT, p))
	return out


func _hold(m: Dictionary, state: String) -> void:
	m["state"] = state
	m["t"] = 999.0
	m["wander_t"] = 999.0


func test_tuning_from_data() -> void:
	var t: Dictionary = tuning["hunt"]
	check_near(ht.crouch_speed, float(t["crouch_speed"]), 0.001, "crouch speed")
	check_eq(ht.feed_s, Vector2(t["feed_s"][0], t["feed_s"][1]), "head-down range")
	check_eq(ht.max_mice, int(t["max_mice"]), "max mice")
	check_near(ht.pounce_range, 40.0, 10.0, "pounce range about 40 px")
	check_near(ht.respawn_s, 30.0, 15.0, "respawn about 30 s")
	check(ht.crouch_speed < float(tuning["player"]["walk_speed"]) / 2.0, "crouching is much slower than walking")


func test_heads_go_down_and_up_on_their_timers() -> void:
	var h = _hunt()
	var m := _mouse(h)
	check_eq(m["state"], "feed", "a new mouse is feeding")
	var spans := {"feed": [], "look": []}
	var cur: String = m["state"]
	var since := 0.0
	var first := true
	for i in 60 * 60:
		h.step(DT, {"pos": spot + Vector2(500, 0), "moving": false, "crouched": false})
		since += DT
		if m["state"] != cur:
			if not first:
				spans[cur].append(since)
			first = false
			cur = m["state"]
			since = 0.0
	check(spans["feed"].size() >= 5 and spans["look"].size() >= 5, "switches back and forth (%d / %d)" % [spans["feed"].size(), spans["look"].size()])
	for st in spans:
		var r: Vector2 = ht.feed_s if st == "feed" else ht.look_s
		for d: float in spans[st]:
			check(d >= r.x - 0.05 and d <= r.y + 0.05, "%s lasted %.2f s, within %s" % [st, d, r])


func test_standing_still_never_raises_alert() -> void:
	var h = _hunt()
	var m := _mouse(h)
	_hold(m, "look")
	# Right next to it, not crouched, head up: still nothing.
	_run(h, 5.0, {"pos": spot + Vector2(10, 0), "moving": false, "crouched": false})
	check_eq(m["alert"], 0.0, "holding still raises nothing, even with its head up")
	m["alert"] = 0.6
	_run(h, 1.0, {"pos": spot + Vector2(10, 0), "moving": false, "crouched": false})
	check_near(m["alert"], 0.6 - ht.alert_fall, 0.02, "alert falls by alert_fall per second while still")


func test_moving_while_it_looks_raises_alert() -> void:
	var h = _hunt()
	var m := _mouse(h)
	_hold(m, "look")
	var far := spot + Vector2(ht.noise_px + 20.0, 0)
	_run(h, 0.5, {"pos": far, "moving": true, "crouched": true})
	check_near(m["alert"], ht.look_rise * 0.5, 0.03, "crouched but moving while it looks: rises by look_rise")


func test_crouched_stalking_while_it_feeds_is_safe() -> void:
	var h = _hunt()
	var m := _mouse(h)
	_hold(m, "feed")
	_run(h, 3.0, {"pos": spot + Vector2(ht.close_px - 4.0, 0), "moving": true, "crouched": true})
	check_eq(m["alert"], 0.0, "crouch-moving while it feeds raises nothing, even close")
	check_eq(m["state"], "feed", "still feeding")


func test_walking_close_raises_alert() -> void:
	var h = _hunt()
	var m := _mouse(h)
	_hold(m, "feed")
	_run(h, 0.5, {"pos": spot + Vector2(ht.noise_px - 5.0, 0), "moving": true, "crouched": false})
	check_near(m["alert"], ht.walk_rise * 0.5, 0.03, "walking (not crouched) within noise_px rises by walk_rise")
	m["alert"] = 0.0
	_run(h, 0.2, {"pos": spot + Vector2(ht.close_px - 4.0, 0), "moving": true, "crouched": false})
	check_near(m["alert"], (ht.walk_rise + ht.close_rise) * 0.2, 0.03, "very close and uncrouched rises faster")
	m["alert"] = 0.0
	_run(h, 1.0, {"pos": spot + Vector2(ht.notice_px + 30.0, 0), "moving": true, "crouched": false})
	check_eq(m["alert"], 0.0, "too far away to notice")


func test_full_alert_runs_into_the_grass_and_respawns() -> void:
	var h = _hunt()
	var m := _mouse(h)
	_hold(m, "look")
	var p := {"pos": spot + Vector2(30, 0), "moving": true, "crouched": false}
	var ev := _run(h, 2.0, p)
	check(ev.any(func(e): return e["type"] == "mouse_flee"), "it bolts when alert is full")
	check(ev.any(func(e): return e["type"] == "mouse_gone"), "and disappears")
	check(h.mice.is_empty(), "gone")
	check(h.spots[0]["cooldown"] > ht.respawn_s - 2.5, "spot waits respawn_s (%.1f)" % h.spots[0]["cooldown"])
	var gone: Dictionary = ev.filter(func(e): return e["type"] == "mouse_gone")[0]
	check(Rect2(340, 180, 40, 30).grow(2).has_point(gone["pos"]), "it ran into the tall grass (%s)" % gone["pos"])
	var away := {"pos": spot + Vector2(500, 0), "moving": false, "crouched": false}
	_run(h, ht.respawn_s - 3.0, away)
	check(h.mice.is_empty(), "not back before respawn_s")
	_run(h, 5.0, away)
	check_eq(h.mice.size(), 1, "back after respawn_s")


func test_never_spawns_near_fern_and_keeps_max() -> void:
	var spots := []
	for i in 4:
		spots.append({"id": "s%d" % i, "pos": Vector2(100 + i * 200, 200)})
	var h = Hunt.new(spots, [], 7, ht)
	var fern := Vector2(100, 205)
	h.fill(fern)
	check_eq(h.mice.size(), ht.max_mice, "fills up to max_mice")
	for m in h.mice:
		check(fern.distance_to(m["pos"]) >= ht.spawn_min_px, "spawned %.0f px from Fern" % fern.distance_to(m["pos"]))
	_run(h, 120.0, {"pos": fern, "moving": false, "crouched": false})
	check(h.mice.size() <= ht.max_mice, "never more than max_mice")
	# Fern sits on every spot: nothing spawns.
	var h2 = Hunt.new([{"id": "x", "pos": fern}], [], 7, ht)
	h2.fill(fern)
	_run(h2, 10.0, {"pos": fern, "moving": false, "crouched": false})
	check(h2.mice.is_empty(), "no mouse appears right next to Fern")


# --- World: crouch, pounce, carry


func _grounds():
	var w = Areas.new().load_world("hunting_grounds", tuning)
	w.hunt_tuning = ht
	w.place_at_spawn("from_camp")
	w.step(DT, Vector2.ZERO, false)  # fills the mice
	return w


## Fern crouched `gap` px left of a mouse held in `state`.
func _stalk(w, state: String, gap: float = 30.0) -> Dictionary:
	var m: Dictionary = w.hunt.mice[0]
	_hold(m, state)
	m["alert"] = 0.0
	w.player_pos = (m["pos"] as Vector2) - Vector2(gap, 0)
	w.player_vel = Vector2.ZERO
	w.step(DT, Vector2.ZERO, false, true)
	return m


func test_grounds_have_mice_at_prey_spots() -> void:
	var w = _grounds()
	check(w.hunt != null, "the Hunting Grounds has a hunt")
	check_eq(w.hunt.mice.size(), ht.max_mice, "max_mice mice on arrival")
	var camp = Areas.new().load_world("camp", tuning)
	check(camp.hunt == null, "no mice in camp")


func test_crouching_is_slow() -> void:
	var w = _grounds()
	w.player_pos = Vector2(150, 250)
	for i in 60:
		w.step(DT, Vector2.RIGHT, true, true)
	check_near(w.speed(), ht.crouch_speed, 0.5, "crouch speed (trot ignored)")
	check(w.crouching, "crouching")


func test_pounce_needs_crouch_range_and_empty_mouth() -> void:
	var w = _grounds()
	var m := _stalk(w, "feed")
	check(w.can_pounce(), "crouched within range: can pounce")
	w.step(DT, Vector2.ZERO, false, false)
	check(not w.can_pounce(), "not crouched: can't")
	_stalk(w, "feed", ht.pounce_range + 8.0)
	check(not w.can_pounce(), "out of range: can't")
	_stalk(w, "feed")
	w.player_state.carried_item = "mouse"
	check(not w.can_pounce(), "carrying: can't")
	w.player_state.carried_item = ""
	check_eq(w.pounce_target()["id"], m["id"], "targets that mouse")


func test_pounce_catches_a_feeding_mouse() -> void:
	var w = _grounds()
	var m := _stalk(w, "feed")
	var id: int = m["id"]
	var ev: Array = w.pounce()
	check_eq(ev[0]["type"], "pounce", "leaps")
	check(w.is_leaping(), "in the air")
	var start: Vector2 = w.player_pos
	var heights := []
	var events: Array[Dictionary] = []
	for i in roundi(ht.leap_s * 60.0) + 2:
		heights.append(w.leap_height())
		events.append_array(w.step(DT, Vector2.UP, true, true))
	check(heights.max() > ht.leap_height * 0.8, "rises (%.1f px)" % heights.max())
	check_eq(w.leap_height(), 0.0, "lands")
	check(w.player_pos.distance_to(m["pos"]) < 3.0 or w.player_pos.distance_to(start) > 20.0, "lands on the mouse")
	check(events.any(func(e): return e["type"] == "catch"), "caught it")
	check_eq(w.carrying(), "mouse", "carrying the mouse")
	check(w.hunt.mouse_by_id(id).is_empty(), "the mouse is gone from the grass")
	check_eq(w.action, "catch", "a short happy pause")
	check(not w.can_pounce(), "can't pounce while carrying")


func test_pounce_misses_when_it_looks_up() -> void:
	var w = _grounds()
	var m := _stalk(w, "feed")
	w.pounce()
	_hold(m, "look")
	var events: Array[Dictionary] = []
	for i in roundi(ht.leap_s * 60.0) + 2:
		events.append_array(w.step(DT, Vector2.ZERO, false, true))
	check(events.any(func(e): return e["type"] == "miss"), "missed")
	check_eq(w.carrying(), "", "nothing caught")
	check_eq(m["state"], "flee", "it runs")
	check_eq(w.action, "stumble", "Fern stumbles")


func test_leap_locks_control() -> void:
	var w = _grounds()
	_stalk(w, "feed")
	w.pounce()
	var to: Vector2 = w.leap["to"]
	var from: Vector2 = w.leap["from"]
	var n := roundi(ht.leap_s * 60.0 / 2.0)
	for i in n:
		w.step(DT, Vector2.DOWN, true, false)
	var mid: Vector2 = from.lerp(to, n * DT / ht.leap_s)
	check(w.player_pos.distance_to(mid) < 1.0, "on the leap's line, ignoring the stick")


func test_eat_carried_or_keep_when_full() -> void:
	var w = _grounds()
	var n = NeedsCore.new(tuning["needs"])
	w.player_state.carried_item = "mouse"
	w.player_pos = Vector2(150, 250)
	w.step(DT, Vector2.ZERO, false)
	check_eq(w.focus_id, "", "nothing nearby")
	n.hunger = 95
	var ev: Array = w.interact(n)
	check_eq(str(ev[0].get("key", "")), "needs.not_hungry", "too full to eat it")
	check_eq(w.carrying(), "mouse", "kept")
	n.hunger = 30
	ev = w.interact(n)
	check_eq(ev[0]["type"], "eat", "eats it")
	check_eq(n.hunger, 30 + int(tuning["needs"]["eat"]), "same as a bite from the pile")
	check_eq(w.carrying(), "", "gone")


func test_deliver_to_the_pile() -> void:
	var w = Areas.new().load_world("camp", tuning)
	var n = NeedsCore.new(tuning["needs"])
	var r: Rect2 = w.pile["rect"]
	w.player_pos = Vector2(r.end.x + w.player_footprint.x / 2.0 + 4.0, r.end.y)
	w.step(DT, Vector2.ZERO, false)
	check_eq(w.focus_id, World.PILE_ID, "at the pile")
	var before: int = w.pile["prey"]
	w.player_state.carried_item = "mouse"
	n.hunger = 10
	var ev: Array = w.interact(n)
	check_eq(ev[0]["type"], "deliver", "delivered (not eaten, though hungry)")
	check_eq(w.pile["prey"], before + 1, "+1 on the pile")
	check_eq(w.carrying(), "", "dropped")
	check_eq(n.hunger, 10, "Fern didn't eat")
	w.action = ""
	w.pile["prey"] = w.pile["max"]
	w.player_state.carried_item = "mouse"
	ev = w.interact(n)
	check_eq(str(ev[0].get("key", "")), "hunt.pile_full", "a full pile says so")
	check_eq(w.carrying(), "mouse", "still carrying")


func test_give_to_sorrel() -> void:
	var w = Areas.new().load_world("camp", tuning)
	var sorrel: Dictionary = w.npc_by_id("sorrel")
	var r: Rect2 = sorrel["rect"]
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 4.0, r.end.y)
	w.step(DT, Vector2.ZERO, false)
	check_eq(w.focus_id, "sorrel", "next to Sorrel")
	w.player_state.carried_item = "mouse"
	var ev: Array = w.interact(null)
	check_eq(ev[0]["type"], "give", "gives her the mouse")
	check_eq(str(ev[1].get("key", "")), "hunt.sorrel_thanks", "her thank-you line")
	check_eq(w.carrying(), "", "given away")
	check(not w.is_talking(), "no conversation opens")
	# Without prey, she talks as before.
	w.action = ""
	ev = w.interact(null)
	check_eq(ev[0]["type"], "talk", "talks when Fern carries nothing")


func test_hunting_autoload_exports_change_the_shared_tuning() -> void:
	var before: float = Hunting.tuning.crouch_speed
	Hunting.crouch_speed = 55.0
	check_eq(Hunting.tuning.crouch_speed, 55.0, "Inspector edit reaches the shared tuning")
	Hunting.head_up_s = Vector2(0.5, 0.7)
	check_eq(Hunting.tuning.look_s, Vector2(0.5, 0.7), "head-up range")
	Hunting.reset()
	check_eq(Hunting.tuning.crouch_speed, before, "reset back to tuning.json")

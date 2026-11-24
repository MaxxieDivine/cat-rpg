extends "res://tests/test_base.gd"
## Patrols (core, headless): who could go, the deputy's offer (kind,
## mates, border spots), a patrol's life (gather -> out -> done, or ->
## report -> done), the goal line, the deputy's conversation branching on
## the patrol flags, and patrol mates walking in world.gd (to the entrance,
## following Fern, home again). Expected values come from data/patrols.json.

const Patrol := preload("res://scripts/core/patrol.gd")
const World := preload("res://scripts/core/world.gd")
const Areas := preload("res://scripts/core/areas.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")
const DT := 1.0 / 60.0

var cfg: Dictionary
var tuning: Dictionary
var p
## Every area's scent spot ids, as the autoload builds them.
var spots: Dictionary = {}


func before_each() -> void:
	cfg = JsonData.load_dict("res://data/patrols.json")
	tuning = JsonData.load_dict("res://data/tuning.json")
	p = Patrol.new()
	var areas := Areas.new()
	spots = {}
	for a in areas.ids():
		var ids: Array = []
		for s: Dictionary in areas.area_data(a).get("scent_spots", []):
			ids.append(s["id"])
		if not ids.is_empty():
			spots[a] = ids


func _ranks() -> Dictionary:
	var gs = GameStateCore.new()
	var r := {}
	for id: String in gs.cats:
		r[id] = gs.get_cat_rank(id)
	return r


func _offer(kind: String, mates: Array) -> void:
	p.offer = {"kind": kind, "mates": mates, "prey_goal": int(cfg["prey_goal"]["solo" if mates.is_empty() else "group"]),
		"marks": p._roll_marks(spots) if kind == "border" else []}


func test_who_could_go() -> void:
	var r := _ranks()
	check(p.could_go("fern", r["fern"]), "Fern can always go")
	check(p.could_go("bram", r["bram"]), "Bram (warrior)")
	check(p.could_go("wick", r["wick"]), "Wick (apprentice)")
	for id in ["sorrel", "larch", "rook"]:
		check(not p.could_go(id, r[id]), "%s can't (rank %s)" % [id, r[id]])
	check(not p.could_go("bram", "kit"), "a kit can't")
	check(not p.could_go("sorrel", "warrior"), "only cats patrols.json lists (they need a walk)")
	check_eq(p.candidates(r), ["bram", "wick"], "candidates in patrols.json order")
	check_eq(p.deputy(), str(cfg["deputy"]), "the deputy from patrols.json")


func test_the_deputy_picks_kinds_and_mates() -> void:
	var r := _ranks()
	var kinds := {}
	var sizes := {}
	for i in 60:
		p.offer = {}
		var o: Dictionary = p.roll_offer(p.candidates(r), spots)
		kinds[o["kind"]] = true
		sizes[o["mates"].size()] = true
		check(o["mates"].size() <= int(cfg["max_mates"]), "at most %d mates" % cfg["max_mates"])
		var seen := {}
		for m in o["mates"]:
			check(p.candidates(r).has(m) and not seen.has(m), "mate %s is a candidate, once" % m)
			seen[m] = true
		check_eq(o["prey_goal"], int(cfg["prey_goal"]["solo" if o["mates"].is_empty() else "group"]), "prey goal for its size")
		if o["kind"] == "border":
			check(o["marks"].size() >= spots[cfg["border"]["area"]].size(), "every spot along the main border")
	check(kinds.has("hunting") and kinds.has("border"), "both kinds come up (%s)" % [kinds.keys()])
	check(sizes.has(0) and sizes.has(1) and sizes.has(2), "solo, one mate and two mates all happen (%s)" % [sizes.keys()])
	# Same seed, same offers.
	var a = Patrol.new()
	var b = Patrol.new()
	check_eq(a.roll_offer(["bram", "wick"], spots), b.roll_offer(["bram", "wick"], spots), "seeded: deterministic")
	# The offer stands until taken or turned down.
	var first: Dictionary = a.offer.duplicate(true)
	check_eq(a.roll_offer(["bram", "wick"], spots), first, "asking again: the same offer")
	a.decline()
	check(a.offer.is_empty(), "declined: no offer")
	check(p.roll_offer([], spots)["mates"].is_empty(), "no candidates: solo")


func test_solo_hunting_patrol() -> void:
	_offer("hunting", [])
	check(p.picked("fern", true), "Fern is picked in the offer")
	check(not p.picked("fern"), "not on a patrol yet")
	var ev: Array = p.accept()
	check_eq(ev[0]["type"], "patrol_start", "starts")
	check(p.is_active() and p.offer.is_empty(), "active, offer used up")
	check_eq(p.phase(), "gather", "meet at the entrance first")
	check_eq(p.goal()["key"], "patrol.goal_gather", "goal: meet up")
	check(p.accept().is_empty(), "can't start twice")
	check_eq(p.left_camp()[0]["type"], "patrol_out", "leaving camp sets out")
	check(p.left_camp().is_empty(), "once")
	check_eq(p.goal(), {"key": "patrol.goal_prey", "n": 0, "of": 1}, "goal: prey 0 / 1")
	ev = p.delivered()
	check_eq(ev[0]["type"], "patrol_done", "one prey home: done")
	check(not p.is_active(), "over")
	check_eq(p.completed, 1, "counted")
	check(p.goal().is_empty(), "no goal")
	check(p.delivered().is_empty(), "more prey is just prey")


func test_group_hunting_needs_more_prey() -> void:
	_offer("hunting", ["bram"])
	p.accept()
	check(p.picked("bram") and p.picked("fern") and not p.picked("wick"), "Fern and Bram are on it, Wick isn't")
	p.left_camp()
	var ev: Array = p.delivered()
	check_eq(ev[0]["type"], "patrol_progress", "the first prey counts")
	check_eq(p.goal()["n"], 1, "1 / 2")
	check_eq(p.delivered()[0]["type"], "patrol_done", "the second finishes it")


func test_border_patrol_marks_and_reports() -> void:
	_offer("border", ["wick"])
	p.accept()
	p.left_camp()
	var marks: Array = p.active["marks"]
	check(marks.size() >= 3, "several spots (%d)" % marks.size())
	check_eq(p.goal(), {"key": "patrol.goal_marks", "n": 0, "of": marks.size()}, "goal: marks 0 / n")
	check(p.mark("hunting_grounds_2", "nope").is_empty(), "an unknown spot does nothing")
	check(p.delivered().is_empty(), "prey doesn't finish a border patrol")
	for i in marks.size():
		var m: Dictionary = marks[i]
		check(p.needs_mark(m["area"], m["id"]), "%s/%s needed" % [m["area"], m["id"]])
		var ev: Array = p.mark(m["area"], m["id"])
		check_eq(ev[0]["type"], "patrol_mark", "marked")
		check_eq(ev[0]["n"], i + 1, "counter goes up")
		check(not p.needs_mark(m["area"], m["id"]) and p.is_marked(m["area"], m["id"]), "done, not needed again")
		check(p.mark(m["area"], m["id"]).is_empty(), "marking twice does nothing")
		if i == marks.size() - 1:
			check_eq(ev[ev.size() - 1]["type"], "patrol_report", "the last one: go and report")
	check_eq(p.phase(), "report", "report phase")
	check_eq(p.goal()["key"], "patrol.goal_report", "goal: tell the deputy")
	check_eq(p.report()[0]["type"], "patrol_done", "reported: done")
	check(p.report().is_empty(), "once")


func test_border_offers_sometimes_include_the_first_grounds() -> void:
	var extra := 0
	var bd: Dictionary = cfg["border"]
	for i in 40:
		p.offer = {}
		p.rng.seed = 1000 + i
		var marks: Array = p._roll_marks(spots)
		var n: int = marks.filter(func(m): return m["area"] == bd["extra_area"]).size()
		check(n <= int(bd["extra_max"]), "at most %d extra spots" % bd["extra_max"])
		extra += 1 if n > 0 else 0
	check(extra > 2 and extra < 38, "sometimes, not always (%d / 40)" % extra)


func test_dialogue_flags() -> void:
	check_eq(p.dialogue_flags(), {"patrol_offer": null, "patrol_group": false, "patrol": null}, "nothing yet")
	_offer("border", ["bram", "wick"])
	check_eq(p.dialogue_flags(), {"patrol_offer": "border", "patrol_group": true, "patrol": null}, "offered")
	p.accept()
	check_eq(p.dialogue_flags()["patrol"], "gather", "gathering")


## The deputy's conversation branches on the flags the autoload writes.
func test_deputy_conversation_branches() -> void:
	var conv := JsonData.load_dict("res://data/dialogue/rook.json")
	var cases := [
		[{"patrol_offer": "hunting", "patrol_group": false}, "Hunting patrol", "alone"],
		[{"patrol_offer": "hunting", "patrol_group": true}, "Hunting patrol", "will go with you"],
		[{"patrol_offer": "border", "patrol_group": false}, "Border patrol. Mark the edge by the second hunting ground.", "alone"],
		[{"patrol_offer": "border", "patrol_group": true}, "Border patrol", "will go with you"],
	]
	for c in cases:
		var gs = GameStateCore.new()
		for k: String in c[0]:
			gs.set_flag(k, c[0][k])
		var d = Dialogue.new(gs)
		var line: Dictionary = d.start(conv)
		check(str(line["text"]).begins_with(c[1]), "%s: %s" % [c[0], line["text"]])
		line = d.advance()
		check(str(line["text"]).contains(c[2]), "%s: then %s" % [c[0], line["text"]])
		check_eq(line["choices"].size(), 2, "accept or not")
		d.choose(0)
		check_eq(gs.get_flag("patrol"), "accepted", "On my way. sets patrol = accepted")
	for ph in [["gather", "waiting"], ["out", "not done"], ["report", "border's marked"]]:
		var gs = GameStateCore.new()
		gs.set_flag("patrol", ph[0])
		var line: Dictionary = Dialogue.new(gs).start(conv)
		check(str(line["text"]).contains(ph[1]), "patrol %s: %s" % [ph[0], line["text"]])


func test_text_vars() -> void:
	var gs = GameStateCore.new()
	check(gs.placeholders().has("patrol_mates"), "{patrol_mates} is a known placeholder")
	check(gs.set_text_var("patrol_mates", "Bram and Wick"), "set")
	check_eq(gs.format_text("{patrol_mates} go."), "Bram and Wick go.", "filled in")
	check(not gs.set_text_var("nope", "x"), "unknown text vars refused")
	gs.reset()
	check(gs.format_text("{patrol_mates}") != "Bram and Wick", "reset clears it")


# --- Patrol mates in world.gd


func _camp():
	var w = World.new(JsonData.load_dict("res://data/world.json"), tuning)
	w.follow_gap = float(cfg["follow_gap"])
	w.follow_speed = float(cfg["follow_speed"])
	w.home_speed = float(cfg["home_speed"])
	return w


func _run(w, seconds: float, move: Vector2 = Vector2.ZERO, run: bool = false) -> void:
	for i in roundi(seconds * 60.0):
		w.step(DT, move, run)


func test_mates_walk_to_the_entrance_and_wait() -> void:
	var w = _camp()
	var meet: Vector2 = w.markers[cfg["meet"]]
	var bram_home: Vector2 = w.npc_by_id("bram")["pos"]
	check(w.send_npc("bram", meet), "sent")
	var bram: Dictionary = w.npc_by_id("bram")
	check(not World.talkable(bram), "can't be talked to while walking a patrol")
	check(not w.solids.has(bram["rect"]), "not solid while walking")
	_run(w, 0.2)
	check(bram["moving"], "walking")
	_run(w, bram_home.distance_to(meet) / (w.follow_speed * 0.5) + 1.0)
	check_eq(bram["pos"], meet, "at the camp entrance")
	check_eq(bram["mode"], "wait", "waiting")
	check(not bram["moving"], "standing")
	var exit_r: Rect2 = w.exits.filter(func(e): return e["id"] == cfg["entrance_exit"])[0]["rect"]
	check(meet.distance_to(exit_r.get_center()) < 80.0, "the meeting point is by the entrance")
	# Home again: its own spot and behaviour.
	w.send_home("bram")
	_run(w, bram_home.distance_to(meet) / w.home_speed + 1.0)
	check_eq(bram["pos"], bram_home, "back home")
	check_eq(str(bram.get("mode", "")), "", "itself again")
	check(World.talkable(bram), "talkable again")
	check(w.solids.has(bram["rect"]), "solid again")


func test_mates_follow_fern() -> void:
	var w = _camp()
	w.place_at_spawn("from_hunting")
	w.follow(["bram", "wick"])
	check_eq(w.followers(), ["bram", "wick"], "following, nearest first")
	var bram: Dictionary = w.npc_by_id("bram")
	var wick: Dictionary = w.npc_by_id("wick")
	# Walk left along the camp's path for a while: they trail behind.
	_run(w, 3.0, Vector2.LEFT)
	_run(w, 1.5)
	var gap := float(cfg["follow_gap"])
	check_near(bram["pos"].distance_to(w.player_pos), gap, 4.0, "Bram one gap behind")
	check_near(wick["pos"].distance_to(w.player_pos), gap * 2.0, 6.0, "Wick two gaps behind")
	check(bram["pos"].x > w.player_pos.x and wick["pos"].x > bram["pos"].x, "behind her, in a line")
	check(not bram["moving"], "they stop when she stops")
	check_eq(bram["facing"], -1, "and face her")
	# Wick's pacing is off while he follows.
	var before: Vector2 = wick["pos"]
	_run(w, 2.0)
	check_eq(wick["pos"], before, "Wick doesn't pace off")
	# They keep up with a trotting Fern.
	_run(w, 2.0, Vector2.DOWN + Vector2.LEFT * 0.2, true)
	_run(w, 0.8)
	check(bram["pos"].distance_to(w.player_pos) < gap * 1.6, "Bram keeps up with a trot")
	w.stop_following()
	check(w.followers().is_empty(), "stopped")


func test_mates_join_fern_in_the_hunting_grounds() -> void:
	var w = Areas.new().load_world("hunting_grounds", tuning)
	w.follow_gap = float(cfg["follow_gap"])
	w.place_at_spawn("from_camp")
	var b: Dictionary = w.add_follower("bram")
	w.add_follower("wick")
	check_eq(w.followers(), ["bram", "wick"], "both follow")
	check(b["pos"].x < w.player_pos.x, "behind Fern (she faces into the grounds)")
	check(w.bounds.encloses(w.footprint_rect(b["pos"], b["footprint"])), "inside the area")
	check(not World.talkable(b), "visitors can't be talked to")
	_run(w, 2.0, Vector2.RIGHT)
	_run(w, 1.0)
	check_near(b["pos"].distance_to(w.player_pos), float(cfg["follow_gap"]), 4.0, "following")

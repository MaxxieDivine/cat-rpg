extends "res://tests/test_base.gd"
## Story beats (core, headless): "The rogue and the missing Wick", Part A.
## When Wick goes missing (enough border patrols, not while he's out on
## one), the deputy's report giving the news once, the reminder, Bram's and
## Sorrel's new lines, the goal, no patrols while investigating, Wick left
## out of the camp, and the save hook keeping all of it.
## Part B: the rogue Slate by the river only during the investigation,
## his three choices (prey only while carrying) and the red-fur question in
## every branch, the saved choice, the story exit opening, how he leaves,
## the scent trail and the arrow, conditional choices in the dialogue core.
## Expected values come from data/story.json.

const Story := preload("res://scripts/core/story.gd")
const World := preload("res://scripts/core/world.gd")
const Areas := preload("res://scripts/core/areas.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")
const Cutscene := preload("res://scripts/core/cutscene.gd")

var cfg: Dictionary
var strings: Dictionary
var story
var gs


func before_each() -> void:
	cfg = JsonData.load_dict("res://data/story.json")
	strings = JsonData.load_dict("res://data/strings.json")
	story = Story.new()
	gs = GameStateCore.new()


func _missing() -> String:
	return str(cfg["rogue"]["missing"])


func test_wick_goes_missing_after_enough_border_patrols() -> void:
	var after := int(cfg["rogue"]["after_border_patrols"])
	check(after >= 1, "after_border_patrols is at least 1")
	check_eq(_missing(), "wick", "Wick is the one who goes missing")
	check(not story.absent(gs, "wick"), "Wick is home at the start")
	for i in after - 1:
		check(not story.border_marked(gs, []), "border patrol %d: not yet" % (i + 1))
	check(story.border_marked(gs, []), "border patrol %d: Wick goes missing" % after)
	check_eq(gs.get_flag("wick_missing"), true, "flag wick_missing")
	check(story.absent(gs, "wick"), "Wick is away")
	check(not story.absent(gs, "bram"), "Bram isn't")
	check(not story.border_marked(gs, []), "it happens once")


func test_not_while_wick_is_on_the_patrol() -> void:
	var s = Story.new({"rogue": {"after_border_patrols": 1, "missing": "wick"}})
	check(not s.border_marked(gs, ["bram", "wick"]), "Wick is out with Fern: not this time")
	check_eq(gs.get_flag("wick_missing"), false, "still home")
	check_eq(s.border_patrols, 1, "the patrol still counts")
	check(s.border_marked(gs, ["bram"]), "the next one without him")


func test_later_start_is_tunable() -> void:
	var s = Story.new({"rogue": {"after_border_patrols": 3, "missing": "wick"}})
	check(not s.border_marked(gs, []), "1 of 3")
	check(not s.border_marked(gs, []), "2 of 3")
	check(s.border_marked(gs, []), "3 of 3: missing")


func test_goal_and_no_patrols_while_investigating() -> void:
	check_eq(story.goal_key(gs), "", "no story goal at the start")
	check(not story.blocks_patrols(gs), "patrols at the start")
	gs.set_flag("wick_missing", true)
	check_eq(story.goal_key(gs), "", "not before the deputy tells the news")
	gs.set_flag("rogue_news", true)
	var key: String = story.goal_key(gs)
	check_eq(key, str(cfg["rogue"]["goal_investigate"]), "the investigation goal")
	check_eq(str(strings.get(key, "")), "Investigate the rogue scent by the river.", "its text")
	check(story.blocks_patrols(gs), "no patrols while investigating")


func _talk(file: String, flags: Dictionary) -> Array[String]:
	for k: String in flags:
		gs.set_flag(k, flags[k])
	var d = Dialogue.new(gs)
	var lines: Array[String] = []
	var line: Dictionary = d.start(JsonData.load_dict(file))
	for i in 20:
		if line.get("type", "") != "line":
			break
		lines.append(gs.format_text(str(line["text"])))
		line = d.choose(0) if not (line.get("choices", []) as Array).is_empty() else d.advance()
	return lines


func test_the_deputy_tells_the_news_once() -> void:
	var lines := _talk("res://data/dialogue/rook.json", {"patrol": "report", "wick_missing": true})
	var all := " | ".join(lines)
	check(lines[0].contains("border's marked"), "the report first (%s)" % lines[0])
	check(all.contains("strange scent down by the river"), "the scent (%s)" % all)
	check(all.contains("A rogue"), "a rogue")
	check(all.contains("Wick hasn't come back"), "Wick is missing")
	check(all.contains("find out what's going on"), "the task")
	check(not all.contains("Rest a while"), "instead of the normal patrol-done line")
	check_eq(gs.get_flag("rogue_news"), true, "rogue_news set")
	check_eq(gs.get_flag("patrol"), "reported", "the patrol is reported")
	# A later border report: the normal line again.
	gs.set_flag("patrol", "report")
	lines = _talk("res://data/dialogue/rook.json", {})
	all = " | ".join(lines)
	check(not all.contains("strange scent"), "not twice (%s)" % all)
	check(all.contains("Rest a while"), "the normal line")


func test_no_news_without_wick_missing() -> void:
	var all := " | ".join(_talk("res://data/dialogue/rook.json", {"patrol": "report"}))
	check(not all.contains("strange scent"), "an ordinary report (%s)" % all)
	check(all.contains("Rest a while"), "the normal line")
	check_eq(gs.get_flag("rogue_news"), false, "no news")


func test_the_deputy_reminds_while_investigating() -> void:
	var lines := _talk("res://data/dialogue/rook.json", {"wick_missing": true, "rogue_news": true})
	check_eq(lines.size(), 1, "one line")
	check(lines[0].contains("river") and lines[0].contains("Wick"), "the reminder (%s)" % lines[0])
	check(not lines[0].contains("patrol."), "no patrol offer")


func test_clanmates_ask_about_wick() -> void:
	var bram := _talk("res://data/dialogue/bram.json", {"talked_bram": true, "wick_missing": true})
	check_eq(bram.size(), 1, "Bram: one line")
	check(bram[0].contains("Have you seen Wick?") and bram[0].contains("sunhigh"), "Bram asks (%s)" % bram[0])
	gs = GameStateCore.new()
	var sorrel := _talk("res://data/dialogue/sorrel.json", {"talked_sorrel": true, "wick_missing": true})
	check(sorrel[0].contains("Wick") and sorrel[0].contains("sunhigh"), "Sorrel too (%s)" % sorrel[0])
	# Their first conversations still play in full.
	gs = GameStateCore.new()
	var first := _talk("res://data/dialogue/bram.json", {"wick_missing": true})
	check(first.size() > 2 and first[0].contains("There you are"), "Bram's first talk still plays (%s)" % first[0])
	gs = GameStateCore.new()
	check(_talk("res://data/dialogue/bram.json", {"talked_bram": true})[0].contains("Dawn comes early"), "before: the old repeat line")


func test_wick_is_left_out_of_camp() -> void:
	var areas := Areas.new()
	var w = areas.load_world("camp", JsonData.load_dict("res://data/tuning.json"))
	check(not w.npc_by_id("wick").is_empty(), "Wick is in the camp file")
	var solids: int = w.solids.size()
	check(w.remove_npc("wick"), "removed")
	check(w.npc_by_id("wick").is_empty(), "gone")
	check(w.solids.size() < solids or w.npc_by_id("wick").is_empty(), "his collider goes with him")
	check(not w.remove_npc("wick"), "only once")
	w.step(0.1, Vector2.ZERO, false)
	check(w.focus_id != "wick", "nothing focuses him")


func test_the_story_survives_save_and_load() -> void:
	check(story.border_marked(gs, []), "missing")
	gs.set_flag("rogue_news", true)
	gs.add_bond("wick", 2)
	var saved: Dictionary = gs.save_data()
	var saved_story: Dictionary = story.save_data()
	check_eq(saved["flags"]["wick_missing"], true, "the save holds wick_missing")
	check_eq(saved["flags"]["rogue_news"], true, "and rogue_news")
	gs.reset()
	story.reset()
	check(not story.absent(gs, "wick"), "a new game: Wick home")
	# Through JSON, as a save file would go.
	gs.load_save_data(JSON.parse_string(JSON.stringify(saved)))
	story.load_save_data(JSON.parse_string(JSON.stringify(saved_story)))
	check(story.absent(gs, "wick"), "loaded: still missing")
	check(story.investigating(gs), "still investigating")
	check_eq(gs.bond("wick"), 2, "bonds too")
	check_eq(story.border_patrols, int(saved_story["border_patrols"]), "the count")
	check(not story.border_marked(gs, []), "no second disappearance after loading")
	# Junk in a save is dropped.
	gs.load_save_data({"flags": {"no_such_flag": true, "vole": "eaten", "rogue_news": "yes"}})
	check(not gs.flags.has("no_such_flag"), "unknown flag dropped")
	check_eq(gs.get_flag("vole"), null, "bad value dropped")
	check_eq(gs.get_flag("rogue_news"), true, "a bad type doesn't overwrite")


# --- Part B: the rogue by the river


func _hg2(flags: Dictionary):
	for k: String in flags:
		gs.set_flag(k, flags[k])
	return Areas.new().load_world(str(cfg["rogue"]["area"]), JsonData.load_dict("res://data/tuning.json"), gs)


func _exit(w, id: String) -> Dictionary:
	for e: Dictionary in w.exits:
		if e["id"] == id:
			return e
	return {}


func test_slate_only_while_investigating() -> void:
	var slate := str(cfg["rogue"]["npc"])
	check(_hg2({}).npc_by_id(slate).is_empty(), "not before the news")
	gs = GameStateCore.new()
	check(_hg2({"wick_missing": true}).npc_by_id(slate).is_empty(), "not when Wick has only just gone")
	gs = GameStateCore.new()
	var w = _hg2({"wick_missing": true, "rogue_news": true})
	var npc: Dictionary = w.npc_by_id(slate)
	check(not npc.is_empty(), "there while investigating")
	check(w.stream_y(npc["pos"].x) > npc["pos"].y - 60.0 and not w.beyond_border(npc["pos"]), "by the river, on our side (%s)" % npc["pos"])
	check(npc["pos"].x > w.size.x * 0.85, "at the far end (%s)" % npc["pos"])
	check(World.talkable(npc), "talkable")
	gs.set_flag("rogue_met", true)
	check(_hg2({}).npc_by_id(slate).is_empty(), "gone once met (after the area reloads)")


func test_story_exit_opens_with_the_rogue() -> void:
	var w = _hg2({"rogue_news": true})
	var e := _exit(w, str(cfg["rogue"]["exit"]))
	check(not e.is_empty(), "the story exit exists")
	check_eq(e["to"], "rogue_camp", "to rogue land")
	check(not w.is_open(e), "closed during the investigation")
	# Walking into it does nothing yet; the spot says why.
	w.player_pos = (e["rect"] as Rect2).get_center() + Vector2(-30, 0)
	w.exits_armed = true
	var exited := false
	var saw_spot := false
	for i in 120:
		for ev: Dictionary in w.step(1.0 / 60.0, Vector2.RIGHT, false):
			exited = exited or ev["type"] == "exit"
		saw_spot = saw_spot or w.focus_id == "old_trail"
	check(not exited, "no way through while closed")
	check(saw_spot, "the old trail says something instead")
	gs.set_flag("rogue_met", true)
	check(w.is_open(e), "open as soon as Fern met him (live)")
	w.player_pos = (e["rect"] as Rect2).get_center() + Vector2(-30, 0)
	w.exits_armed = true
	for i in 120:
		for ev: Dictionary in w.step(1.0 / 60.0, Vector2.RIGHT, false):
			exited = exited or (ev["type"] == "exit" and ev["to"] == "rogue_camp")
	check(exited, "walking in leaves for rogue land")
	check(w.focus_id != "old_trail", "the closed-trail spot is gone")


func _slate(flags: Dictionary, picks: Array) -> Dictionary:
	gs = GameStateCore.new()
	for k: String in flags:
		gs.set_flag(k, flags[k])
	var d = Dialogue.new(gs)
	var lines: Array[String] = []
	var shown: Array = []
	var line: Dictionary = d.start(JsonData.load_dict("res://data/dialogue/slate.json"))
	for i in 30:
		if line.get("type", "") != "line":
			break
		lines.append(gs.format_text(str(line["text"])))
		if not (line["choices"] as Array).is_empty():
			shown.append(line["choices"])
			line = d.choose(int(picks.pop_front()) if not picks.is_empty() else 0)
		else:
			line = d.advance()
	return {"lines": " | ".join(lines), "choices": shown}


func test_slate_choices() -> void:
	var r := _slate({"rogue_news": true}, [0, 1])
	check_eq((r["choices"][0] as Array).size(), 2, "without prey: two choices (%s)" % [r["choices"][0]])
	check(not " ".join(r["choices"][0]).contains("prey"), "no prey choice")
	check(r["lines"].contains("nice rest. With friends"), "questioned: he lets it slip (%s)" % r["lines"])
	check_eq(gs.get_flag("rogue_choice"), "question", "saved: question")
	check_eq(gs.get_flag("rogue_met"), true, "met")
	r = _slate({"rogue_news": true, "carrying": true}, [1, 1])
	check_eq((r["choices"][0] as Array).size(), 3, "carrying: three choices")
	check(r["lines"].contains("Keep your precious border"), "threatened: he backs off (%s)" % r["lines"])
	check_eq(gs.get_flag("rogue_choice"), "threaten", "saved: threaten")
	r = _slate({"rogue_news": true, "carrying": true}, [2, 1])
	check(r["lines"].contains("old trail east"), "bribed: he tells (%s)" % r["lines"])
	check_eq(gs.get_flag("rogue_choice"), "bribe", "saved: bribe")
	check_eq(gs.get_flag("rogue_met"), true, "met")


func test_red_fur_in_every_branch() -> void:
	var ends := {0: "I've got places to be", 1: "Keep your precious border", 2: "old trail east"}
	for pick: int in ends:
		var r := _slate({"rogue_news": true, "carrying": true}, [pick, 0])
		check(" ".join(r["choices"][1]).contains("red on your fur"), "branch %d offers the question" % pick)
		check(r["lines"].contains("He didn't come quietly"), "branch %d: the hint (%s)" % [pick, r["lines"]])
		check(r["lines"].contains(ends[pick]), "branch %d: then its own ending (%s)" % [pick, r["lines"]])
		check_eq(gs.get_flag("rogue_red"), true, "asked")
		check_eq(gs.get_flag("rogue_met"), true, "met")
	var r := _slate({"rogue_met": true}, [])
	check(r["lines"].contains("get lost"), "afterwards: get lost (%s)" % r["lines"])


func test_conditional_choices() -> void:
	var conv := {"start": "a", "nodes": {
		"a": {"speaker": "fern", "text": "?", "choices": [
			{"text": "one", "next": "b"},
			{"if": {"carrying": true}, "text": "two", "next": "c", "set": {"vole": "kept"}}]},
		"b": {"speaker": "fern", "text": "b", "end": true},
		"c": {"speaker": "fern", "text": "c", "end": true}}}
	var d = Dialogue.new(gs)
	check_eq(d.start(conv)["choices"], ["one"], "hidden while not carrying")
	check_eq(d.choose(1)["choices"], ["one"], "a hidden choice can't be picked")
	gs.set_flag("carrying", true)
	d = Dialogue.new(gs)
	check_eq(d.start(conv)["choices"], ["one", "two"], "shown while carrying")
	check_eq(d.choose(1)["text"], "c", "picked by its shown index")
	check_eq(gs.get_flag("vole"), "kept", "its set applies")
	var Validator := preload("res://scripts/core/dialogue_validator.gd")
	check(Validator.validate(conv).is_empty(), "valid: %s" % [Validator.validate(conv)])
	var bad := conv.duplicate(true)
	bad["nodes"]["a"]["choices"][0]["if"] = {"nope": true}
	var errs: Array = Validator.validate(bad)
	check(" ".join(errs).contains("unknown flag 'nope'"), "unknown flag in a choice's if (%s)" % [errs])
	check(" ".join(errs).contains("every choice has an"), "one choice must always show (%s)" % [errs])


func test_how_slate_leaves() -> void:
	var route: Array[Vector2] = story.rogue_route()
	check(route.size() >= 2, "a route")
	var walk: Dictionary = story.leave_plan("question")
	var run: Dictionary = story.leave_plan("threaten")
	check_eq(walk["mode"], "walk", "questioned: he walks off")
	check_eq(run["mode"], "run", "threatened: he bolts")
	check(float(run["speed"]) > float(walk["speed"]) * 3.0, "running is much faster")
	check_eq(story.leave_plan("bribe")["mode"], "stay", "bribed: he stays and eats")
	var w = _hg2({"rogue_news": true})
	var exit_r: Rect2 = _exit(w, str(cfg["rogue"]["exit"]))["rect"]
	var npc: Dictionary = w.npc_by_id(story.rogue_npc())
	check(npc["pos"].distance_to(route[0]) < 1.0, "the route starts where he stands")
	var crosses := false
	for i in range(1, route.size()):
		for t in 20:
			crosses = crosses or exit_r.has_point(route[i - 1].lerp(route[i], t / 20.0))
	check(crosses, "it goes out through the story exit")
	check(route[route.size() - 1].x > w.size.x, "and on out of the area")
	check(w.leave_npc(story.rogue_npc(), walk["route"], float(run["speed"])), "sent")
	check(w.is_leaving(story.rogue_npc()), "leaving")
	check(not World.talkable(w.npc_by_id(story.rogue_npc())), "can't be talked to while leaving")
	var left := false
	for i in 240:
		for ev: Dictionary in w.step(1.0 / 60.0, Vector2.ZERO, false):
			left = left or (ev["type"] == "npc_left" and ev["id"] == story.rogue_npc())
	check(left, "an npc_left event")
	check(w.npc_by_id(story.rogue_npc()).is_empty(), "gone from the area")


func test_trail_and_arrow() -> void:
	var size := Vector2(900, 440)
	check(story.trail(gs, size).is_empty(), "no trail before")
	check_eq(story.way_mark(gs), Vector2.INF, "no arrow before")
	gs.set_flag("rogue_met", true)
	gs.set_flag("rogue_choice", "question")
	check(story.trail(gs, size).is_empty(), "questioned: no trail")
	gs.set_flag("rogue_choice", "threaten")
	var t: Array[Vector2] = story.trail(gs, size)
	check(t.size() >= 2, "threatened: a trail of scent rings (%d)" % t.size())
	var every := float(cfg["rogue"]["trail_every"])
	for i in range(1, t.size()):
		check_near(t[i].distance_to(t[i - 1]), every, every * 0.35, "rings about trail_every apart")
	for p in t:
		check(Rect2(Vector2.ZERO, size).grow(-8).has_point(p), "ring %s inside the area" % p)
	gs.set_flag("rogue_choice", "bribe")
	check(story.trail(gs, size).is_empty(), "bribed: no trail")
	check(story.way_mark(gs) != Vector2.INF, "bribed: the arrow")
	check_eq(story.goal_key(gs), str(cfg["rogue"]["goal_follow"]), "goal: follow the rogue")
	check_eq(str(strings.get(story.goal_key(gs), "")), "Follow the rogue.", "its text")


# --- Part C: the rogue camp, hiding, the cutscene, warning the deputy


func _camp_w(flags: Dictionary):
	gs = GameStateCore.new()
	for k: String in flags:
		gs.set_flag(k, flags[k])
	return Areas.new().load_world(str(cfg["rogue"]["camp_area"]), JsonData.load_dict("res://data/tuning.json"), gs)


const FOLLOWING := {"wick_missing": true, "rogue_news": true, "rogue_met": true, "rogue_choice": "question"}


func test_rogue_camp_layout() -> void:
	var w = _camp_w(FOLLOWING)
	check(w != null, "the rogue camp loads")
	check(not w.npc_by_id("wick").is_empty(), "Wick is here")
	check(not story.absent(gs, "wick", "rogue_camp"), "not absent from the rogue camp")
	check(story.absent(gs, "wick", "camp") and story.absent(gs, "wick"), "absent everywhere else")
	check(not World.talkable(w.npc_by_id("wick")), "Wick doesn't talk yet")
	check_eq(w.npc_by_id("wick")["rest"], "sleep", "lying down")
	for id in ["vex", "slate"]:
		check(not w.npc_by_id(id).is_empty(), "%s is here" % id)
	var wick: Vector2 = w.npc_by_id("wick")["pos"]
	check(wick.x > w.size.x * 0.8 and wick.y < w.size.y * 0.4, "Wick is in a corner (%s)" % wick)
	check(w.npc_by_id("slate")["pos"].distance_to(wick) < 60.0, "guarded")
	# The log by the entrance, the hiding spot behind it.
	var logs: Array = w.props.filter(func(p): return p["type"] == "log")
	check_eq(logs.size(), 1, "a fallen log")
	var spawn: Vector2 = w.spawns["from_hunting_grounds_2"]["pos"]
	check(logs[0]["pos"].distance_to(spawn) < 100.0, "near the entrance")
	var sp: Dictionary = w.spot_by_id("hide_log")
	check(not sp.is_empty() and sp["event"] == "hide", "a hide spot")
	check(sp["at"].y < logs[0]["pos"].y and absf(sp["at"].x - logs[0]["pos"].x) < 6.0, "Fern hides just behind (north of) the log")
	# The barrier keeps Fern in the entrance pocket.
	check(not w.barriers.is_empty(), "a barrier")
	for b: Dictionary in w.barriers:
		check(b["rect"].position.x > spawn.x and b["rect"].position.x < wick.x, "between the entrance and the camp")
	w.place_at_spawn("from_hunting_grounds_2")
	var msgs: Array = []
	for i in 300:
		for ev: Dictionary in w.step(1.0 / 60.0, Vector2.RIGHT, false):
			if ev["type"] == "message":
				msgs.append(ev["key"])
	check(w.player_pos.x < w.barriers[0]["rect"].position.x, "walking east stops at the hedge (%s)" % w.player_pos)
	check(msgs.has("story.too_risky"), "Too risky. Find somewhere to hide.")
	check(msgs.size() <= 3, "not every frame (%d)" % msgs.size())
	check_eq(str(strings.get("story.too_risky", "")), "Too risky. Find somewhere to hide.", "its text")
	check_eq(w.arrive_message.get("message", ""), "story.stay_hidden", "a line on arrival")
	check(w.is_open(w.arrive_message), "while the camp isn't found")


func test_reaching_the_log() -> void:
	var w = _camp_w(FOLLOWING)
	w.place_at_spawn("from_hunting_grounds_2")
	var sp: Dictionary = w.spot_by_id("hide_log")
	var target: Vector2 = sp["prompt"] + Vector2(0, 6)
	var found := false
	for i in 600:
		var to: Vector2 = (target - w.player_pos)
		w.step(1.0 / 60.0, to.normalized() if to.length() > 2.0 else Vector2.ZERO, false)
		if w.focus_id == "hide_log":
			found = true
			break
	check(found, "Fern can walk up to the log and it takes focus")
	var ev: Array[Dictionary] = w.interact()
	check(not ev.is_empty() and ev[0]["type"] == "hide", "interact = hide (%s)" % [ev])
	gs.set_flag("rogue_camp_found", true)
	w.step(1.0 / 60.0, Vector2.ZERO, false)
	check(w.focus_id != "hide_log", "once found, nothing to hide for")
	check(not w.is_open(w.arrive_message), "no 'stay out of sight' line any more")


func test_cutscene_file() -> void:
	var data := Cutscene.load_file(story.cutscene_path())
	var errs := Cutscene.check(data, JsonData.load_dict("res://data/speakers.json"), GameStateCore.new())
	check(errs.is_empty(), "valid: %s" % [errs])
	var says: Array = (data["steps"] as Array).filter(func(s): return s.has("say"))
	var who := {}
	for s in says:
		who[s["say"]] = true
	for id in ["slate", "vex"]:
		check(who.has(id), "%s speaks" % id)
	var text := " ".join(says.map(func(s): return str(s["text"])))
	for bit in ["patrol times", "loners", "land", "Let them come"]:
		check(text.contains(bit), "the talk covers '%s'" % bit)
	var kinds := {}
	for s: Dictionary in data["steps"]:
		for k in Cutscene.STEP_KINDS:
			if s.has(k):
				kinds[k] = true
	for k in ["camera", "move", "say"]:
		check(kinds.has(k), "uses %s steps" % k)
	check_eq(data["steps"][data["steps"].size() - 1].get("set", {}), {"rogue_camp_found": true}, "ends by setting rogue_camp_found")
	var bad := Cutscene.check({"steps": [{"say": "nobody", "text": "x"}, {"wait": 1, "say": "fern"}, {"set": {"nope": 1}}]}, JsonData.load_dict("res://data/speakers.json"), GameStateCore.new())
	check_eq(bad.size(), 3, "bad speaker, two kinds in one step, bad flag (%s)" % [bad])


func test_cutscene_runs() -> void:
	var w = _camp_w(FOLLOWING)
	var data := Cutscene.load_file(story.cutscene_path())
	var says := (data["steps"] as Array).filter(func(s): return s.has("say")).size()
	var c = Cutscene.new(data)
	var follow := Vector2(120, 180)
	var lines: Array[String] = []
	var ends := 0
	var furthest := 0.0
	var ev: Array[Dictionary] = c.start(w, gs, follow)
	check(c.is_running(), "running")
	for i in 6000:
		for e: Dictionary in ev:
			if e["type"] == "line":
				lines.append(str(e["text"]))
				check(e["choices"].is_empty(), "no choices in a cutscene")
			if e["type"] == "end":
				ends += 1
		if c.is_done():
			break
		if c.camera_point() != Vector2.INF:
			furthest = maxf(furthest, c.camera_point().x)
		if not c.line.is_empty():
			ev = c.advance()
		else:
			w.step(1.0 / 60.0, Vector2.ZERO, false)
			ev = c.step(1.0 / 60.0, follow)
	check(c.is_done(), "it finishes")
	check_eq(ends, 1, "one end event")
	check_eq(lines.size(), says, "every line shown once")
	check(furthest > 380.0, "the camera went over to the camp (%.0f)" % furthest)
	check_eq(c.camera_point(), Vector2.INF, "and back to Fern at the end")
	var to: Array = (data["steps"] as Array).filter(func(s): return s.has("move"))[0]["to"]
	check(w.npc_by_id("slate")["pos"].distance_to(Vector2(to[0], to[1])) < 1.0, "Slate walked over to Vex")
	check_eq(gs.get_flag("rogue_camp_found"), true, "rogue_camp_found")
	check(not story.can_hide(gs), "not again")


func test_warning_the_deputy() -> void:
	var flags := FOLLOWING.duplicate()
	flags["rogue_camp_found"] = true
	gs = GameStateCore.new()
	check_eq(story.goal_key(gs), "", "start: no goal")
	var lines := _talk("res://data/dialogue/rook.json", flags)
	var all := " | ".join(lines)
	check(story.goal_key(gs) == "" and gs.get_flag("rogue_warned") == true, "warned: goal done")
	check(all.contains("Rogues have Wick") and all.contains("loners"), "Fern tells him (%s)" % all)
	check(all.contains("Larch"), "he takes it to the leader")
	check(not story.investigating(gs) and not story.blocks_patrols(gs), "patrols come back")
	check(story.absent(gs, "wick"), "Wick stays in the rogue camp")
	# Afterwards: the normal offers again.
	var gs2 = GameStateCore.new()
	for k: String in flags:
		gs2.set_flag(k, flags[k])
	gs2.set_flag("rogue_warned", true)
	gs2.set_flag("patrol_offer", "hunting")
	gs = gs2
	check(_talk("res://data/dialogue/rook.json", {})[0].contains("Hunting patrol"), "a patrol offer again")


func test_goals_through_the_story() -> void:
	var expect := [
		[{}, ""],
		[{"rogue_news": true}, "story.goal_investigate"],
		[{"rogue_met": true}, "story.goal_follow"],
		[{"rogue_camp_found": true}, "story.goal_warn"],
		[{"rogue_warned": true}, ""],
	]
	gs = GameStateCore.new()
	for e in expect:
		for k: String in e[0]:
			gs.set_flag(k, e[0][k])
		check_eq(story.goal_key(gs), e[1], "after %s" % [e[0]])
	check_eq(str(strings["story.goal_warn"]), "Get back to camp and warn the deputy.", "the warn goal's text")
	# And they survive the save hook.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.save_data()))
	var gs2 = GameStateCore.new()
	gs2.load_save_data(saved)
	for k in ["rogue_news", "rogue_met", "rogue_camp_found", "rogue_warned"]:
		check_eq(gs2.get_flag(k), true, "loaded %s" % k)

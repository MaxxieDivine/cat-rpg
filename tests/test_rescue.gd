extends "res://tests/test_base.gd"
## Rescuing Wick, Part A (core, headless): the scene select presets, the
## deputy's stalling talk and Bram's line, resting at night, the night tint
## flag in every area, the rogue camp's log at night (watch, then sneak),
## the coin flip and both fate cutscenes run headless, the prisoner den
## (bigger than the apprentices' den, ivy over the doorway, captives), the
## sleeping apprentices, the camp entrance closed until night, and the
## rescue flags through the save hook. Expected values from data/.

const Story := preload("res://scripts/core/story.gd")
const Areas := preload("res://scripts/core/areas.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")
const Cutscene := preload("res://scripts/core/cutscene.gd")
const ScenePresets := preload("res://scripts/core/scene_presets.gd")
const Travel := preload("res://scripts/core/travel.gd")

var cfg: Dictionary
var rs: Dictionary
var tuning: Dictionary
var strings: Dictionary
var story
var gs

const AFTER_CAMP := {"wick_missing": true, "rogue_news": true, "rogue_met": true, "rogue_choice": "question", "rogue_camp_found": true}


func before_each() -> void:
	cfg = JsonData.load_dict("res://data/story.json")
	rs = cfg["rescue"]
	tuning = JsonData.load_dict("res://data/tuning.json")
	strings = JsonData.load_dict("res://data/strings.json")
	story = Story.new()
	gs = GameStateCore.new()


func _setf(flags: Dictionary) -> void:
	for k: String in flags:
		gs.set_flag(k, flags[k])


func _world(area: String):
	return Areas.new().load_world(area, tuning, gs)


func _talk(file: String) -> Array[String]:
	var d = Dialogue.new(gs)
	var lines: Array[String] = []
	var line: Dictionary = d.start(JsonData.load_dict(file))
	for i in 20:
		if line.get("type", "") != "line":
			break
		lines.append(gs.format_text(str(line["text"])))
		line = d.choose(0) if not (line.get("choices", []) as Array).is_empty() else d.advance()
	return lines


# --- Scene select


func test_presets_are_valid() -> void:
	var sp = ScenePresets.new()
	var areas = Areas.new()
	var errs: Array[String] = sp.check(areas.ids(), gs)
	check(errs.is_empty(), "presets check out: %s" % [errs])
	for id in ["camp_day", "after_rogue_camp", "rest", "night_log", "prisoner_den"]:
		check(sp.ids().has(id), "preset %s" % id)
	for id in sp.ids():
		var p: Dictionary = sp.resolved(id)
		var w = Areas.new().load_world(str(p["area"]), tuning, GameStateCore.new())
		if not check(w != null, "%s: its area loads" % id):
			continue
		if p.has("spawn"):
			check(w.spawns.has(str(p["spawn"])) or (p["area"] == "prisoner_den" or p["area"] == "apprentices_den"), "%s: spawn %s" % [id, p["spawn"]])
		else:
			var pos := Vector2(p["pos"][0], p["pos"][1])
			check(w.bounds.has_point(pos), "%s: pos inside the area" % id)


func test_presets_inherit_their_base() -> void:
	var sp = ScenePresets.new()
	var p: Dictionary = sp.resolved("night_log")
	check_eq(p["flags"].get("rogue_camp_found"), true, "from after_rogue_camp")
	check_eq(p["flags"].get("told_rook"), true, "from rest")
	check_eq(p["flags"].get("night"), true, "its own")
	check_eq(p["area"], "rogue_camp", "its own area")
	check(sp.resolved("nope").is_empty(), "unknown preset")
	# A new story point is one line of data.
	var extra = ScenePresets.new({"presets": [{"id": "a", "label": "A", "flags": {"night": true}, "area": "camp", "spawn": "start"},
		{"id": "b", "label": "B", "base": "a", "flags": {"told_rook": true}, "area": "camp", "spawn": "start"}]})
	check_eq(extra.resolved("b")["flags"], {"night": true, "told_rook": true}, "base flags merge")
	var bad = ScenePresets.new({"presets": [{"id": "x", "label": "X", "flags": {"no_such_flag": true}, "area": "moon"}]})
	check_eq(bad.check(Areas.new().ids(), gs).size(), 3, "bad flag, area and no spawn are reported")


func test_preset_state_matches_the_story_point() -> void:
	var sp = ScenePresets.new()
	var expect := {"camp_day": "", "after_rogue_camp": "story.goal_warn", "rest": "story.goal_rest", "night_log": "story.goal_rescue", "prisoner_den": ""}
	for id: String in expect:
		gs = GameStateCore.new()
		ScenePresets.apply_flags(sp.resolved(id), gs)
		check_eq(story.goal_key(gs), expect[id], "%s: goal" % id)
	gs = GameStateCore.new()
	ScenePresets.apply_flags(sp.resolved("rest"), gs)
	check(story.can_rest(gs), "rest: ready to sleep")
	gs = GameStateCore.new()
	ScenePresets.apply_flags(sp.resolved("night_log"), gs)
	check(story.sneaking(gs) and gs.get_flag("log_watched") == true, "night_log: out at night, behind the log")
	var w = _world("rogue_camp")
	w.player_pos = Vector2(sp.resolved("night_log")["pos"][0], sp.resolved("night_log")["pos"][1])
	w._update_focus()
	check_eq(w.focus_id, "sneak_log", "night_log: the log offers sneaking")


# --- A2: Rook stalls


func test_rook_stalls_and_bram_backs_it_up() -> void:
	_setf(AFTER_CAMP)
	var lines := _talk("res://data/dialogue/rook.json")
	var all := " | ".join(lines)
	check(all.contains("I found where they're keeping Wick. A rogue camp, just past the river."), "Fern's line (%s)" % all)
	check(all.contains("You went past the border? Alone?"), "Rook")
	check(all.contains("I'll speak to Larch. This isn't something an apprentice settles."), "stalling")
	check(all.contains("Go rest. And stay in camp."), "go rest")
	check_eq(gs.get_flag("told_rook"), true, "told_rook")
	check_eq(story.goal_key(gs), str(rs["goal_rest"]), "goal: rest")
	check_eq(str(strings[rs["goal_rest"]]), "Rest in the apprentices' den.", "goal text")
	lines = _talk("res://data/dialogue/rook.json")
	check(lines.size() == 1 and lines[0].contains("I said rest"), "then he only says to rest (%s)" % [lines])
	gs.set_flag("talked_bram", true)
	lines = _talk("res://data/dialogue/bram.json")
	check(lines.size() == 2 and lines[0].contains("were arguing") and lines[1].contains("comes back on his own"), "Bram heard them argue (%s)" % [lines])


func test_the_camp_entrance_waits_for_night() -> void:
	_setf(AFTER_CAMP)
	gs.set_flag("told_rook", true)
	var w = _world("camp")
	var exit_r: Rect2 = w.exits.filter(func(e): return e["id"] == "to_hunting_grounds")[0]["rect"]
	w.place_at_spawn("from_hunting")
	w.player_pos = Vector2(exit_r.position.x - 30, exit_r.get_center().y)
	var said := false
	var left := false
	for i in 120:
		for ev: Dictionary in w.step(1.0 / 30.0, Vector2.RIGHT, false):
			said = said or (ev["type"] == "message" and ev["key"] == "story.stay_in_camp")
			left = left or ev["type"] == "exit"
	check(said and not left, "told to stay in camp, and kept there")
	gs.set_flag("night", true)
	w = _world("camp")
	w.player_pos = Vector2(exit_r.position.x - 30, exit_r.get_center().y)
	for i in 120:
		for ev: Dictionary in w.step(1.0 / 30.0, Vector2.RIGHT, false):
			left = left or ev["type"] == "exit"
	check(left, "at night she slips out")
	check(w.npc_by_id("rook").is_empty(), "Rook isn't watching the entrance at night")
	var w0 = Areas.new().load_world("camp", tuning)
	check(w0.barriers.all(func(b): return not w0.barrier_up(b)), "no barrier without conditions (tools, tests)")


# --- A3: rest and wake at night


func test_resting_wakes_at_night() -> void:
	_setf(AFTER_CAMP)
	check(not story.can_rest(gs), "not before telling the deputy")
	gs.set_flag("told_rook", true)
	check(story.can_rest(gs) and not story.sneaking(gs), "now she can rest")
	story.rest(gs)
	check(story.is_night(gs) and story.sneaking(gs), "night: out to rescue Wick")
	check(not story.can_rest(gs), "no second night")
	check_eq(story.goal_key(gs), str(rs["goal_rescue"]), "goal: rescue")
	check_eq(gs.format_text(str(strings[rs["goal_rescue"]])), "Sneak out and rescue Wick.", "goal text")
	check(story.blocks_patrols(gs), "no patrols")
	for area in ["camp", "hunting_grounds", "hunting_grounds_2", "rogue_camp", "apprentices_den"]:
		var w = _world(area)
		check(w != null, "%s loads at night" % area)
	var den = _world(str(rs["rest_area"]))
	for id in ["sleeper_a", "sleeper_b"]:
		var npc: Dictionary = den.npc_by_id(id)
		if not check(not npc.is_empty(), "%s asleep in the den at night" % id):
			continue
		var in_nest: bool = den.interior["nests"].any(func(n): return (n["pos"] as Vector2).distance_to(npc["pos"]) < 0.5 and not n["mine"])
		check(in_nest, "%s lies in a nest that isn't Fern's" % id)
		check(not den.talkable(npc), "%s isn't woken by talking" % id)
	gs.set_flag("night", false)
	check(_world(str(rs["rest_area"])).npc_by_id("sleeper_a").is_empty(), "not there by day")


func test_travel_scene() -> void:
	var t = Travel.new(tuning)
	check(t.scene("apprentices_den", "nest", "Hello"), "starts")
	check(not t.scene("camp", "start", "x") and not t.collapse("camp", "start"), "one at a time")
	check_eq(t.phase, "lie", "lies down first")
	var kinds: Array[String] = []
	for i in 600:
		for ev: Dictionary in t.step(1.0 / 30.0):
			kinds.append(ev["type"])
			if ev["type"] == "load":
				check(not ev["collapsed"] and ev["kind"] == "scene", "a scene, not passing out")
		if t.phase == "message":
			check(t.has_message() and t.message == "Hello", "its own line on black")
			t.confirm()
		if not t.busy():
			break
	check(not t.busy(), "finishes")
	check(kinds.has("load") and kinds.has("wake") and kinds.has("done"), "load, wake, done (%s)" % [kinds])
	t = Travel.new(tuning)
	t.scene("camp", "start", "", false, false)
	check_eq(t.phase, "out", "no lying down")
	kinds.clear()
	for i in 600:
		for ev: Dictionary in t.step(1.0 / 30.0):
			kinds.append(ev["type"])
		check(t.phase != "message" and t.phase != "wake", "no line, no stretch")
		if not t.busy():
			break
	check(kinds.has("load") and not kinds.has("wake"), "loads without waking (%s)" % [kinds])


# --- A4 / A5: the log at night, the coin flip


func _night_camp():
	_setf(AFTER_CAMP)
	gs.set_flag("rogue_warned", true)
	gs.set_flag("told_rook", true)
	gs.set_flag("night", true)
	return _world(story.camp_area())


func test_the_log_at_night() -> void:
	var w = _night_camp()
	check(not w.arrival().is_empty() and w.arrival()["message"] == "story.stay_hidden", "Stay out of sight... at night")
	for id in ["wick", "slate", "vex"]:
		check(not w.npc_by_id(id).is_empty(), "%s is there" % id)
	var hide: Dictionary = w.spot_by_id("hide_log_night")
	check(w.is_open(hide) and hide["event"] == "hide", "the log hides her again")
	check(not w.is_open(w.spot_by_id("sneak_log")), "no sneaking before looking")
	check(not w.is_open(w.spot_by_id("hide_log")), "not the daytime hiding")
	w.player_pos = hide["prompt"] + Vector2(0, 6)
	w._update_focus()
	check_eq(w.focus_id, "hide_log_night", "the log has focus")
	var ev: Array[Dictionary] = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "hide", "hide event")
	var lines := _run_cutscene(w, story.night_cutscene("watch"))
	check(" ".join(lines).contains("There's Wick") and " ".join(lines).contains("Slate"), "she sees Wick and Slate (%s)" % [lines])
	check_eq(gs.get_flag("log_watched"), true, "log_watched")
	w._update_focus()
	check_eq(w.focus_id, "sneak_log", "now the log offers sneaking")
	check_eq(w.spot_by_id("sneak_log")["label"], str(rs["sneak_label"]), "labelled")
	ev = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "sneak", "sneak event")


## Runs cutscene `path` headless in `w`; returns its lines.
func _run_cutscene(w, path: String) -> Array[String]:
	var data := Cutscene.load_file(path)
	check(Cutscene.check(data, JsonData.load_dict("res://data/speakers.json"), gs).is_empty(), "%s checks out: %s" % [path, Cutscene.check(data, JsonData.load_dict("res://data/speakers.json"), gs)])
	var c = Cutscene.new(data)
	var lines: Array[String] = []
	var ev: Array[Dictionary] = c.start(w, gs, w.player_pos)
	for i in 20000:
		for e: Dictionary in ev:
			if e["type"] == "line":
				lines.append(gs.format_text(str(e["text"])))
		if c.is_done():
			break
		if not c.line.is_empty():
			ev = c.advance()
		else:
			w.step(1.0 / 60.0, Vector2.ZERO, false)
			ev = c.step(1.0 / 60.0, w.player_pos)
	check(c.is_done(), "%s finishes" % path)
	return lines


func test_coin_flip() -> void:
	check_eq(story.lucky_chance, float(rs["lucky_chance"]), "odds from story.json")
	var counts := {"lucky": 0, "caught": 0}
	for i in 400:
		counts[story.fate()] += 1
	check(counts["lucky"] > 120 and counts["caught"] > 120, "both outcomes at 50/50 (%s)" % [counts])
	var a = Story.new()
	var b = Story.new()
	var seq_a := []
	var seq_b := []
	for i in 20:
		seq_a.append(a.fate())
		seq_b.append(b.fate())
	check_eq(seq_a, seq_b, "seeded: the same flips every new game")
	story.lucky_chance = 1.0
	check(range(20).all(func(_i): return story.fate() == "lucky"), "odds 1: always lucky")
	story.lucky_chance = 0.0
	check(range(20).all(func(_i): return story.fate() == "caught"), "odds 0: always caught")
	# The flips carry on after a save and load.
	var c = Story.new()
	c.fate()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(c.save_data()))
	var next := c.fate()
	var d = Story.new()
	d.load_save_data(saved)
	check_eq(d.fate(), next, "the RNG survives the save hook")


func test_lucky_cutscene() -> void:
	var w = _night_camp()
	gs.set_flag("log_watched", true)
	var path: String = story.night_cutscene("lucky")
	var lines := _run_cutscene(w, path)
	check(" ".join(lines).contains("Wake up") and " ".join(lines).contains("You came for me"), "she wakes Wick (%s)" % [lines])
	check(w.player_pos.distance_to(w.npc_by_id("wick")["pos"]) < 50.0, "Fern got over to him")
	check_eq(w.npc_by_id("wick")["rest"], "idle", "Wick got up")
	check_eq(gs.get_flag("rescue"), "rescued", "rescued")
	check(not story.absent(gs, "wick") and not story.is_night(gs), "Wick home, morning")
	check(not story.blocks_patrols(gs) and story.goal_key(gs) == "", "mission done: patrols again, no goal")
	var then: Dictionary = Cutscene.load_file(path)["then"]
	check(Areas.new().has(str(then["area"])) and strings.has(str(then["message"])), "then: home with a line")
	check(not _world("camp").npc_by_id("wick").is_empty(), "Wick is back in camp")
	check(_world(story.camp_area()).npc_by_id("wick").is_empty(), "and gone from the rogue camp")


func test_caught_cutscene() -> void:
	var w = _night_camp()
	gs.set_flag("log_watched", true)
	var path: String = story.night_cutscene("caught")
	var lines := _run_cutscene(w, path)
	check(" ".join(lines).contains("Look what crept out"), "Slate sees her (%s)" % [lines])
	check(w.npc_by_id("slate")["pos"].distance_to(w.player_pos) < 40.0, "Slate grabbed her")
	check_eq(gs.get_flag("rescue"), "captured", "captured")
	var then: Dictionary = Cutscene.load_file(path)["then"]
	check_eq(str(then["area"]), story.prison_area(), "then: the prisoner den")
	check(_world(story.prison_area()).spawns.has(str(then["spawn"])), "a spawn there")
	check(not story.sneaking(gs) and story.goal_key(gs) == "", "no longer sneaking")


# --- A6: the prisoner den


func test_prisoner_den() -> void:
	var p = _world(story.prison_area())
	var a = _world("apprentices_den")
	if not check(p != null and p.is_indoors(), "the prisoner den is a den"):
		return
	var pf: Rect2 = p.interior["floor_rect"]
	var af: Rect2 = a.interior["floor_rect"]
	check(pf.size.x > af.size.x and pf.size.y > af.size.y, "bigger than the apprentices' den (%s vs %s)" % [pf.size, af.size])
	check_eq(p.interior["settings"]["walls"], "bramble", "rough bramble walls")
	var ivy: Array = p.props.filter(func(pr): return pr["type"] == "ivy")
	if check(ivy.size() == 1, "ivy over the entrance"):
		var door: Rect2 = p.interior["door_rect"]
		check(absf(ivy[0]["pos"].x - door.get_center().x) < 2.0 and ivy[0]["pos"].y >= door.position.y, "right over the doorway")
		check(not ivy[0]["solid"], "Fern can pass under it")
	var captives: Array = p.npcs.filter(func(n): return n["id"].begins_with("captive"))
	check(captives.size() >= 2, "other captives (%d)" % captives.size())
	check(p.spawns.has("nest"), "she wakes on bedding")
	var nest: Dictionary = p.interior["nests"].filter(func(n): return n["mine"])[0]
	check(not nest["feather"], "no feather on the rogues' bedding")
	check_eq(p.spot_by_id("my_nest")["message"], "story.prison_bedding", "its own line")
	check(p.ground.size() >= 3, "old bedding and scraps on the floor")
	# Walking out: the doorway is still an exit (game.gd turns it into the
	# placeholder ending).
	check_eq(p.exits.size(), 1, "one way out")
	story.escape_placeholder(gs)
	check(gs.get_flag("rescue") == "escaped" and not story.is_night(gs), "placeholder: home, morning")
	check(strings.has(str(rs["escape_message"])), "'To be continued' line")


func test_rescue_flags_survive_save_and_load() -> void:
	_setf(AFTER_CAMP)
	_setf({"rogue_warned": true, "told_rook": true, "night": true, "log_watched": true, "rescue": "captured"})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.save_data()))
	var g2 = GameStateCore.new()
	g2.load_save_data(saved)
	for k in ["told_rook", "night", "log_watched", "rogue_camp_found"]:
		check_eq(g2.get_flag(k), true, "loaded %s" % k)
	check_eq(g2.get_flag("rescue"), "captured", "loaded rescue")

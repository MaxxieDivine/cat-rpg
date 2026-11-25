extends "res://tests/test_base.gd"
## Story beats (core, headless): "The rogue and the missing Wick", Part A.
## When Wick goes missing (enough border patrols, not while he's out on
## one), the deputy's report giving the news once, the reminder, Bram's and
## Sorrel's new lines, the goal, no patrols while investigating, Wick left
## out of the camp, and the save hook keeping all of it.
## Expected values come from data/story.json.

const Story := preload("res://scripts/core/story.gd")
const World := preload("res://scripts/core/world.gd")
const Areas := preload("res://scripts/core/areas.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")

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

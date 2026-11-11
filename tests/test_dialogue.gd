extends "res://tests/test_base.gd"
## Dialogue runner + GameState: branches, flags, bonds, the repeat-line
## switch, and the real conversations played start to finish. Lines are read
## from the dialogue files, not hard-coded.

const GameState := preload("res://scripts/core/game_state.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var state
var d
var convs: Dictionary = {}


func before_each() -> void:
	state = GameState.new()
	d = Dialogue.new(state)
	for id in ["bram", "sorrel", "wick", "cow"]:
		convs[id] = JsonData.load_dict("res://data/dialogue/%s.json" % id)


func _text(conv: String, node: String) -> String:
	return str(convs[conv]["nodes"][node]["text"])


## Plays `conv` from the start, picking choices by their index from `picks`
## in order. Returns the node ids of every line shown.
func _play(conv: String, picks: Array = []) -> Array[String]:
	var seen: Array[String] = []
	var ev: Dictionary = d.start(convs[conv], conv)
	var guard := 0
	while ev["type"] == "line" and guard < 100:
		guard += 1
		seen.append(ev["node"])
		if not ev["choices"].is_empty():
			check(not picks.is_empty(), "%s: ran out of picks at %s" % [conv, ev["node"]])
			ev = d.choose(picks.pop_front() if not picks.is_empty() else 0)
		else:
			ev = d.advance()
	check(not d.is_active(), "%s: conversation ended" % conv)
	return seen


# --- GameState


func test_state_starts_empty_with_zero_bonds() -> void:
	var defs := JsonData.load_dict(GameState.STATE_PATH)
	for id in defs["bonds"]:
		check_eq(state.bond(id), 0, "bond %s starts at 0" % id)
	for f in defs["flags"]:
		var want: Variant = false if defs["flags"][f]["type"] == "bool" else null
		check_eq(state.get_flag(f), want, "flag %s unset" % f)


func test_state_rejects_unknown_flags_and_bad_values() -> void:
	check(not state.set_flag("no_such_flag", true), "unknown flag refused")
	check(not state.set_flag("vole", "eaten"), "value outside the list refused")
	check(not state.set_flag("talked_bram", "yes"), "string into a bool flag refused")
	check(state.set_flag("vole", "kept"), "valid value stored")
	check_eq(state.get_flag("vole"), "kept", "vole stored")
	check(not state.add_bond("fern", 1), "fern has no bond")
	state.add_bond("wick", 2)
	state.add_bond("wick", -1)
	check_eq(state.bond("wick"), 1, "bond adds up")
	state.reset()
	check_eq(state.get_flag("vole"), null, "reset clears flags")
	check_eq(state.bond("wick"), 0, "reset zeroes bonds")


# --- Runner on small hand-made conversations


func test_branch_first_match_wins_and_fallback() -> void:
	var conv := {"start": "b", "nodes": {
		"b": {"branch": [
			{"if": {"vole": "kept"}, "next": "kept"},
			{"if": {"talked_wick": true}, "next": "talked"},
			{"next": "fallback"},
		]},
		"kept": {"speaker": "wick", "text": "kept", "end": true},
		"talked": {"speaker": "wick", "text": "talked", "end": true},
		"fallback": {"speaker": "wick", "text": "fallback", "end": true},
	}}
	check_eq(d.start(conv)["node"], "fallback", "no flags -> fallback")
	state.set_flag("talked_wick", true)
	check_eq(d.start(conv)["node"], "talked", "second entry matches")
	state.set_flag("vole", "kept")
	check_eq(d.start(conv)["node"], "kept", "first match wins even when a later one matches too")


func test_branch_condition_needs_every_flag() -> void:
	var conv := {"start": "b", "nodes": {
		"b": {"branch": [{"if": {"vole": "shared", "sorrel_thanked": false}, "next": "yes"}, {"next": "no"}]},
		"yes": {"speaker": "sorrel", "text": "yes", "end": true},
		"no": {"speaker": "sorrel", "text": "no", "end": true},
	}}
	check_eq(d.start(conv)["node"], "no", "vole unset")
	state.set_flag("vole", "shared")
	check_eq(d.start(conv)["node"], "yes", "both match")
	state.set_flag("sorrel_thanked", true)
	check_eq(d.start(conv)["node"], "no", "one no longer matches")


func test_node_and_choice_set_and_bond() -> void:
	var conv := {"start": "a", "nodes": {
		"a": {"speaker": "wick", "text": "a", "bond": {"wick": 2}, "choices": [
			{"text": "x", "next": "b", "set": {"vole": "kept"}, "bond": {"wick": 1}},
			{"text": "y", "next": "b", "set": {"vole": "shared"}},
		]},
		"b": {"speaker": "wick", "text": "b", "set": {"talked_wick": true}, "end": true},
	}}
	var ev: Dictionary = d.start(conv)
	check_eq(state.bond("wick"), 2, "node bond applies on entering")
	check_eq(ev["choices"], ["x", "y"], "choice texts")
	check_eq(d.advance()["node"], "a", "advance waits for a choice")
	check_eq(d.choose(5)["node"], "a", "bad index ignored")
	check_eq(state.get_flag("vole"), null, "nothing set before choosing")
	ev = d.choose(0)
	check_eq(ev["node"], "b", "choice follows its next")
	check_eq(state.get_flag("vole"), "kept", "choice set")
	check_eq(state.bond("wick"), 3, "choice bond")
	check_eq(state.get_flag("talked_wick"), true, "node set applies when the line shows")
	check_eq(d.advance()["type"], "end", "end line ends")
	check(not d.is_active(), "not active after end")


func test_expression_defaults_to_neutral() -> void:
	var ev: Dictionary = d.start({"start": "a", "nodes": {"a": {"speaker": "bram", "text": "hi", "end": true}}})
	check_eq(ev["expression"], "neutral", "default expression")


func test_branch_loop_ends_safely() -> void:
	var ev: Dictionary = d.start({"start": "a", "nodes": {"a": {"branch": [{"next": "b"}]}, "b": {"branch": [{"next": "a"}]}}})
	check_eq(ev["type"], "end", "branch loop ends instead of hanging")


# --- The real conversations


func test_bram_eager_and_repeat() -> void:
	var seen := _play("bram", [0])
	check(seen.has("bram_eager") and not seen.has("bram_nervous"), "eager path: %s" % [seen])
	check(seen.has("fern_eager"), "Fern says her choice")
	check_eq(state.get_flag("bram_reply"), "eager", "bram_reply")
	check_eq(state.bond("bram"), 1, "bond bram +1")
	check_eq(state.get_flag("talked_bram"), true, "talked_bram")
	check_eq(_play("bram"), ["repeat"] as Array[String], "repeat line after the full conversation")
	check_eq(d.start(convs["bram"])["text"], _text("bram", "repeat"), "repeat text from the file")
	check_eq(state.bond("bram"), 1, "repeat changes nothing")


func test_bram_nervous() -> void:
	var seen := _play("bram", [1])
	check(seen.has("bram_nervous") and not seen.has("bram_eager"), "nervous path")
	check_eq(state.get_flag("bram_reply"), "nervous", "bram_reply")
	check_eq(state.bond("bram"), 0, "no bond for nervous")


func test_fern_lines_are_fern() -> void:
	d.start(convs["bram"])
	d.advance()
	var ev: Dictionary = d.choose(0)
	check_eq(ev["speaker"], "fern", "Fern speaks her choice")


func test_wick_kept_changes_later_lines() -> void:
	var seen := _play("wick", [0, 0])
	check(seen.has("our_secret"), "kept path")
	check_eq(state.get_flag("vole"), "kept", "vole kept")
	check_eq(state.bond("wick"), 2, "stream jab +1, eating +1")
	check_eq(state.get_flag("talked_wick"), true, "talked_wick")
	check_eq(_play("wick"), ["repeat_kept"] as Array[String], "Wick's repeat for kept")
	_play("sorrel")
	check_eq(_play("sorrel"), ["empty_pile"] as Array[String], "Sorrel notices the empty pile")
	check_eq(_play("sorrel"), ["empty_pile"] as Array[String], "and keeps saying so")


func test_wick_shared_changes_later_lines() -> void:
	var seen := _play("wick", [1, 1])
	check(seen.has("good_one") and seen.has("say_hi"), "shared path")
	check_eq(state.get_flag("vole"), "shared", "vole shared")
	check_eq(state.bond("wick"), 0, "no bond on this path")
	check_eq(_play("wick"), ["repeat_shared"] as Array[String], "Wick's repeat for shared")
	var full := _play("sorrel")
	check(not full.has("thanks"), "first talk with Sorrel is her story")
	check_eq(_play("sorrel"), ["thanks"] as Array[String], "then she thanks Fern for the vole")
	check_eq(state.get_flag("sorrel_thanked"), true, "thanks remembered")
	check_eq(_play("sorrel"), ["dozing"] as Array[String], "thanks only once")


func test_sorrel_before_wick() -> void:
	var seen := _play("sorrel")
	check_eq(seen, ["come", "river", "stones", "grandmother", "walk_first"] as Array[String], "Sorrel's story in order")
	check_eq(_play("sorrel"), ["dozing"] as Array[String], "repeat before the vole: dozing")
	_play("wick", [1, 1])
	check_eq(_play("sorrel"), ["thanks"] as Array[String], "vole shared later: thanks")


func test_any_order() -> void:
	for order in [["bram", "sorrel", "wick"], ["wick", "bram", "sorrel"], ["sorrel", "wick", "bram"]]:
		state.reset()
		for id: String in order:
			_play(id, [0, 0])
		for id: String in order:
			check_eq(state.get_flag("talked_" + id), true, "%s talked after order %s" % [id, order])


func test_cow_says_moo() -> void:
	var ev: Dictionary = d.start(convs["cow"])
	check_eq(ev["text"], _text("cow", "moo"), "cow line")
	check_eq(ev["speaker"], "cow", "cow speaks")
	check_eq(d.advance()["type"], "end", "one line")

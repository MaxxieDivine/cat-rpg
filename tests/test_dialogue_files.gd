extends "res://tests/test_base.gd"
## Every dialogue file must validate (CI fails otherwise), and the validator
## must catch each kind of mistake it promises to.

const Validator := preload("res://scripts/core/dialogue_validator.gd")
const JsonData := preload("res://scripts/core/json_data.gd")


func test_every_dialogue_file_is_valid() -> void:
	var files := Validator.dialogue_files()
	check(files.size() >= 4, "found the dialogue files (%s)" % [files])
	for f in files:
		var errors := Validator.validate_file(f)
		check(errors.is_empty(), "%s:\n       %s" % [f, "\n       ".join(errors)])


func test_world_npcs_point_at_real_dialogue_files() -> void:
	var world := JsonData.load_dict("res://data/world.json")
	var speakers := JsonData.load_dict(Validator.SPEAKERS_PATH)
	var files := Validator.dialogue_files()
	for n: Dictionary in world["npcs"]:
		check(files.has(str(n.get("dialogue", ""))), "%s's dialogue file %s exists" % [n["id"], n.get("dialogue")])
		check(speakers.has(n["id"]), "%s is a known speaker (name, voice)" % n["id"])
	check(speakers.has("fern") and speakers["fern"]["side"] == "right", "Fern speaks from the right")


func _ok() -> Dictionary:
	return {"start": "a", "nodes": {
		"a": {"speaker": "wick", "text": "hi", "choices": [{"text": "x", "next": "b"}, {"text": "y", "next": "b"}]},
		"b": {"speaker": "fern", "text": "bye", "end": true},
	}}


func _expect_error(conv: Dictionary, needle: String, what: String) -> void:
	var errors := Validator.validate(conv)
	var found := false
	for e in errors:
		found = found or e.contains(needle)
	check(found, "%s: expected an error containing '%s', got %s" % [what, needle, errors])


func test_valid_conversation_has_no_errors() -> void:
	check_eq(Validator.validate(_ok()), [] as Array[String], "small valid conversation")


func test_catches_missing_next_target() -> void:
	var c := _ok()
	c["nodes"]["a"]["choices"][1]["next"] = "nowhere"
	_expect_error(c, "next target 'nowhere' does not exist", "choice next")
	c = _ok()
	c["nodes"]["b"] = {"speaker": "fern", "text": "bye", "next": "gone"}
	_expect_error(c, "next target 'gone' does not exist", "line next")
	c = _ok()
	c["start"] = "missing"
	_expect_error(c, "start node 'missing' does not exist", "start")


func test_catches_unreachable_nodes() -> void:
	var c := _ok()
	c["nodes"]["orphan"] = {"speaker": "bram", "text": "nobody hears me", "end": true}
	_expect_error(c, "node 'orphan' is unreachable", "orphan node")


func test_catches_unknown_flags() -> void:
	var c := _ok()
	c["nodes"]["b"]["set"] = {"talked_brma": true}
	_expect_error(c, "sets unknown flag 'talked_brma'", "node set")
	c = _ok()
	c["nodes"]["a"]["choices"][0]["set"] = {"mood": "good"}
	_expect_error(c, "sets unknown flag 'mood'", "choice set")
	c = _ok()
	c["start"] = "s"
	c["nodes"]["s"] = {"branch": [{"if": {"volee": "kept"}, "next": "a"}, {"next": "a"}]}
	_expect_error(c, "tests unknown flag 'volee'", "branch condition")
	c = _ok()
	c["nodes"]["b"]["set"] = {"vole": "eaten"}
	_expect_error(c, "sets vole to bad value", "value outside the list")


func test_catches_unknown_speakers_and_expressions() -> void:
	var c := _ok()
	c["nodes"]["a"]["speaker"] = "fenr"
	_expect_error(c, "unknown speaker 'fenr'", "speaker")
	c = _ok()
	c["nodes"]["a"]["expression"] = "smug"
	_expect_error(c, "unknown expression 'smug'", "expression")
	c = _ok()
	c["nodes"]["b"]["bond"] = {"fern": 1}
	_expect_error(c, "bond of unknown cat 'fern'", "bond")


func test_catches_too_many_choices() -> void:
	var c := _ok()
	for t in ["z", "w"]:
		c["nodes"]["a"]["choices"].append({"text": t, "next": "b"})
	_expect_error(c, "has 4 choices (at most 3)", "four choices")


func test_catches_shape_mistakes() -> void:
	var c := _ok()
	c["nodes"]["b"].erase("end")
	_expect_error(c, "needs exactly one of next / choices / end", "line without exit")
	c = _ok()
	c["nodes"]["b"]["nxet"] = "a"
	_expect_error(c, "unknown field 'nxet'", "typo field")
	c = _ok()
	c["start"] = "s"
	c["nodes"]["s"] = {"branch": [{"if": {"vole": "kept"}, "next": "a"}]}
	_expect_error(c, "branch has no fallback", "no fallback")
	c = _ok()
	c["start"] = "s"
	c["nodes"]["s"] = {"branch": [{"next": "a"}, {"if": {"vole": "kept"}, "next": "b"}]}
	_expect_error(c, "comes after the fallback", "entry after fallback")
	c = _ok()
	c["nodes"]["b"] = {"speaker": "fern", "text": "loop", "next": "a"}
	_expect_error(c, "can never reach an end", "endless loop")

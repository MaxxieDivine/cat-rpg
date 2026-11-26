extends RefCounted
## Checks a dialogue file before it ships. CI runs this over every file in
## data/dialogue/ (tools/validate_dialogue.gd and tests/test_dialogue_files.gd)
## and fails the build on any error. preload() this script.
##
## Errors: missing start or next targets, unreachable nodes, unknown flags,
## speakers, bond cats or expressions, bad flag values, more than
## MAX_CHOICES choices, nodes that are neither a line nor a branch, lines
## without exactly one of next / choices / end, branches without a single
## final fallback, and nodes from which no end can be reached, unknown
## {placeholders} in text, and await nodes (`"await": <screen>`, e.g. the
## Name Editor) without both a "next" (confirmed) and a "cancel" target.

const JsonData := preload("res://scripts/core/json_data.gd")
const GameState := preload("res://scripts/core/game_state.gd")
const DIALOGUE_DIR := "res://data/dialogue"
const SPEAKERS_PATH := "res://data/speakers.json"
const MAX_CHOICES := 3
const NODE_KEYS := ["speaker", "expression", "text", "next", "choices", "branch", "set", "bond", "end", "await", "cancel"]
## Screens a conversation can wait on (game.gd opens them).
const AWAITS := ["name_editor"]
const CHOICE_KEYS := ["text", "next", "set", "bond", "if"]
const BRANCH_KEYS := ["if", "next"]


## Every dialogue file path, sorted.
static func dialogue_files() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(DIALOGUE_DIR):
		if f.get_extension() == "json":
			out.append(DIALOGUE_DIR.path_join(f))
	out.sort()
	return out


## Loads and checks one file. Errors are prefixed with the file name.
static func validate_file(path: String, speakers: Dictionary = {}, state = null) -> Array[String]:
	var errors: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		errors.append("%s: not a JSON object (parse error?)" % path.get_file())
		return errors
	for e in validate(parsed, speakers, state):
		errors.append("%s: %s" % [path.get_file(), e])
	return errors


## Checks a parsed conversation. `speakers` defaults to data/speakers.json,
## `state` (a GameState, for flag and bond names) to data/state.json.
static func validate(conv: Dictionary, speakers: Dictionary = {}, state = null) -> Array[String]:
	if speakers.is_empty():
		speakers = JsonData.load_dict(SPEAKERS_PATH)
	if state == null:
		state = GameState.new()
	var errors: Array[String] = []
	var nodes: Variant = conv.get("nodes")
	if not nodes is Dictionary or (nodes as Dictionary).is_empty():
		errors.append("no \"nodes\" object")
		return errors
	var start := str(conv.get("start", ""))
	if not nodes.has(start):
		errors.append("start node '%s' does not exist" % start)

	# id -> ids it can go to
	var edges: Dictionary = {}
	var ends: Array[String] = []
	for id: String in nodes:
		var n: Variant = nodes[id]
		var where := "node '%s'" % id
		edges[id] = []
		if not n is Dictionary:
			errors.append("%s is not an object" % where)
			continue
		for k: String in n:
			if not NODE_KEYS.has(k):
				errors.append("%s has unknown field '%s'" % [where, k])
		_check_set(n.get("set", {}), where, state, errors)
		_check_bond(n.get("bond", {}), where, state, errors)
		if n.has("await"):
			for k in ["speaker", "text", "expression", "choices", "end", "branch"]:
				if n.has(k):
					errors.append("%s waits on a screen and cannot have '%s'" % [where, k])
			if not AWAITS.has(str(n["await"])):
				errors.append("%s awaits unknown screen '%s' (known: %s)" % [where, n["await"], ", ".join(AWAITS)])
			_check_target(n.get("next"), where + " next", nodes, errors, edges[id])
			_check_target(n.get("cancel"), where + " cancel", nodes, errors, edges[id])
			continue
		if n.has("cancel"):
			errors.append("%s: only await nodes have \"cancel\"" % where)
		if n.has("branch"):
			for k in ["speaker", "text", "expression", "next", "choices", "end"]:
				if n.has(k):
					errors.append("%s is a branch and cannot have '%s'" % [where, k])
			_check_branch(n["branch"], where, nodes, state, errors, edges[id])
			continue
		if not n.has("text"):
			errors.append("%s has neither \"text\" nor \"branch\"" % where)
			continue
		if str(n["text"]).strip_edges() == "":
			errors.append("%s has empty text" % where)
		_check_placeholders(str(n["text"]), where, state, errors)
		var speaker := str(n.get("speaker", ""))
		if not speakers.has(speaker):
			errors.append("%s has unknown speaker '%s'" % [where, speaker])
		if n.has("expression") and not state.expressions.has(str(n["expression"])):
			errors.append("%s has unknown expression '%s' (known: %s)" % [where, n["expression"], ", ".join(state.expressions)])
		var exits := 0
		for k in ["next", "choices", "end"]:
			if n.has(k):
				exits += 1
		if exits != 1:
			errors.append("%s needs exactly one of next / choices / end" % where)
		if n.has("end") and n["end"] != true:
			errors.append("%s: \"end\" must be true" % where)
		if n.get("end", false) == true:
			ends.append(id)
		if n.has("next"):
			_check_target(n["next"], where, nodes, errors, edges[id])
		if n.has("choices"):
			_check_choices(n["choices"], where, nodes, state, errors, edges[id])

	if nodes.has(start):
		# Unreachable: not visited walking forward from start.
		var seen := _walk(start, edges)
		var ids: Array = nodes.keys()
		ids.sort()
		for id: String in ids:
			if not seen.has(id):
				errors.append("node '%s' is unreachable from start '%s'" % [id, start])
		# Dead ends: reachable nodes from which no end line can be reached.
		var reverse: Dictionary = {}
		for id: String in edges:
			for to: String in edges[id]:
				if not reverse.has(to):
					reverse[to] = []
				reverse[to].append(id)
		var can_end: Dictionary = {}
		for e in ends:
			can_end.merge(_walk(e, reverse))
		for id: String in ids:
			if seen.has(id) and not can_end.has(id):
				errors.append("node '%s' can never reach an end" % id)
	return errors


static func _check_target(target: Variant, where: String, nodes: Dictionary, errors: Array[String], out: Array) -> void:
	var t := str(target) if target is String else ""
	if t == "" or not nodes.has(t):
		errors.append("%s: next target '%s' does not exist" % [where, str(target)])
	else:
		out.append(t)


static func _check_choices(choices: Variant, where: String, nodes: Dictionary, state, errors: Array[String], out: Array) -> void:
	if not choices is Array or (choices as Array).is_empty():
		errors.append("%s: \"choices\" must be a non-empty list" % where)
		return
	if choices.size() > MAX_CHOICES:
		errors.append("%s has %d choices (at most %d)" % [where, choices.size(), MAX_CHOICES])
	var unconditional := 0
	for i in choices.size():
		var c: Variant = choices[i]
		var cw := "%s choice %d" % [where, i + 1]
		if not c is Dictionary:
			errors.append("%s is not an object" % cw)
			continue
		for k: String in c:
			if not CHOICE_KEYS.has(k):
				errors.append("%s has unknown field '%s'" % [cw, k])
		if str(c.get("text", "")).strip_edges() == "":
			errors.append("%s has no text" % cw)
		_check_placeholders(str(c.get("text", "")), cw, state, errors)
		_check_target(c.get("next"), cw, nodes, errors, out)
		_check_set(c.get("set", {}), cw, state, errors)
		_check_bond(c.get("bond", {}), cw, state, errors)
		if c.has("if"):
			_check_cond(c["if"], cw, state, errors)
		else:
			unconditional += 1
	if unconditional == 0:
		errors.append("%s: every choice has an \"if\" (one must always show)" % where)


static func _check_branch(entries: Variant, where: String, nodes: Dictionary, state, errors: Array[String], out: Array) -> void:
	if not entries is Array or (entries as Array).is_empty():
		errors.append("%s: \"branch\" must be a non-empty list" % where)
		return
	var fallback := -1
	for i in entries.size():
		var e: Variant = entries[i]
		var ew := "%s branch %d" % [where, i + 1]
		if not e is Dictionary:
			errors.append("%s is not an object" % ew)
			continue
		for k: String in e:
			if not BRANCH_KEYS.has(k):
				errors.append("%s has unknown field '%s'" % [ew, k])
		if fallback >= 0:
			errors.append("%s comes after the fallback and can never match" % ew)
		if e.has("if"):
			_check_cond(e["if"], ew, state, errors)
		elif fallback < 0:
			fallback = i
		_check_target(e.get("next"), ew, nodes, errors, out)
	if fallback < 0:
		errors.append("%s: branch has no fallback (an entry without \"if\")" % where)


## An "if" (branch entry or choice): flag -> value, every flag known.
static func _check_cond(cond: Variant, where: String, state, errors: Array[String]) -> void:
	if not cond is Dictionary or (cond as Dictionary).is_empty():
		errors.append("%s: \"if\" must be a non-empty object" % where)
		return
	for flag: String in cond:
		if not state.is_known_flag(flag):
			errors.append("%s tests unknown flag '%s'" % [where, flag])
		elif not state.is_valid_value(flag, cond[flag], true):
			errors.append("%s tests %s against bad value %s" % [where, flag, var_to_str(cond[flag])])


## Text may only use the placeholders GameState fills in ({player_name},
## {name_<cat id>}).
static func _check_placeholders(text: String, where: String, state, errors: Array[String]) -> void:
	var re := RegEx.create_from_string("\\{([a-z_]*)\\}")
	for m in re.search_all(text):
		if not state.placeholders().has(m.get_string(1)):
			errors.append("%s uses unknown placeholder {%s} (known: %s)" % [where, m.get_string(1), ", ".join(state.placeholders())])


static func _check_set(d: Variant, where: String, state, errors: Array[String]) -> void:
	if not d is Dictionary:
		errors.append("%s: \"set\" must be an object" % where)
		return
	for flag: String in d:
		if not state.is_known_flag(flag):
			errors.append("%s sets unknown flag '%s'" % [where, flag])
		elif not state.is_valid_value(flag, d[flag]):
			errors.append("%s sets %s to bad value %s" % [where, flag, var_to_str(d[flag])])


static func _check_bond(d: Variant, where: String, state, errors: Array[String]) -> void:
	if not d is Dictionary:
		errors.append("%s: \"bond\" must be an object" % where)
		return
	for id: String in d:
		if not state.bond_ids.has(id):
			errors.append("%s changes bond of unknown cat '%s'" % [where, id])
		var v: Variant = d[id]
		if not (v is float or v is int) or float(v) != floorf(float(v)):
			errors.append("%s: bond change for '%s' must be a whole number" % [where, id])


static func _walk(from: String, edges: Dictionary) -> Dictionary:
	var seen := {from: true}
	var todo: Array[String] = [from]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		for to: String in edges.get(id, []):
			if not seen.has(to):
				seen[to] = true
				todo.append(to)
	return seen

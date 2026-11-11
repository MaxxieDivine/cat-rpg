extends RefCounted
## Runs one conversation (a dialogue JSON file, see CLAUDE.md "Dialogue
## files") node by node against a GameState. Plain data, no Nodes; the
## DialogueManager autoload owns one of these. preload() this script.
##
## start() / advance() / choose() return an event:
##   {"type": "line", "node", "speaker", "expression", "text", "choices": [texts]}
##   {"type": "end"}
## Branch nodes never reach the view: they are resolved on the way. A node's
## "set" and "bond" apply when it is entered; a choice's when it is picked.

## Most branch nodes in a row before we give up (a loop of branches).
const MAX_HOPS := 64
const DEFAULT_EXPRESSION := "neutral"

var state
var conversation: Dictionary = {}
## Name for warnings (usually the file path).
var conversation_id := ""
## The line node on screen, or "" when not running.
var node_id := ""


func _init(game_state) -> void:
	state = game_state


func is_active() -> bool:
	return node_id != ""


func node() -> Dictionary:
	return conversation.get("nodes", {}).get(node_id, {})


## Starts a conversation at its "start" node.
func start(conv: Dictionary, id: String = "") -> Dictionary:
	conversation = conv
	conversation_id = id
	node_id = ""
	return _enter(str(conv.get("start", "")))


## The current line as an event (or "end" when nothing is running).
func current() -> Dictionary:
	if not is_active():
		return {"type": "end"}
	var n := node()
	var choices: Array[String] = []
	for c: Dictionary in n.get("choices", []):
		choices.append(str(c.get("text", "")))
	return {
		"type": "line",
		"node": node_id,
		"speaker": str(n.get("speaker", "")),
		"expression": str(n.get("expression", DEFAULT_EXPRESSION)),
		"text": str(n.get("text", "")),
		"choices": choices,
	}


func has_choices() -> bool:
	return is_active() and not (node().get("choices", []) as Array).is_empty()


## Moves past a line without choices: to its "next", or ends the
## conversation after an "end" line. Does nothing while choices are shown.
func advance() -> Dictionary:
	if not is_active():
		return {"type": "end"}
	if has_choices():
		return current()
	var n := node()
	if n.get("end", false) or not n.has("next"):
		return _stop()
	return _enter(str(n["next"]))


## Picks choice `index` (0-based): applies its set / bond, follows its next.
func choose(index: int) -> Dictionary:
	if not has_choices():
		return current()
	var choices: Array = node()["choices"]
	if index < 0 or index >= choices.size():
		return current()
	var c: Dictionary = choices[index]
	state.apply_set(c.get("set", {}))
	state.apply_bond(c.get("bond", {}))
	return _enter(str(c.get("next", "")))


func _enter(id: String) -> Dictionary:
	var nodes: Dictionary = conversation.get("nodes", {})
	for hop in MAX_HOPS:
		if not nodes.has(id):
			push_warning("Dialogue %s: no node '%s'; ending" % [conversation_id, id])
			return _stop()
		var n: Dictionary = nodes[id]
		state.apply_set(n.get("set", {}))
		state.apply_bond(n.get("bond", {}))
		if not n.has("branch"):
			node_id = id
			return current()
		id = _pick_branch(n["branch"])
		if id == "":
			push_warning("Dialogue %s: no branch matched; ending" % conversation_id)
			return _stop()
	push_warning("Dialogue %s: more than %d branches in a row; ending" % [conversation_id, MAX_HOPS])
	return _stop()


## First entry whose "if" matches (an entry without "if" always does).
func _pick_branch(entries: Array) -> String:
	for e: Dictionary in entries:
		if state.matches(e.get("if", {})):
			return str(e.get("next", ""))
	return ""


func _stop() -> Dictionary:
	node_id = ""
	return {"type": "end"}

extends RefCounted
## Runs one conversation (a dialogue JSON file, see CLAUDE.md "Dialogue
## files") node by node against a GameState. Plain data, no Nodes; the
## DialogueManager autoload owns one of these. preload() this script.
##
## start() / advance() / choose() / resume() return an event:
##   {"type": "line", "node", "conversation", "speaker", "expression", "text", "choices": [texts]}
##   {"type": "await", "node", "conversation", "await": screen}
##   {"type": "end"}
## Branch nodes never reach the view: they are resolved on the way. A node's
## "set" and "bond" apply when it is entered; a choice's when it is picked.
## Text and choices have {player_name} filled in (GameState.format_text()).
## An await node ({"await": "name_editor", "next": ..., "cancel": ...})
## pauses the conversation while the view shows that screen; resume(true)
## goes on to "next", resume(false) to "cancel".
## start() may queue a follow-up conversation (the naming offer after the
## name-giver's own lines): when the first one ends, the follow-up starts
## instead of an "end".

## Most branch nodes in a row before we give up (a loop of branches).
const MAX_HOPS := 64
const DEFAULT_EXPRESSION := "neutral"

var state
var conversation: Dictionary = {}
## Name for warnings (usually the file path).
var conversation_id := ""
## The line (or await) node on screen, or "" when not running.
var node_id := ""
## [conversation, id] to start when this one ends, or [].
var follow_up: Array = []


func _init(game_state) -> void:
	state = game_state


func is_active() -> bool:
	return node_id != ""


func node() -> Dictionary:
	return conversation.get("nodes", {}).get(node_id, {})


## Starts a conversation at its "start" node. `then` (with `then_id`) is
## started when it ends, if not empty.
func start(conv: Dictionary, id: String = "", then: Dictionary = {}, then_id: String = "") -> Dictionary:
	conversation = conv
	conversation_id = id
	node_id = ""
	follow_up = [] if then.is_empty() else [then, then_id]
	return _enter(str(conv.get("start", "")))


## True while an await node waits for its screen.
func is_waiting() -> bool:
	return is_active() and node().has("await")


## The await node's screen closed: `confirmed` goes on to its "next",
## otherwise to its "cancel".
func resume(confirmed: bool) -> Dictionary:
	if not is_waiting():
		return current()
	var n := node()
	return _enter(str(n.get("next" if confirmed else "cancel", "")))


func _format(text: String) -> String:
	return state.format_text(text) if state != null and state.has_method("format_text") else text


## The current line as an event (or "end" when nothing is running).
func current() -> Dictionary:
	if not is_active():
		return {"type": "end"}
	var n := node()
	if n.has("await"):
		return {"type": "await", "node": node_id, "conversation": conversation_id, "await": str(n["await"])}
	var choices: Array[String] = []
	for c: Dictionary in shown_choices():
		choices.append(_format(str(c.get("text", ""))))
	return {
		"type": "line",
		"node": node_id,
		"conversation": conversation_id,
		"speaker": str(n.get("speaker", "")),
		"expression": str(n.get("expression", DEFAULT_EXPRESSION)),
		"text": _format(str(n.get("text", ""))),
		"choices": choices,
	}


func has_choices() -> bool:
	return is_active() and not shown_choices().is_empty()


## The current line's choices whose "if" matches (a choice without one
## always shows): "Offer prey" only while carrying some.
func shown_choices() -> Array:
	var out: Array = []
	if not is_active():
		return out
	for c: Dictionary in node().get("choices", []):
		if not c.has("if") or state.matches(c["if"]):
			out.append(c)
	return out


## Moves past a line without choices: to its "next", or ends the
## conversation after an "end" line. Does nothing while choices are shown.
func advance() -> Dictionary:
	if not is_active():
		return {"type": "end"}
	if has_choices() or is_waiting():
		return current()
	var n := node()
	if n.get("end", false) or not n.has("next"):
		return _stop()
	return _enter(str(n["next"]))


## Picks choice `index` (0-based): applies its set / bond, follows its next.
func choose(index: int) -> Dictionary:
	if not has_choices():
		return current()
	var choices: Array = shown_choices()
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
			return current()  # a line, or an await node
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
	if not follow_up.is_empty():
		var next: Array = follow_up
		follow_up = []
		conversation = next[0]
		conversation_id = str(next[1])
		return _enter(str(conversation.get("start", "")))
	return {"type": "end"}

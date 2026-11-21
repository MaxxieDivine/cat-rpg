extends Node
## Autoload "DialogueManager": loads conversations from data/dialogue/*.json
## (cached) and runs one at a time against GameState, node by node. A thin
## Node around scripts/core/dialogue.gd; the dialogue box shows the events it
## returns and calls advance() / choose().

signal line_shown(line: Dictionary)
## An await node: the view opens that screen, then calls resume().
signal awaiting(screen: String)
signal ended(path: String)

const Dialogue := preload("res://scripts/core/dialogue.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

## File of the running conversation, or "".
var path := ""
var _runner
var _cache: Dictionary = {}


func runner():
	if _runner == null:
		_runner = Dialogue.new(GameState.state)
	return _runner


func load_conversation(p: String) -> Dictionary:
	if not _cache.has(p):
		_cache[p] = JsonData.load_dict(p)
	return _cache[p]


func is_active() -> bool:
	return runner().is_active()


func current() -> Dictionary:
	return runner().current()


## Starts the conversation in file `p`. Returns its first line (or "end").
## `then`: a conversation file to run straight after it ("" = none).
func start(p: String, then: String = "") -> Dictionary:
	path = p
	var follow: Dictionary = load_conversation(then) if then != "" else {}
	return _emit(runner().start(load_conversation(p), p, follow, then))


## The conversation file to run after talking to NPC `npc_id`: the naming
## offer for the name-giver (data/names/naming.json), else "".
func follow_up_for(npc_id: String) -> String:
	var names = GameState.state.names
	return names.giver_dialogue() if npc_id == names.giver() and names.giver_dialogue() != "" else ""


func is_waiting() -> bool:
	return runner().is_waiting()


## The awaited screen closed (confirmed or cancelled).
func resume(confirmed: bool) -> Dictionary:
	return _emit(runner().resume(confirmed))


func advance() -> Dictionary:
	return _emit(runner().advance())


func choose(index: int) -> Dictionary:
	return _emit(runner().choose(index))


## Drops the running conversation without effects (new game, tests).
func stop() -> void:
	runner().node_id = ""
	runner().follow_up = []
	path = ""


func _emit(ev: Dictionary) -> Dictionary:
	if ev["type"] == "line":
		line_shown.emit(ev)
	elif ev["type"] == "await":
		awaiting.emit(str(ev["await"]))
	else:
		var p := path
		path = ""
		ended.emit(p)
	return ev

extends Node
## Autoload "DialogueManager": loads conversations from data/dialogue/*.json
## (cached) and runs one at a time against GameState, node by node. A thin
## Node around scripts/core/dialogue.gd; the dialogue box shows the events it
## returns and calls advance() / choose().

signal line_shown(line: Dictionary)
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
func start(p: String) -> Dictionary:
	path = p
	return _emit(runner().start(load_conversation(p), p))


func advance() -> Dictionary:
	return _emit(runner().advance())


func choose(index: int) -> Dictionary:
	return _emit(runner().choose(index))


## Drops the running conversation without effects (new game, tests).
func stop() -> void:
	runner().node_id = ""
	path = ""


func _emit(ev: Dictionary) -> Dictionary:
	if ev["type"] == "line":
		line_shown.emit(ev)
	else:
		var p := path
		path = ""
		ended.emit(p)
	return ev

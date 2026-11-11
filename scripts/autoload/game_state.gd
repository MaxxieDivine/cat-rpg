extends Node
## Autoload "GameState": the one game state (flags and bonds) for the whole
## session. A thin Node around scripts/core/game_state.gd, which holds the
## data and rules and is what tests use directly.

signal changed

const State := preload("res://scripts/core/game_state.gd")

var state := State.new()


func reset() -> void:
	state.reset()
	changed.emit()


func get_flag(name: String) -> Variant:
	return state.get_flag(name)


func set_flag(name: String, value: Variant) -> bool:
	var ok: bool = state.set_flag(name, value)
	if ok:
		changed.emit()
	return ok


func bond(id: String) -> int:
	return state.bond(id)


func add_bond(id: String, delta: int) -> bool:
	var ok: bool = state.add_bond(id, delta)
	if ok:
		changed.emit()
	return ok

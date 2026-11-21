extends Node
## Autoload "GameState": the one game state (flags and bonds) for the whole
## session. A thin Node around scripts/core/game_state.gd, which holds the
## data and rules and is what tests use directly.

signal changed
## The player's name changed (get_player_name()); everything showing it
## refreshes.
signal name_changed(new_name: String)

const State := preload("res://scripts/core/game_state.gd")

var state := State.new()


func reset() -> void:
	var old := get_player_name()
	state.reset()
	changed.emit()
	if get_player_name() != old:
		name_changed.emit(get_player_name())


## "Fernwhisker": see scripts/core/game_state.gd get_player_name().
func get_player_name() -> String:
	return state.get_player_name()


## Sets the name from word ids (data/names/); false if it isn't allowed.
func set_player_name(prefix_id: String, suffix_id: String) -> bool:
	var old := get_player_name()
	if not state.set_player_name(prefix_id, suffix_id):
		return false
	changed.emit()
	if get_player_name() != old:
		name_changed.emit(get_player_name())
	return true


func format_text(text: String) -> String:
	return state.format_text(text)


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

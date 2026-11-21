extends Node
## Autoload "GameState": the one game state (flags and bonds) for the whole
## session. A thin Node around scripts/core/game_state.gd, which holds the
## data and rules and is what tests use directly.

signal changed
## A cat's name changed (get_cat_name(id)); everything showing it refreshes.
signal name_changed(cat_id: String, new_name: String)
## A cat's rank changed (its symbol follows).
signal rank_changed(cat_id: String, rank: String)

const State := preload("res://scripts/core/game_state.gd")

var state := State.new()


func reset() -> void:
	var old_names := {}
	var old_ranks := {}
	for id: String in state.cats:
		old_names[id] = state.get_cat_name(id)
		old_ranks[id] = state.get_cat_rank(id)
	state.reset()
	changed.emit()
	for id: String in state.cats:
		if state.get_cat_name(id) != old_names.get(id, ""):
			name_changed.emit(id, state.get_cat_name(id))
		if state.get_cat_rank(id) != old_ranks.get(id, ""):
			rank_changed.emit(id, state.get_cat_rank(id))


## "Fernwhisker": see scripts/core/game_state.gd get_player_name().
func get_player_name() -> String:
	return state.get_player_name()


func get_cat_name(id: String) -> String:
	return state.get_cat_name(id)


func get_cat_rank(id: String) -> String:
	return state.get_cat_rank(id)


## Renames a cat from word ids (data/names/); false if it isn't allowed.
func set_cat_name(id: String, prefix_id: String, suffix_id: String) -> bool:
	var old := state.get_cat_name(id)
	if not state.set_cat_name(id, prefix_id, suffix_id):
		return false
	changed.emit()
	if state.get_cat_name(id) != old:
		name_changed.emit(id, state.get_cat_name(id))
	return true


func set_player_name(prefix_id: String, suffix_id: String) -> bool:
	return set_cat_name(state.names.player_speaker(), prefix_id, suffix_id)


func set_cat_rank(id: String, rank_id: String) -> bool:
	var old := state.get_cat_rank(id)
	if not state.set_cat_rank(id, rank_id):
		return false
	changed.emit()
	if rank_id != old:
		rank_changed.emit(id, rank_id)
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

extends Node
## Autoload "Story": story beats (scripts/core/story.gd) on top of
## GameState's flags. game.gd calls border_marked() when a border patrol's
## last spot is marked, absent() as it fills an area with cats, and
## goal_text() for the hud; Patrols asks blocks_patrols() and absent()
## before the deputy picks a patrol. The game screen calls reset() on a new
## game.

signal changed

const StoryCore := preload("res://scripts/core/story.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

var story := StoryCore.new()


func reset() -> void:
	story.reset()
	changed.emit()


func border_marked(mates: Array) -> bool:
	var went := story.border_marked(GameState.state, mates)
	if went:
		GameState.changed.emit()
		changed.emit()
	return went


func absent(id: String) -> bool:
	return story.absent(GameState.state, id)


func investigating() -> bool:
	return story.investigating(GameState.state)


func blocks_patrols() -> bool:
	return story.blocks_patrols(GameState.state)


## The story goal ("Investigate the rogue scent by the river."), or "".
func goal_text() -> String:
	var key := story.goal_key(GameState.state)
	return "" if key == "" else GameState.format_text(GameStrings.text(key))


## The story part of a save (GameState.save_data() holds the flags).
func save_data() -> Dictionary:
	return story.save_data()


func load_save_data(d: Dictionary) -> void:
	story.load_save_data(d)
	changed.emit()

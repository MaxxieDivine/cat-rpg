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


## Whether cat `id` is away (from area `area`, if given).
func absent(id: String, area: String = "") -> bool:
	return story.absent(GameState.state, id, area)


func camp_area() -> String:
	return story.camp_area()


func can_hide() -> bool:
	return story.can_hide(GameState.state)


func cutscene_path() -> String:
	return story.cutscene_path()


func investigating() -> bool:
	return story.investigating(GameState.state)


func blocks_patrols() -> bool:
	return story.blocks_patrols(GameState.state)


## The story goal ("Investigate the rogue scent by the river."), or "".
func goal_text() -> String:
	var key := story.goal_key(GameState.state)
	return "" if key == "" else GameState.format_text(GameStrings.text(key))


func rogue_npc() -> String:
	return story.rogue_npc()


func leave_plan() -> Dictionary:
	return story.leave_plan(GameState.get_flag("rogue_choice"))


func trail(area_id: String, area_size: Vector2) -> Array[Vector2]:
	if area_id != story.rogue_area():
		return [] as Array[Vector2]
	return story.trail(GameState.state, area_size)


func way_mark(area_id: String) -> Vector2:
	return story.way_mark(GameState.state) if area_id == story.rogue_area() else Vector2.INF


## The story part of a save (GameState.save_data() holds the flags).
func save_data() -> Dictionary:
	return story.save_data()


func load_save_data(d: Dictionary) -> void:
	story.load_save_data(d)
	changed.emit()

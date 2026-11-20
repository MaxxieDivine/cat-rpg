extends Node
## Autoload "Player": Fern's state that carries over between areas (the
## area, the spawn she arrived at, what she carries), plus the passing-out
## settings. A thin Node around scripts/core/player_state.gd. Hunger and
## thirst are in the Needs autoload. The game screen calls reset() when it
## starts.
## The exports are defaults from tuning.json "collapse" and strings.json;
## change them in the remote Inspector (Scene dock > Remote > root > Player)
## while the game runs.

signal area_changed(area: String, spawn: String)

const PlayerState := preload("res://scripts/core/player_state.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

var state := PlayerState.new()

## Where Fern wakes after passing out: an area id and a spawn in it.
@export var recovery_area := "camp"
@export var recovery_spawn := "den"
## Shown on black while she is carried home.
@export_multiline var collapse_message := ""


func _init() -> void:
	var co: Dictionary = JsonData.load_dict("res://data/tuning.json").get("collapse", {})
	recovery_area = str(co.get("recovery_area", recovery_area))
	recovery_spawn = str(co.get("recovery_spawn", recovery_spawn))


func _ready() -> void:
	if collapse_message == "":
		collapse_message = GameStrings.text("collapse.message")


func reset(start_area: String = "camp", start_spawn: String = "start") -> void:
	state.reset(start_area, start_spawn)
	area_changed.emit(state.area, state.spawn)


func arrive(to_area: String, to_spawn: String) -> void:
	state.arrive(to_area, to_spawn)
	area_changed.emit(to_area, to_spawn)


func area() -> String:
	return state.area


func spawn() -> String:
	return state.spawn


func carried_item() -> String:
	return state.carried_item


func drop_carried() -> String:
	return state.drop_carried()

extends Node2D
## An exit out of the area (scenes/area_exit.tscn): walking into its rect
## fades to black and loads `target_area` (an id in data/areas.json) at
## `target_spawn` (a spawn name in that area's file).
## The area file's "exits" entry is the source of truth; world_view.gd
## creates one of these per entry and fills the exports from it. Changing
## an export (e.g. in the remote Inspector while the game runs) changes that
## exit live, because the node writes back into the world's exit entry.
## Invisible in play; with the debug overlay on it draws its rect.

## Area id to load (data/areas.json).
@export var target_area := "":
	set(v):
		target_area = v
		if not exit_data.is_empty():
			exit_data["to"] = v
## Spawn name in the target area.
@export var target_spawn := "":
	set(v):
		target_spawn = v
		if not exit_data.is_empty():
			exit_data["spawn"] = v
## Size of the trigger rect (world px); the node sits at its top-left.
@export var size := Vector2(14, 36):
	set(v):
		size = v
		if not exit_data.is_empty():
			exit_data["rect"] = Rect2(position, v)
		queue_redraw()

## The world's exit entry this node shows ({"id", "rect", "to", "spawn"}).
var exit_data: Dictionary = {}
var _debug := false


func setup(e: Dictionary) -> void:
	exit_data = {}
	name = "Exit_" + str(e.get("id", ""))
	var r: Rect2 = e["rect"]
	position = r.position
	target_area = str(e.get("to", ""))
	target_spawn = str(e.get("spawn", ""))
	size = r.size
	exit_data = e


func _process(_dt: float) -> void:
	var on: bool = Settings.debug_overlay
	if on != _debug:
		_debug = on
		queue_redraw()


func _draw() -> void:
	if _debug:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.3, 0.35))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.3, 0.9), false, 1.0)

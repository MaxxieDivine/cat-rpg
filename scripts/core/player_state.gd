extends RefCounted
## What stays with Fern from area to area (besides hunger and thirst, which
## live in needs.gd): where she is, which spawn she last arrived at, and
## what she carries. Plain data; the `Player` autoload wraps it.
## preload(), no class_name.

## Area id (data/areas.json) and the spawn she last arrived at.
var area := ""
var spawn := ""
## What Fern carries in her mouth ("" = nothing). Prey uses it next
## milestone; passing out drops it.
var carried_item := ""
## How many times she has passed out this game.
var collapses := 0


func reset(start_area: String = "camp", start_spawn: String = "start") -> void:
	area = start_area
	spawn = start_spawn
	carried_item = ""
	collapses = 0


func arrive(to_area: String, to_spawn: String) -> void:
	area = to_area
	spawn = to_spawn


## Drops whatever she carries; returns what it was ("" if nothing).
func drop_carried() -> String:
	var was := carried_item
	carried_item = ""
	return was

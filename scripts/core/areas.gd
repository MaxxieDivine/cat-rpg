extends RefCounted
## The areas Fern can walk between (data/areas.json): id -> area file (a
## world.json-style layout). load_world(id) builds that area's World.
## preload(), no class_name.

const JsonData := preload("res://scripts/core/json_data.gd")
const World := preload("res://scripts/core/world.gd")
const AREAS_PATH := "res://data/areas.json"

var data: Dictionary = {}


func _init(d: Dictionary = {}) -> void:
	data = d if not d.is_empty() else JsonData.load_dict(AREAS_PATH)


## The area a new game starts in.
func start_area() -> String:
	return str(data.get("start", "camp"))


func ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in data.get("areas", {}):
		out.append(k)
	return out


func has(id: String) -> bool:
	return data.get("areas", {}).has(id)


func file(id: String) -> String:
	return str(data.get("areas", {}).get(id, {}).get("file", ""))


func area_data(id: String) -> Dictionary:
	var f := file(id)
	return JsonData.load_dict(f) if f != "" else {}


## A fresh World for area `id` (empty if unknown).
func load_world(id: String, tuning: Dictionary = {}):
	var d := area_data(id)
	if d.is_empty():
		push_warning("Areas: unknown area '%s'" % id)
		return null
	if not d.has("id"):
		d["id"] = id
	return World.new(d, tuning)

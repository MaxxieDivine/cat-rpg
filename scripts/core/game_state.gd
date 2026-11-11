extends RefCounted
## Flags and bonds: everything conversations remember. Plain data, no Nodes;
## the GameState autoload (scripts/autoload/game_state.gd) holds one of these.
## Known flags, their types and the cats that have bonds come from
## data/state.json, so a typo in a dialogue file is caught, not stored.
## preload() this script; no class_name.
##
## Flags are bool ("type": "bool", unset = false) or string ("type":
## "string" with a "values" list, unset = null). Bonds are an int per cat,
## starting at 0.

const JsonData := preload("res://scripts/core/json_data.gd")
const STATE_PATH := "res://data/state.json"

## name -> {"type": "bool"} or {"type": "string", "values": [...]}
var flag_defs: Dictionary = {}
var bond_ids: Array[String] = []
var expressions: Array[String] = []
var flags: Dictionary = {}
var bonds: Dictionary = {}


func _init(defs: Dictionary = {}) -> void:
	if defs.is_empty():
		defs = JsonData.load_dict(STATE_PATH)
	flag_defs = defs.get("flags", {})
	for id in defs.get("bonds", []):
		bond_ids.append(str(id))
	for e in defs.get("expressions", []):
		expressions.append(str(e))
	reset()


## Back to a new game: no flags, every bond 0.
func reset() -> void:
	flags = {}
	bonds = {}
	for id in bond_ids:
		bonds[id] = 0


func is_known_flag(name: String) -> bool:
	return flag_defs.has(name)


func flag_type(name: String) -> String:
	return str(flag_defs.get(name, {}).get("type", ""))


## Whether `value` may be stored in flag `name`. With `allow_unset`, null
## (string flags) also counts: conditions use it to mean "not set yet".
func is_valid_value(name: String, value: Variant, allow_unset: bool = false) -> bool:
	if not is_known_flag(name):
		return false
	match flag_type(name):
		"bool":
			return value is bool
		"string":
			if value == null:
				return allow_unset
			return value is String and (flag_defs[name].get("values", []) as Array).has(value)
	return false


func get_flag(name: String) -> Variant:
	if flags.has(name):
		return flags[name]
	return false if flag_type(name) == "bool" else null


## Stores a flag. Unknown flags and wrong values warn and are ignored.
func set_flag(name: String, value: Variant) -> bool:
	if not is_valid_value(name, value):
		push_warning("GameState: refusing %s = %s (unknown flag or bad value)" % [name, var_to_str(value)])
		return false
	flags[name] = value
	return true


func bond(id: String) -> int:
	return int(bonds.get(id, 0))


func add_bond(id: String, delta: int) -> bool:
	if not bonds.has(id):
		push_warning("GameState: no bond for '%s'" % id)
		return false
	bonds[id] = int(bonds[id]) + delta
	return true


## Applies a dialogue "set" block: {"flag": value, ...}.
func apply_set(d: Dictionary) -> void:
	for name: String in d:
		set_flag(name, d[name])


## Applies a dialogue "bond" block: {"wick": 1, ...}.
func apply_bond(d: Dictionary) -> void:
	for id: String in d:
		add_bond(id, int(d[id]))


## True when every flag in `cond` has the given value ({"vole": "kept"}).
## An empty condition always matches.
func matches(cond: Dictionary) -> bool:
	for name: String in cond:
		if get_flag(name) != cond[name]:
			return false
	return true

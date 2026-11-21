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
##
## The player's name is two word ids, prefix_id + suffix_id (word lists in
## data/names/, rules in scripts/core/names.gd), plus a rank. Everything that
## shows the name calls get_player_name(); dialogue text uses {player_name}
## (format_text()). The GameState autoload emits name_changed.

const JsonData := preload("res://scripts/core/json_data.gd")
const Names := preload("res://scripts/core/names.gd")
const STATE_PATH := "res://data/state.json"
## Placeholders dialogue text may use (format_text()).
const PLACEHOLDERS := ["player_name"]

## name -> {"type": "bool"} or {"type": "string", "values": [...]}
var flag_defs: Dictionary = {}
var bond_ids: Array[String] = []
var expressions: Array[String] = []
var flags: Dictionary = {}
var bonds: Dictionary = {}
## The player's name: word ids from data/names/prefixes.json and
## suffixes.json ("" suffix = just the prefix, the start name "Fern").
var prefix_id := ""
var suffix_id := ""
## kit / apprentice / warrior / leader (data/names/naming.json "ranks").
## Not shown yet: see get_player_name().
var rank := ""
## scripts/core/names.gd (word lists and rules), shared.
var names = Names.shared()


func _init(defs: Dictionary = {}) -> void:
	if defs.is_empty():
		defs = JsonData.load_dict(STATE_PATH)
	flag_defs = defs.get("flags", {})
	for id in defs.get("bonds", []):
		bond_ids.append(str(id))
	for e in defs.get("expressions", []):
		expressions.append(str(e))
	reset()


## Back to a new game: no flags, every bond 0, the start name.
func reset() -> void:
	flags = {}
	bonds = {}
	for id in bond_ids:
		bonds[id] = 0
	var start: Dictionary = names.start_name()
	prefix_id = str(start.get("prefix", ""))
	suffix_id = str(start.get("suffix", ""))
	rank = str(start.get("rank", ""))


## The name everyone sees: prefix (capitalised) + suffix (lowercase),
## "Fern" + "whisker" = "Fernwhisker".
func get_player_name() -> String:
	var full: String = names.build(prefix_id, suffix_id)
	# TODO(rank): rank-based names (kit / apprentice / warrior / leader) go
	# here, e.g. swapping the suffix for names.rank_ending(rank) below
	# warrior. The endings live in data/names/naming.json, not in code. For
	# now the chosen name is shown at every rank.
	return full


## Sets the name from two word ids. Refuses (false) names that names.gd
## doesn't allow: unknown words, the blocklist, NPC names, triple letters.
func set_player_name(new_prefix: String, new_suffix: String) -> bool:
	if not names.is_allowed(new_prefix, new_suffix):
		push_warning("GameState: refusing name %s + %s (%s)" % [new_prefix, new_suffix, names.check(new_prefix, new_suffix)])
		return false
	prefix_id = new_prefix
	suffix_id = new_suffix
	return true


## Fills {player_name} (PLACEHOLDERS) in dialogue text and name plates.
func format_text(text: String) -> String:
	if not text.contains("{"):
		return text
	return text.replace("{player_name}", get_player_name())


## What a save file will keep of the name.
## TODO(save): the save milestone writes this (with flags and bonds) and
## calls load_save_data() on load.
func save_data() -> Dictionary:
	return {"prefix_id": prefix_id, "suffix_id": suffix_id, "rank": rank}


func load_save_data(d: Dictionary) -> void:
	var p := str(d.get("prefix_id", prefix_id))
	var s := str(d.get("suffix_id", suffix_id))
	if names.is_allowed(p, s) or s == "":
		prefix_id = p
		suffix_id = s
	if names.ranks().has(str(d.get("rank", ""))):
		rank = str(d["rank"])


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

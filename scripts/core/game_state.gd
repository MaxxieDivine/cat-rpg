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
## Every cat's name is two word ids, prefix_id + suffix_id (word lists in
## data/names/, rules in scripts/core/names.gd), or a fixed starting name
## until renamed, plus a rank (data/names/naming.json "cats" and "ranks").
## Everything that shows a name calls get_cat_name() / get_player_name();
## dialogue text uses {player_name} and {name_<cat id>} (format_text()). The
## GameState autoload emits name_changed / rank_changed.

const JsonData := preload("res://scripts/core/json_data.gd")
const Names := preload("res://scripts/core/names.gd")
const STATE_PATH := "res://data/state.json"
## Placeholders dialogue text may use (format_text()): {player_name},
## {name_<id>} for every cat in naming.json, and the text variables
## state.json "text_vars" declares (set_text_var(); {patrol_mates}).
const PLAYER_PLACEHOLDER := "player_name"

## name -> {"type": "bool"} or {"type": "string", "values": [...]}
var flag_defs: Dictionary = {}
var bond_ids: Array[String] = []
var expressions: Array[String] = []
var flags: Dictionary = {}
var bonds: Dictionary = {}
## Text variables (state.json "text_vars": name -> default): game systems
## fill them ({patrol_mates} = "Bram and Wick") for dialogue text.
var text_var_defaults: Dictionary = {}
var text_vars: Dictionary = {}
## cat id -> {"prefix_id", "suffix_id", "fixed", "rank"}. "fixed" is the
## starting name of a cat whose name isn't built from words yet ("Bram");
## it is cleared once the cat is renamed.
var cats: Dictionary = {}
## The player's name parts and rank (shortcuts into `cats`).
var prefix_id: String:
	get:
		return str(_player().get("prefix_id", ""))
var suffix_id: String:
	get:
		return str(_player().get("suffix_id", ""))
var rank: String:
	get:
		return str(_player().get("rank", ""))
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
	text_var_defaults = defs.get("text_vars", {})
	reset()


## Back to a new game: no flags, every bond 0, the start name.
func reset() -> void:
	flags = {}
	bonds = {}
	text_vars = text_var_defaults.duplicate()
	for id in bond_ids:
		bonds[id] = 0
	cats = {}
	for id in names.cat_ids():
		var st: Dictionary = names.cat_start(id)
		cats[id] = {
			"prefix_id": str(st.get("prefix", "")),
			"suffix_id": str(st.get("suffix", "")),
			"fixed": str(st.get("name", "")),
			"rank": str(st.get("rank", "none")),
		}


func _player() -> Dictionary:
	return cats.get(names.player_speaker(), {})


## The placeholders text may use: "player_name" and "name_<id>" per cat.
func placeholders() -> Array[String]:
	var out: Array[String] = [PLAYER_PLACEHOLDER]
	for id in names.cat_ids():
		out.append("name_" + id)
	for k: String in text_var_defaults:
		out.append(k)
	return out


## Sets a text variable state.json declares (unknown names are refused).
func set_text_var(name: String, value: String) -> bool:
	if not text_var_defaults.has(name):
		push_warning("GameState: unknown text variable '%s'" % name)
		return false
	text_vars[name] = value
	return true


## Unsets a flag (string flags back to null, bools to false).
func clear_flag(name: String) -> void:
	flags.erase(name)


func has_cat(id: String) -> bool:
	return cats.has(id)


## A cat's name: prefix (capitalised) + suffix (lowercase), "Fern" +
## "whisker" = "Fernwhisker"; its fixed starting name until it is renamed.
func get_cat_name(id: String) -> String:
	var c: Dictionary = cats.get(id, {})
	if c.is_empty():
		return ""
	if str(c["fixed"]) != "":
		return str(c["fixed"])
	# TODO(rank): rank-based names (kit / apprentice / warrior / leader) go
	# here, e.g. swapping the suffix for names.rank_ending(rank) below
	# warrior. The endings live in data/names/naming.json, not in code. For
	# now the chosen name is shown at every rank.
	return names.build(str(c["prefix_id"]), str(c["suffix_id"]))


## The player's name ("Fernwhisker").
func get_player_name() -> String:
	return get_cat_name(names.player_speaker())


## Every other cat's current name (what `id` may not be called).
func names_taken_by_others(id: String) -> Array[String]:
	var out: Array[String] = []
	for other: String in cats:
		if other != id:
			out.append(get_cat_name(other))
	return out


## Renames cat `id` from two word ids. Refuses (false) names names.gd
## doesn't allow: unknown words, the blocklist, another cat's name, triple
## letters.
func set_cat_name(id: String, new_prefix: String, new_suffix: String) -> bool:
	if not cats.has(id):
		push_warning("GameState: no cat '%s'" % id)
		return false
	var why: String = names.check(new_prefix, new_suffix, names_taken_by_others(id))
	if why != names.OK:
		push_warning("GameState: refusing name %s + %s for %s (%s)" % [new_prefix, new_suffix, id, why])
		return false
	cats[id]["prefix_id"] = new_prefix
	cats[id]["suffix_id"] = new_suffix
	cats[id]["fixed"] = ""
	return true


func set_player_name(new_prefix: String, new_suffix: String) -> bool:
	return set_cat_name(names.player_speaker(), new_prefix, new_suffix)


func get_cat_rank(id: String) -> String:
	return str(cats.get(id, {}).get("rank", ""))


## Sets a cat's rank (a naming.json rank id); false for unknown ones.
func set_cat_rank(id: String, rank_id: String) -> bool:
	if not cats.has(id) or not names.ranks().has(rank_id):
		push_warning("GameState: refusing rank '%s' for '%s'" % [rank_id, id])
		return false
	cats[id]["rank"] = rank_id
	return true


## Fills {player_name} and {name_<id>} in dialogue text and name plates.
func format_text(text: String) -> String:
	if not text.contains("{"):
		return text
	text = text.replace("{player_name}", get_player_name())
	for id: String in cats:
		text = text.replace("{name_%s}" % id, get_cat_name(id))
	for k: String in text_vars:
		text = text.replace("{%s}" % k, str(text_vars[k]))
	return text


## What a save file will keep of the names and ranks.
## TODO(save): the save milestone writes this (with flags and bonds) and
## calls load_save_data() on load.
func save_data() -> Dictionary:
	return {"cats": cats.duplicate(true)}


func load_save_data(d: Dictionary) -> void:
	var saved: Dictionary = d.get("cats", {})
	for id: String in saved:
		if not cats.has(id):
			continue
		var c: Dictionary = saved[id]
		if str(c.get("fixed", "")) == "" and names.is_allowed(str(c.get("prefix_id", "")), str(c.get("suffix_id", ""))):
			cats[id]["prefix_id"] = str(c["prefix_id"])
			cats[id]["suffix_id"] = str(c["suffix_id"])
			cats[id]["fixed"] = ""
		if names.ranks().has(str(c.get("rank", ""))):
			cats[id]["rank"] = str(c["rank"])


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

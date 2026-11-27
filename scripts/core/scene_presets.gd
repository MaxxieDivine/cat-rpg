extends RefCounted
## Scene select presets (data/scene_select.json): story points to jump to
## while testing. Plain data, no Nodes; game.gd jump_to() starts a new game
## and applies one, scripts/view/scene_select.gd is the menu.
## preload(), no class_name.
##
## A preset: {"id", "label", "base" (another preset id: its flags first),
## "flags" {flag: value}, "needs" {"hunger", "thirst"}, "time" (0..1),
## "story" (Story save data: border_patrols), "area", "spawn" or "pos" +
## "facing", "wake" (strings.json key: arrive through a fade with it)}.

const JsonData := preload("res://scripts/core/json_data.gd")
const PATH := "res://data/scene_select.json"

var presets: Array[Dictionary] = []


func _init(data: Dictionary = {}) -> void:
	if data.is_empty():
		data = JsonData.load_dict(PATH)
	for p: Dictionary in data.get("presets", []):
		presets.append(p)


func ids() -> Array[String]:
	var out: Array[String] = []
	for p in presets:
		out.append(str(p.get("id", "")))
	return out


func _raw(id: String) -> Dictionary:
	for p in presets:
		if str(p.get("id", "")) == id:
			return p
	return {}


## Preset `id` with its base chain merged in (flags: base first, then its
## own; every other field its own), or {} if unknown.
func resolved(id: String) -> Dictionary:
	var chain: Array[Dictionary] = []
	var at := _raw(id)
	while not at.is_empty() and chain.size() < 16:
		chain.push_front(at)
		var b := str(at.get("base", ""))
		at = _raw(b) if b != "" else {}
	if chain.is_empty():
		return {}
	var flags := {}
	for p in chain:
		flags.merge(p.get("flags", {}), true)
	var out: Dictionary = chain[-1].duplicate(true)
	out["flags"] = flags
	return out


## Writes a preset's flags into `state` (GameState's core, already reset).
static func apply_flags(p: Dictionary, state) -> void:
	state.apply_set(p.get("flags", {}))


## Problems with the presets (tests): duplicate or empty ids, unknown base,
## area (`area_ids`), flags or values (`state`), no spawn or pos.
func check(area_ids: Array, state) -> Array[String]:
	var errs: Array[String] = []
	var seen := {}
	for p in presets:
		var id := str(p.get("id", ""))
		if id == "" or seen.has(id):
			errs.append("preset '%s': empty or duplicate id" % id)
		seen[id] = true
		if str(p.get("label", "")).strip_edges() == "":
			errs.append("%s: no label" % id)
		var b := str(p.get("base", ""))
		if b != "" and _raw(b).is_empty():
			errs.append("%s: unknown base '%s'" % [id, b])
		if not area_ids.has(str(p.get("area", ""))):
			errs.append("%s: unknown area '%s'" % [id, p.get("area", "")])
		if not p.has("spawn") and not (p.get("pos") is Array and (p["pos"] as Array).size() == 2):
			errs.append("%s: needs a spawn or a pos" % id)
		var flags: Dictionary = p.get("flags", {})
		for f: String in flags:
			if not state.is_valid_value(f, flags[f]):
				errs.append("%s: bad flag %s = %s" % [id, f, flags[f]])
	return errs

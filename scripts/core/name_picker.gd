extends RefCounted
## What the Name Editor is showing: two wheels (prefix, suffix) over the word
## lists, the prefix category tab, the two Randomize locks and which wheel
## has keyboard / gamepad focus. Plain data, no Nodes, so it runs and tests
## headless; scripts/view/name_editor.gd draws it and sends it commands.
## preload() this script; no class_name.
##
## Wheels wrap around. The prefix wheel shows the words of the selected
## category tab (tabs() = prefix categories, then "All"); switching tabs
## keeps the current word when it is in the new tab, else jumps to the tab's
## first word. roll() rolls the unlocked parts (prefixes from the
## current tab) to an allowed name. Nothing here changes GameState: the view
## calls GameState.set_player_name() on Confirm.

const Names := preload("res://scripts/core/names.gd")
const ALL := "All"
const PREFIX := 0
const SUFFIX := 1

var names
## Index into tabs().
var category := 0
var prefix_list: Array[Dictionary] = []
var suffix_list: Array[Dictionary] = []
## Selected word on each wheel: [prefix index, suffix index].
var index: Array[int] = [0, 0]
## Randomize leaves a locked wheel alone: [prefix, suffix].
var locked: Array[bool] = [false, false]
## The wheel up / down moves (PREFIX or SUFFIX).
var focus := PREFIX
## The name when the editor opened (Cancel keeps it).
var start_prefix := ""
var start_suffix := ""


func _init(name_rules = null) -> void:
	names = name_rules if name_rules != null else Names.shared()
	suffix_list = names.suffixes.duplicate()
	category = tabs().size() - 1
	prefix_list = names.prefixes_in(ALL)


## Opens on the current name ("" suffix: the first suffix).
func open(prefix_id: String, suffix_id: String) -> void:
	start_prefix = prefix_id
	start_suffix = suffix_id
	locked = [false, false]
	focus = PREFIX
	category = tabs().size() - 1
	prefix_list = names.prefixes_in(ALL)
	index = [maxi(0, _find(prefix_list, prefix_id)), maxi(0, _find(suffix_list, suffix_id))]


## Category tabs over the prefix wheel: the prefix categories, then "All".
func tabs() -> Array[String]:
	var out: Array[String] = names.prefix_categories.duplicate()
	out.append(ALL)
	return out


func category_name() -> String:
	return tabs()[category]


## Switches the prefix wheel to tab `i` (wraps).
func set_category(i: int) -> void:
	var keep := prefix_id()
	category = posmod(i, tabs().size())
	prefix_list = names.prefixes_in(category_name())
	if prefix_list.is_empty():
		prefix_list = names.prefixes_in(ALL)
	index[PREFIX] = maxi(0, _find(prefix_list, keep))


func list(wheel: int) -> Array[Dictionary]:
	return prefix_list if wheel == PREFIX else suffix_list


## The word `offset` places from the selected one on `wheel` (wraps).
func word(wheel: int, offset: int = 0) -> Dictionary:
	var l := list(wheel)
	if l.is_empty():
		return {}
	return l[posmod(index[wheel] + offset, l.size())]


## Text of a word as it is shown on its wheel ("Fern", "whisker").
func word_text(wheel: int, offset: int = 0) -> String:
	var t := str(word(wheel, offset).get("text", ""))
	if t == "":
		return t
	return t.substr(0, 1).to_upper() + t.substr(1).to_lower() if wheel == PREFIX else t.to_lower()


func move(wheel: int, delta: int) -> void:
	var n := list(wheel).size()
	if n > 0:
		index[wheel] = posmod(index[wheel] + delta, n)


func toggle_lock(wheel: int) -> void:
	locked[wheel] = not locked[wheel]


func prefix_id() -> String:
	return str(word(PREFIX).get("id", ""))


func suffix_id() -> String:
	return str(word(SUFFIX).get("id", ""))


func full_name() -> String:
	return names.build(prefix_id(), suffix_id())


## Names.OK, or why the shown name can't be confirmed (Names.TAKEN / TRIPLE).
func status() -> String:
	return names.check(prefix_id(), suffix_id())


func can_confirm() -> bool:
	return status() == Names.OK


## Rolls the unlocked parts to a random allowed name. Returns true if the
## name changed.
func roll(rng: RandomNumberGenerator) -> bool:
	var before := [prefix_id(), suffix_id()]
	var r: Array[String] = names.roll(rng, prefix_id(), suffix_id(), locked[PREFIX], locked[SUFFIX], prefix_list, suffix_list)
	index[PREFIX] = maxi(0, _find(prefix_list, r[0]))
	index[SUFFIX] = maxi(0, _find(suffix_list, r[1]))
	return [prefix_id(), suffix_id()] != before


static func _find(words: Array[Dictionary], id: String) -> int:
	for i in words.size():
		if str(words[i].get("id", "")) == id:
			return i
	return -1

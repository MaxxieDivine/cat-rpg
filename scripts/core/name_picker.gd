extends RefCounted
## What the Name Editor is showing: which cat is being edited, and for that
## cat two wheels (prefix, suffix) over the word lists, the prefix category
## tab, the two Randomize locks, the rank, and which wheel has keyboard /
## gamepad focus. Plain data, no Nodes, so it runs and tests headless;
## scripts/view/name_editor.gd draws it and sends it commands.
## preload() this script; no class_name.
##
## Every cat keeps a draft while the editor is open (switching cats keeps
## them); changes() lists what Confirm should apply, Cancel drops them all.
## A cat whose current name can't be shown on the wheels (a fixed starting
## name like "Bram", or the start name "Fern" with no suffix) keeps that
## name until a wheel is touched. Names must differ from every other cat's
## (draft) name. Wheels wrap around; the prefix wheel shows the words of the
## selected category tab (tabs() = prefix categories, then "All").
## Nothing here changes GameState.

const Names := preload("res://scripts/core/names.gd")
const ALL := "All"
const PREFIX := 0
const SUFFIX := 1

var names
## Cat ids, in the editor's order, and the one shown.
var cats: Array[String] = []
var cat := 0
## The shown cat's draft (see _draft()):
## Index into tabs().
var category := 0
var prefix_list: Array[Dictionary] = []
var suffix_list: Array[Dictionary] = []
## Selected word on each wheel: [prefix index, suffix index].
var index: Array[int] = [0, 0]
## Randomize leaves a locked wheel alone: [prefix, suffix].
var locked: Array[bool] = [false, false]
## False while a name the wheels can't show is kept (`kept_name`).
var touched := true
var kept_name := ""
var rank := ""
## The wheel up / down moves (PREFIX or SUFFIX); shared by every cat.
var focus := PREFIX
## The shown cat's name when the editor opened.
var start_prefix := ""
var start_suffix := ""
var start_rank := ""
## Other cats' drafts: id -> saved fields.
var _drafts: Dictionary = {}


func _init(name_rules = null) -> void:
	names = name_rules if name_rules != null else Names.shared()
	suffix_list = names.suffixes.duplicate()
	category = tabs().size() - 1
	prefix_list = names.prefixes_in(ALL)


## Opens on every cat in GameState core `state`, showing `first` (default:
## the player).
func open_cats(state, first: String = "") -> void:
	cats = []
	_drafts = {}
	focus = PREFIX
	for id: String in names.cat_ids():
		if not state.has_cat(id):
			continue
		cats.append(id)
		var c: Dictionary = state.cats[id]
		_load_fresh(str(c["prefix_id"]), str(c["suffix_id"]), state.get_cat_name(id), str(c["rank"]))
		_drafts[id] = _save()
	cat = maxi(0, cats.find(first if first != "" else names.player_speaker()))
	_restore(_drafts.get(cat_id(), {}))


## Opens on one unnamed cat with this name (tests, tools).
func open(prefix_id: String, suffix_id: String, rank_id: String = "") -> void:
	cats = [""]
	_drafts = {}
	cat = 0
	focus = PREFIX
	_load_fresh(prefix_id, suffix_id, names.build(prefix_id, suffix_id), rank_id)


func _load_fresh(prefix_id: String, suffix_id: String, current_name: String, rank_id: String) -> void:
	start_prefix = prefix_id
	start_suffix = suffix_id
	start_rank = rank_id
	rank = rank_id
	locked = [false, false]
	category = tabs().size() - 1
	prefix_list = names.prefixes_in(ALL)
	var pi := _find(prefix_list, prefix_id)
	var si := _find(suffix_list, suffix_id)
	index = [maxi(0, pi), maxi(0, si)]
	# The wheels can only show word names.
	touched = pi >= 0 and si >= 0
	kept_name = current_name


func _save() -> Dictionary:
	return {
		"category": category, "index": index.duplicate(), "locked": locked.duplicate(),
		"touched": touched, "kept_name": kept_name, "rank": rank,
		"start_prefix": start_prefix, "start_suffix": start_suffix, "start_rank": start_rank,
	}


func _restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	category = int(d["category"])
	prefix_list = names.prefixes_in(category_name())
	if prefix_list.is_empty():
		prefix_list = names.prefixes_in(ALL)
	index = (d["index"] as Array[int]).duplicate()
	locked = (d["locked"] as Array[bool]).duplicate()
	touched = bool(d["touched"])
	kept_name = str(d["kept_name"])
	rank = str(d["rank"])
	start_prefix = str(d["start_prefix"])
	start_suffix = str(d["start_suffix"])
	start_rank = str(d["start_rank"])


# --- Cats


func cat_id() -> String:
	return cats[cat] if cat < cats.size() else ""


## Shows cat `i` (wraps), keeping the current cat's draft.
func set_cat(i: int) -> void:
	if cats.is_empty():
		return
	_drafts[cat_id()] = _save()
	cat = posmod(i, cats.size())
	_restore(_drafts.get(cat_id(), {}))


func next_cat(delta: int) -> void:
	set_cat(cat + delta)


# --- Ranks


func cycle_rank(delta: int) -> void:
	var rs: Array[String] = names.ranks()
	if rs.is_empty():
		return
	rank = rs[posmod(rs.find(rank) + delta, rs.size())]


# --- Wheels


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
	var at := _find(prefix_list, keep)
	if at < 0:
		touched = true
	index[PREFIX] = maxi(0, at)


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


## Puts the shown cat's wheels on these words (All tab; tests, tools).
func set_words(prefix_id: String, suffix_id: String) -> void:
	set_category(tabs().size() - 1)
	index = [maxi(0, _find(prefix_list, prefix_id)), maxi(0, _find(suffix_list, suffix_id))]
	touched = true


func move(wheel: int, delta: int) -> void:
	var n := list(wheel).size()
	if n > 0:
		index[wheel] = posmod(index[wheel] + delta, n)
		touched = true


func toggle_lock(wheel: int) -> void:
	locked[wheel] = not locked[wheel]


func prefix_id() -> String:
	return str(word(PREFIX).get("id", ""))


func suffix_id() -> String:
	return str(word(SUFFIX).get("id", ""))


## The shown cat's name: the wheels', or its kept name until they are used.
func full_name() -> String:
	return names.build(prefix_id(), suffix_id()) if touched else kept_name


## The other cats' (draft) names: the shown one may not use them.
func taken() -> Array[String]:
	var out: Array[String] = []
	for i in cats.size():
		if i != cat:
			out.append(_draft_name(_drafts.get(cats[i], {})))
	return out


func _draft_name(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	if not bool(d["touched"]):
		return str(d["kept_name"])
	var ids := _draft_ids(d)
	return names.build(ids[0], ids[1])


## A draft's wheel words: [prefix id, suffix id].
func _draft_ids(d: Dictionary) -> Array[String]:
	var plist: Array[Dictionary] = names.prefixes_in(tabs()[int(d["category"])])
	if plist.is_empty():
		plist = names.prefixes_in(ALL)
	var p: Dictionary = plist[posmod(int(d["index"][PREFIX]), plist.size())]
	var s: Dictionary = suffix_list[posmod(int(d["index"][SUFFIX]), suffix_list.size())]
	return [str(p["id"]), str(s["id"])]


## Names.OK, or why the shown name can't be confirmed (Names.TAKEN / TRIPLE).
## A kept name is always fine.
func status() -> String:
	if not touched:
		return Names.OK
	return names.check(prefix_id(), suffix_id(), taken())


## Every cat's draft can be saved.
func can_confirm() -> bool:
	return first_blocked() < 0


## Index of the first cat whose draft can't be saved, or -1.
func first_blocked() -> int:
	var here := cat
	var drafts := _all_drafts()
	for i in cats.size():
		if i == here:
			if status() != Names.OK:
				return i
			continue
		var d: Dictionary = drafts[i]
		if not bool(d["touched"]):
			continue
		var others: Array[String] = []
		for j in cats.size():
			if j != i:
				others.append(full_name() if j == here else _draft_name(drafts[j]))
		if names.check_name(_draft_name(d), others) != Names.OK:
			return i
	return -1


func _all_drafts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in cats.size():
		out.append(_save() if i == cat else _drafts.get(cats[i], {}))
	return out


## What Confirm applies: one entry per cat with a change,
## {"id", "rank", and "prefix_id" / "suffix_id" if renamed}.
func changes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var drafts := _all_drafts()
	for i in cats.size():
		var d: Dictionary = drafts[i]
		var e := {"id": cats[i], "rank": str(d["rank"])}
		var renamed := false
		if bool(d["touched"]):
			var ids := _draft_ids(d)
			var p := ids[0]
			var s := ids[1]
			if p != str(d["start_prefix"]) or s != str(d["start_suffix"]):
				e["prefix_id"] = p
				e["suffix_id"] = s
				renamed = true
		if renamed or str(d["rank"]) != str(d["start_rank"]):
			out.append(e)
	return out


## Rolls the unlocked parts to a random allowed name. Returns true if the
## name changed.
func roll(rng: RandomNumberGenerator) -> bool:
	var before := full_name()
	var r: Array[String] = names.roll(rng, prefix_id(), suffix_id(), locked[PREFIX], locked[SUFFIX], prefix_list, suffix_list, taken())
	index[PREFIX] = maxi(0, _find(prefix_list, r[0]))
	index[SUFFIX] = maxi(0, _find(suffix_list, r[1]))
	touched = true
	return full_name() != before


static func _find(words: Array[Dictionary], id: String) -> int:
	for i in words.size():
		if str(words[i].get("id", "")) == id:
			return i
	return -1

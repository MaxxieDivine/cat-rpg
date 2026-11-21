extends RefCounted
## The player's name: word lists and the rules for which names are allowed.
## Plain data, no Nodes; GameState (scripts/core/game_state.gd) holds the
## chosen prefix / suffix ids and asks this for the display name.
## preload() this script; no class_name.
##
## Data (edit these, not code):
##   data/names/prefixes.json   first parts ("Fern"), shown capitalised
##   data/names/suffixes.json   second parts ("whisker"), shown lowercase
##     each word: id, text, category, rarity ("common" / "rare"; unused yet)
##   data/names/blocklist.json  full names that can never be picked or rolled
##   data/names/naming.json     the name-giver, every cat's starting name
##                              and rank, the ranks and their symbols
## A name is allowed when it is not on the blocklist, is not another cat's
## current name (`taken`, from GameState) and has no letter three times in a
## row ("Mossstep"). Comparisons ignore letter case.

const JsonData := preload("res://scripts/core/json_data.gd")
const PREFIXES_PATH := "res://data/names/prefixes.json"
const SUFFIXES_PATH := "res://data/names/suffixes.json"
const BLOCKLIST_PATH := "res://data/names/blocklist.json"
const NAMING_PATH := "res://data/names/naming.json"
const SELF_PATH := "res://scripts/core/names.gd"

## Why a name can't be used ("" = allowed).
const OK := ""
const TAKEN := "taken"
const TRIPLE := "triple"
const UNKNOWN := "unknown"

var prefixes: Array[Dictionary] = []
var suffixes: Array[Dictionary] = []
var prefix_categories: Array[String] = []
var suffix_categories: Array[String] = []
## Lowercase full names that are never allowed (the blocklist).
var blocked: Dictionary = {}
var config: Dictionary = {}
var _prefix_by_id: Dictionary = {}
var _suffix_by_id: Dictionary = {}

static var _shared


## One loaded copy for everyone (the files don't change while running).
static func shared():
	if _shared == null:
		_shared = (load(SELF_PATH) as GDScript).new()
	return _shared


func _init(data: Dictionary = {}) -> void:
	var p: Dictionary = data.get("prefixes", JsonData.load_dict(PREFIXES_PATH))
	var s: Dictionary = data.get("suffixes", JsonData.load_dict(SUFFIXES_PATH))
	var b: Dictionary = data.get("blocklist", JsonData.load_dict(BLOCKLIST_PATH))
	config = data.get("naming", JsonData.load_dict(NAMING_PATH))
	for c in p.get("categories", []):
		prefix_categories.append(str(c))
	for c in s.get("categories", []):
		suffix_categories.append(str(c))
	for w: Dictionary in p.get("words", []):
		prefixes.append(w)
		_prefix_by_id[str(w.get("id", ""))] = w
	for w: Dictionary in s.get("words", []):
		suffixes.append(w)
		_suffix_by_id[str(w.get("id", ""))] = w
	for n in b.get("names", []):
		blocked[str(n).to_lower()] = true


## The speakers.json id whose name plate shows the player's name.
func player_speaker() -> String:
	return str(config.get("player_speaker", "fern"))


## The NPC id whose conversation is followed by the naming offer.
func giver() -> String:
	return str(config.get("giver", ""))


func giver_dialogue() -> String:
	return str(config.get("dialogue", ""))


## Every cat the Name Editor can rename, in order (the player first).
func cat_ids() -> Array[String]:
	var out: Array[String] = []
	var cats: Dictionary = config.get("cats", {})
	var player := player_speaker()
	if cats.has(player):
		out.append(player)
	for id: String in cats:
		if id != player:
			out.append(id)
	return out


## A cat's starting name and rank: {"prefix", "suffix"} word ids or a fixed
## {"name"}, and "rank".
func cat_start(id: String) -> Dictionary:
	return config.get("cats", {}).get(id, {})


## The player's start entry.
func start_name() -> Dictionary:
	return cat_start(player_speaker())


## Rank ids in the editor's order.
func ranks() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in config.get("ranks", []):
		out.append(str(r.get("id", "")))
	return out


func rank(id: String) -> Dictionary:
	for r: Dictionary in config.get("ranks", []):
		if str(r.get("id", "")) == id:
			return r
	return {}


func rank_label(id: String) -> String:
	return str(rank(id).get("label", id))


## The rank's symbol (an AssetCatalog key), "" for none.
func rank_icon(id: String) -> String:
	return str(rank(id).get("icon", ""))


## Placeholder ending for `rank` (data/names/naming.json "endings"; unused yet).
func rank_ending(rank_id: String) -> String:
	return str(config.get("endings", {}).get(rank_id, ""))


func prefix(id: String) -> Dictionary:
	return _prefix_by_id.get(id, {})


func suffix(id: String) -> Dictionary:
	return _suffix_by_id.get(id, {})


## Prefixes in `category` ("" or "All" = every one), in file order.
func prefixes_in(category: String) -> Array[Dictionary]:
	return _filter(prefixes, category)


func suffixes_in(category: String) -> Array[Dictionary]:
	return _filter(suffixes, category)


static func _filter(words: Array[Dictionary], category: String) -> Array[Dictionary]:
	if category == "" or category == "All":
		return words.duplicate()
	var out: Array[Dictionary] = []
	for w in words:
		if str(w.get("category", "")) == category:
			out.append(w)
	return out


## Prefix capitalised + suffix lowercase: "Fern" + "whisker" = "Fernwhisker".
## Unknown ids count as empty.
func build(prefix_id: String, suffix_id: String) -> String:
	var p := str(prefix(prefix_id).get("text", ""))
	var s := str(suffix(suffix_id).get("text", ""))
	if p != "":
		p = p.substr(0, 1).to_upper() + p.substr(1).to_lower()
	return p + s.to_lower()


## OK, or why this combination can't be used: UNKNOWN (no such word),
## TAKEN (blocklist, or one of `taken`: the other cats' names) or TRIPLE (a
## letter three times in a row).
func check(prefix_id: String, suffix_id: String, taken: Array = []) -> String:
	if prefix(prefix_id).is_empty() or suffix(suffix_id).is_empty():
		return UNKNOWN
	return check_name(build(prefix_id, suffix_id), taken)


## The same rules for a whole name.
func check_name(full: String, taken: Array = []) -> String:
	if full == "":
		return UNKNOWN
	var low := full.to_lower()
	if blocked.has(low):
		return TAKEN
	for t in taken:
		if str(t).to_lower() == low:
			return TAKEN
	if has_triple(full):
		return TRIPLE
	return OK


func is_allowed(prefix_id: String, suffix_id: String, taken: Array = []) -> bool:
	return check(prefix_id, suffix_id, taken) == OK


## True when some letter appears three times in a row (any case).
static func has_triple(s: String) -> bool:
	var low := s.to_lower()
	for i in range(2, low.length()):
		if low[i] == low[i - 1] and low[i] == low[i - 2]:
			return true
	return false


## A random allowed name: [prefix_id, suffix_id]. A locked part stays as it
## is; the unlocked parts are drawn from `prefix_pool` / `suffix_pool` (word
## lists; default all) and, when possible, the result differs from the
## current name. Returns the current ids when nothing allowed is left (e.g.
## both locked). `rng` is a RandomNumberGenerator; `taken` = names in use.
func roll(rng: RandomNumberGenerator, prefix_id: String, suffix_id: String, lock_prefix: bool, lock_suffix: bool,
		prefix_pool: Array[Dictionary] = [], suffix_pool: Array[Dictionary] = [], taken: Array = []) -> Array[String]:
	var ps: Array[String] = _ids(prefix_pool if not prefix_pool.is_empty() else prefixes)
	var ss: Array[String] = _ids(suffix_pool if not suffix_pool.is_empty() else suffixes)
	if lock_prefix:
		ps = [prefix_id]
	if lock_suffix:
		ss = [suffix_id]
	var options: Array = []
	var same: Array = []
	for p in ps:
		for s in ss:
			if not is_allowed(p, s, taken):
				continue
			if p == prefix_id and s == suffix_id:
				same.append([p, s])
			else:
				options.append([p, s])
	if options.is_empty():
		options = same
	if options.is_empty():
		return [prefix_id, suffix_id]
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	return [str(pick[0]), str(pick[1])]


static func _ids(words: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for w in words:
		out.append(str(w.get("id", "")))
	return out

extends "res://tests/test_base.gd"
## The player's name: word lists (data/names/), the rules (scripts/core/
## names.gd), GameState's name parts, {player_name} in dialogue, await
## nodes and the naming follow-up, and the Name Editor's headless state
## (scripts/core/name_picker.gd). Expected words come from the data files.

const Names := preload("res://scripts/core/names.gd")
const NamePicker := preload("res://scripts/core/name_picker.gd")
const GameState := preload("res://scripts/core/game_state.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const Validator := preload("res://scripts/core/dialogue_validator.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

const PREFIX_CATEGORIES := ["Plants", "Weather", "Animals", "Colors", "Earth and Water"]
const STARTER_PREFIXES := ["Fern", "Moss", "Birch", "Thistle", "Clover", "Briar", "Rain", "Frost", "Mist", "Dusk", "Ember", "Cloud", "Sparrow", "Wren", "Beetle", "Hare", "Russet", "Ash", "Amber", "Slate", "Pebble", "Brook", "Reed", "Hollow"]
const STARTER_SUFFIXES := ["whisker", "tail", "step", "fur", "pelt", "ear", "song", "shade", "leaf", "stripe", "eye", "foot", "drift", "wing", "spark"]

var names


func before_each() -> void:
	names = Names.new()


## A small rule set: "Sor" + "rel" would be the NPC Sorrel.
func _custom(block: Array = []) -> Object:
	return Names.new({
		"prefixes": {"categories": ["A"], "words": [
			{"id": "sor", "text": "Sor", "category": "A", "rarity": "common"},
			{"id": "moss", "text": "Moss", "category": "A", "rarity": "common"},
			{"id": "oak", "text": "Oak", "category": "A", "rarity": "common"}]},
		"suffixes": {"categories": ["B"], "words": [
			{"id": "rel", "text": "rel", "category": "B", "rarity": "common"},
			{"id": "step", "text": "step", "category": "B", "rarity": "common"},
			{"id": "tail", "text": "tail", "category": "B", "rarity": "common"}]},
		"blocklist": {"names": block},
	})


# --- Word lists


func test_word_lists_are_well_formed() -> void:
	for pair in [[names.prefixes, names.prefix_categories, "prefix"], [names.suffixes, names.suffix_categories, "suffix"]]:
		var seen := {}
		for w: Dictionary in pair[0]:
			for k in ["id", "text", "category", "rarity"]:
				check(w.has(k), "%s %s has %s" % [pair[2], w.get("id", "?"), k])
			var id := str(w.get("id", ""))
			check(not seen.has(id), "%s id '%s' is unique" % [pair[2], id])
			seen[id] = true
			check(id == id.to_lower() and id != "", "%s id '%s' is lowercase" % [pair[2], id])
			check((pair[1] as Array).has(str(w.get("category", ""))), "%s %s: category '%s' is listed" % [pair[2], id, w.get("category")])
			check(["common", "rare"].has(str(w.get("rarity", ""))), "%s %s: rarity common or rare" % [pair[2], id])
	check_eq(names.prefix_categories, PREFIX_CATEGORIES as Array[String], "prefix categories")
	check(names.suffixes_in("All").size() == names.suffixes.size(), "All = every suffix")


func test_starter_words_are_there() -> void:
	var p: Array = names.prefixes.map(func(w): return w["text"])
	var s: Array = names.suffixes.map(func(w): return w["text"])
	for w in STARTER_PREFIXES:
		check(p.has(w), "prefix %s" % w)
	for w in STARTER_SUFFIXES:
		check(s.has(w), "suffix %s" % w)


func test_blocklist_file_is_a_list_of_names() -> void:
	var b := JsonData.load_dict(Names.BLOCKLIST_PATH)
	check(b.get("names") is Array, "blocklist.json has a names list")


# --- Rules


func test_build_capitalises_the_prefix_and_lowercases_the_suffix() -> void:
	check_eq(names.build("fern", "whisker"), "Fernwhisker", "Fern + whisker")
	check_eq(names.build("ash", "eye"), "Asheye", "Ash + eye")
	check_eq(names.build("fern", ""), "Fern", "no suffix: just the prefix")


func test_triple_letters_are_skipped() -> void:
	check_eq(names.check("moss", "step"), Names.TRIPLE, "Mossstep")
	check_eq(names.check("moss", "shade"), Names.TRIPLE, "Mossshade")
	check_eq(names.check("moss", "tail"), Names.OK, "Mosstail is fine (two s)")
	check(Names.has_triple("AAa"), "any case")
	check(not Names.has_triple("Fernwhisker"), "no triple")


func test_other_cats_names_and_the_blocklist_are_taken() -> void:
	var c = _custom(["Oaktail"])
	check_eq(c.check("sor", "rel", ["Sorrel", "Bram"]), Names.TAKEN, "Sorrel is another cat's name")
	check_eq(c.check("sor", "rel"), Names.OK, "free when no cat has it")
	check_eq(c.check("oak", "tail"), Names.TAKEN, "Oaktail is on the blocklist")
	check_eq(c.check_name("OAKTAIL"), Names.TAKEN, "any letter case")
	check_eq(c.check_name("sorrel", ["Sorrel"]), Names.TAKEN, "taken names in any case")
	check_eq(c.check("oak", "step"), Names.OK, "Oakstep is free")
	check_eq(c.check("oak", "nope"), Names.UNKNOWN, "unknown word")
	# In GameState: no two cats share a name.
	var s = GameState.new()
	check(s.names_taken_by_others("fern").has("Bram"), "Bram's name is taken for Fern")
	check(not s.names_taken_by_others("fern").has(s.get_player_name()), "but not her own")
	check(s.set_cat_name("bram", "birch", "song"), "Bram can become Birchsong")
	check(not s.set_cat_name("fern", "birch", "song"), "then Fern can't")
	check(not s.set_cat_name("cow", "birch", "pelt"), "unknown cats can't be renamed")


func test_roll_only_gives_allowed_names_and_respects_locks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 300:
		var r: Array[String] = names.roll(rng, "fern", "whisker", false, false)
		check(names.is_allowed(r[0], r[1]), "roll %d: %s is allowed" % [i, names.build(r[0], r[1])])
	for i in 50:
		var r: Array[String] = names.roll(rng, "moss", "tail", true, false)
		check_eq(r[0], "moss", "locked prefix stays")
		check(names.is_allowed(r[0], r[1]), "allowed with a locked prefix")
	for i in 50:
		var r: Array[String] = names.roll(rng, "fern", "tail", false, true)
		check_eq(r[1], "tail", "locked suffix stays")
	check_eq(names.roll(rng, "fern", "tail", true, true), ["fern", "tail"] as Array[String], "both locked: unchanged")
	var c = _custom(["Oakstep", "Oaktail"])
	for i in 30:
		var r: Array[String] = c.roll(rng, "oak", "rel", true, false)
		check_eq(r, ["oak", "rel"] as Array[String], "the only allowed Oak name")


func test_roll_changes_the_name_when_it_can() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		var r: Array[String] = names.roll(rng, "fern", "tail", false, false)
		check(r != (["fern", "tail"] as Array[String]), "a new name each roll")


# --- GameState


func test_game_state_name_parts() -> void:
	var s = GameState.new()
	var start: Dictionary = names.start_name()
	check_eq(s.prefix_id, str(start["prefix"]), "start prefix")
	check_eq(s.suffix_id, str(start["suffix"]), "start suffix")
	check_eq(s.get_player_name(), names.build(str(start["prefix"]), str(start["suffix"])), "start name")
	check(names.ranks().has(s.rank), "start rank '%s' is a known rank" % s.rank)
	check(s.set_player_name("birch", "song"), "Birchsong can be set")
	check_eq(s.get_player_name(), "Birchsong", "the new name")
	check(not s.set_player_name("moss", "step"), "Mossstep is refused")
	check_eq(s.get_player_name(), "Birchsong", "refusing keeps the old name")
	check_eq(s.format_text("Hi, {player_name}!"), "Hi, Birchsong!", "{player_name}")
	var saved: Dictionary = s.save_data()
	var fern_saved: Dictionary = saved["cats"]["fern"]
	check_eq([fern_saved["prefix_id"], fern_saved["suffix_id"], fern_saved["rank"]], ["birch", "song", s.rank], "save data holds the two parts and the rank")
	check(saved["cats"].has("bram"), "and every other cat")
	s.reset()
	check_eq(s.get_player_name(), names.build(str(start["prefix"]), str(start["suffix"])), "a new game: the start name")
	s.load_save_data(saved)
	check_eq(s.get_player_name(), "Birchsong", "loaded back")


func test_ranks_and_endings_live_in_data() -> void:
	var cfg := JsonData.load_dict(Names.NAMING_PATH)
	var ids: Array[String] = names.ranks()
	for r in ["kit", "apprentice", "warrior", "medicine", "deputy", "leader"]:
		check(ids.has(r), "rank %s" % r)
		var key: String = names.rank_icon(r)
		check(key != "" and ResourceLoader.exists(JsonData.load_dict("res://data/assets.json").get(key, "")), "%s has a symbol (%s)" % [r, key])
		check((cfg["endings"] as Dictionary).has(r), "an ending slot for %s" % r)
		check(names.rank_label(r) != "", "%s has a label" % r)
	check_eq(names.rank_icon("none"), "", "no rank: no symbol")


func test_every_cat_has_a_name_and_a_rank() -> void:
	var s = GameState.new()
	var world := JsonData.load_dict("res://data/world.json")
	check_eq(names.cat_ids()[0], names.player_speaker(), "the player comes first")
	for npc: Dictionary in world["npcs"]:
		check(s.has_cat(npc["id"]), "%s can be renamed" % npc["id"])
	for id in names.cat_ids():
		check(s.get_cat_name(id) != "", "%s has a name" % id)
		check(names.ranks().has(s.get_cat_rank(id)), "%s has a known rank" % id)
	check_eq(s.get_cat_name("bram"), "Bram", "Bram keeps his name until renamed")
	check(s.set_cat_rank("bram", "leader"), "Bram can lead")
	check_eq(s.get_cat_rank("bram"), "leader", "rank set")
	check(not s.set_cat_rank("bram", "king"), "unknown ranks refused")
	check(s.set_cat_name("sorrel", "ash", "pelt"), "Sorrel renamed")
	check_eq(s.format_text("Ask {name_sorrel}, {player_name}."), "Ask Ashpelt, Fern.", "{name_<cat>} placeholders")
	for id in names.cat_ids():
		check(s.placeholders().has("name_" + id), "{name_%s} is known" % id)


func test_the_name_giver_is_a_camp_npc() -> void:
	var giver: String = names.giver()
	var world := JsonData.load_dict("res://data/world.json")
	check(world["npcs"].any(func(n): return n["id"] == giver), "giver '%s' is in world.json" % giver)
	var conv := JsonData.load_dict(names.giver_dialogue())
	var speakers := {}
	for id: String in conv["nodes"]:
		if conv["nodes"][id].has("speaker"):
			speakers[conv["nodes"][id]["speaker"]] = true
	check(speakers.has(giver), "the naming lines are spoken by the giver")
	for sp in speakers:
		check(sp == giver or sp == names.player_speaker(), "naming speakers: giver or player only (%s)" % sp)


# --- Dialogue: {player_name}, await, follow-up


func test_dialogue_fills_in_the_player_name() -> void:
	var s = GameState.new()
	s.set_player_name("wren", "song")
	var d = Dialogue.new(s)
	var ev: Dictionary = d.start({"start": "a", "nodes": {
		"a": {"speaker": "bram", "text": "Hi, {player_name}.", "choices": [{"text": "I'm {player_name}!", "next": "b"}]},
		"b": {"speaker": "bram", "text": "ok", "end": true}}})
	check_eq(ev["text"], "Hi, Wrensong.", "line text")
	check_eq(ev["choices"], ["I'm Wrensong!"] as Array[String], "choice text")


func test_await_node_waits_and_resumes() -> void:
	var s = GameState.new()
	var d = Dialogue.new(s)
	var conv := {"start": "a", "nodes": {
		"a": {"speaker": "sorrel", "text": "Well?", "next": "w"},
		"w": {"await": "name_editor", "next": "yes", "cancel": "no"},
		"yes": {"speaker": "sorrel", "text": "Yes, {player_name}.", "end": true},
		"no": {"speaker": "sorrel", "text": "No.", "end": true}}}
	d.start(conv)
	var ev: Dictionary = d.advance()
	check_eq(ev["type"], "await", "await event")
	check_eq(ev["await"], "name_editor", "which screen")
	check(d.is_waiting(), "waiting")
	check_eq(d.advance()["type"], "await", "advance does nothing while waiting")
	s.set_player_name("hare", "foot")
	ev = d.resume(true)
	check_eq(ev["node"], "yes", "confirmed -> next")
	check_eq(ev["text"], "Yes, Harefoot.", "with the new name")
	d.start(conv)
	d.advance()
	check_eq(d.resume(false)["node"], "no", "cancelled -> cancel")


func test_follow_up_conversation_runs_after_the_first() -> void:
	var d = Dialogue.new(GameState.new())
	var one := {"start": "a", "nodes": {"a": {"speaker": "sorrel", "text": "One.", "end": true}}}
	var two := {"start": "b", "nodes": {"b": {"speaker": "sorrel", "text": "Two.", "end": true}}}
	var ev: Dictionary = d.start(one, "one", two, "two")
	check_eq([ev["conversation"], ev["node"]], ["one", "a"], "first conversation")
	ev = d.advance()
	check_eq([ev["conversation"], ev["node"]], ["two", "b"], "then the follow-up")
	check_eq(d.advance()["type"], "end", "then the end")


func test_naming_conversation_paths() -> void:
	var s = GameState.new()
	var d = Dialogue.new(s)
	var conv := JsonData.load_dict(names.giver_dialogue())
	var ev: Dictionary = d.start(conv)
	check_eq(ev["choices"].size(), 2, "two choices")
	check_eq(ev["choices"][0], "Can I have a new name?", "ask")
	check_eq(ev["choices"][1], "Never mind.", "never mind")
	var guard := 0
	ev = d.choose(0)
	while ev["type"] == "line" and guard < 10:
		guard += 1
		ev = d.advance()
	check_eq(ev["type"], "await", "asking opens the editor")
	s.set_player_name("frost", "pelt")
	ev = d.resume(true)
	check(str(ev["text"]).contains("Frostpelt"), "the reply uses the new name (%s)" % ev["text"])
	d.start(conv)
	ev = d.choose(1)
	while ev["type"] == "line":
		ev = d.advance()
	check_eq(ev["type"], "end", "never mind ends it")


func test_validator_knows_await_and_placeholders() -> void:
	var bad_await := {"start": "w", "nodes": {"w": {"await": "name_editor", "next": "e"}, "e": {"speaker": "sorrel", "text": "x", "end": true}}}
	check(Validator.validate(bad_await).any(func(e: String) -> bool: return e.contains("cancel")), "await without cancel")
	var bad_screen := {"start": "w", "nodes": {"w": {"await": "nope", "next": "e", "cancel": "e"}, "e": {"speaker": "sorrel", "text": "x", "end": true}}}
	check(Validator.validate(bad_screen).any(func(e: String) -> bool: return e.contains("unknown screen")), "unknown screen")
	var bad_ph := {"start": "e", "nodes": {"e": {"speaker": "sorrel", "text": "Hi {player}", "end": true}}}
	check(Validator.validate(bad_ph).any(func(e: String) -> bool: return e.contains("placeholder")), "unknown placeholder")
	var bad_cat := {"start": "e", "nodes": {"e": {"speaker": "sorrel", "text": "Hi {name_cow}", "end": true}}}
	check(Validator.validate(bad_cat).any(func(e: String) -> bool: return e.contains("placeholder")), "{name_cow} is no cat")
	var good := {"start": "w", "nodes": {"w": {"await": "name_editor", "next": "e", "cancel": "e"}, "e": {"speaker": "sorrel", "text": "Hi {player_name}, ask {name_wick}", "end": true}}}
	check_eq(Validator.validate(good), [] as Array[String], "a good await node")


# --- Name Editor state


func test_picker_wheels_tabs_and_locks() -> void:
	var p = NamePicker.new()
	p.open("fern", "")
	check_eq(p.prefix_id(), "fern", "opens on the current prefix")
	check_eq(p.suffix_id(), str(names.suffixes[0]["id"]), "no suffix yet: the first one")
	check_eq(p.tabs()[-1], "All", "All is the last tab")
	check_eq(p.tabs().slice(0, -1), PREFIX_CATEGORIES as Array[String], "tabs follow the categories")
	check_eq(p.category_name(), "All", "opens on All")
	p.move(NamePicker.PREFIX, -1)
	check_eq(p.prefix_id(), str(names.prefixes[-1]["id"]), "the wheel wraps")
	p.move(NamePicker.PREFIX, 1)
	check_eq(p.word_text(NamePicker.PREFIX, 1), str(names.prefixes[1]["text"]), "the next word")
	p.set_category(PREFIX_CATEGORIES.find("Plants"))
	check_eq(p.prefix_id(), "fern", "Fern is a plant: kept")
	check(p.prefix_list.all(func(w): return w["category"] == "Plants"), "only plants")
	p.set_category(PREFIX_CATEGORIES.find("Weather"))
	check_eq(p.prefix_id(), str(names.prefixes_in("Weather")[0]["id"]), "jumps to the first weather word")
	p.move(NamePicker.PREFIX, p.prefix_list.size())
	check_eq(p.prefix_id(), str(names.prefixes_in("Weather")[0]["id"]), "wraps within the tab")
	# Locks and rolls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	p.set_category(p.tabs().size() - 1)
	p.toggle_lock(NamePicker.SUFFIX)
	var suf := p.suffix_id()
	for i in 30:
		p.roll(rng)
		check_eq(p.suffix_id(), suf, "locked suffix stays")
		check(p.can_confirm(), "rolled names are allowed")
	p.toggle_lock(NamePicker.SUFFIX)
	p.toggle_lock(NamePicker.PREFIX)
	var pre := p.prefix_id()
	for i in 30:
		p.roll(rng)
		check_eq(p.prefix_id(), pre, "locked prefix stays")
	# Blocked.
	p.open("moss", "step")
	check_eq(p.status(), Names.TRIPLE, "Mossstep shown as blocked")
	check(not p.can_confirm(), "can't confirm it")
	check_eq(p.start_prefix, "moss", "remembers where it opened")


func test_picker_keeps_a_draft_per_cat() -> void:
	var s = GameState.new()
	var p = NamePicker.new()
	p.open_cats(s)
	check_eq(p.cat_id(), names.player_speaker(), "opens on the player")
	check_eq(p.cats, names.cat_ids(), "every cat")
	check_eq(p.full_name(), "Fern", "Fern's name until a wheel moves")
	check(p.changes().is_empty(), "nothing changed yet")
	p.set_words("birch", "song")
	p.next_cat(1)
	check_eq(p.cat_id(), "bram", "next cat")
	check_eq(p.full_name(), "Bram", "Bram keeps his name until a wheel moves")
	check_eq(p.rank, "warrior", "Bram's rank")
	p.cycle_rank(1)
	check_eq(p.rank, names.ranks()[names.ranks().find("warrior") + 1], "the next rank")
	p.set_words("birch", "song")
	check_eq(p.status(), Names.TAKEN, "Fern's draft name is taken for Bram")
	check(not p.can_confirm(), "can't confirm two Birchsongs")
	p.set_words("frost", "ear")
	check(p.can_confirm(), "Frostear is fine")
	p.next_cat(-1)
	check_eq(p.full_name(), "Birchsong", "Fern's draft is kept")
	var ch: Array[Dictionary] = p.changes()
	check_eq(ch.size(), 2, "two cats changed (%s)" % [ch])
	var by_id := {}
	for c in ch:
		by_id[c["id"]] = c
	check_eq([by_id["fern"].get("prefix_id"), by_id["fern"].get("suffix_id")], ["birch", "song"], "Fern renamed")
	check_eq([by_id["bram"].get("prefix_id"), by_id["bram"].get("suffix_id"), by_id["bram"]["rank"]], ["frost", "ear", p.names.ranks()[p.names.ranks().find("warrior") + 1]], "Bram renamed and re-ranked")
	# A rank-only change.
	p.open_cats(s, "wick")
	p.cycle_rank(1)
	ch = p.changes()
	check(ch.size() == 1 and ch[0]["id"] == "wick" and not ch[0].has("prefix_id"), "only Wick's rank (%s)" % [ch])
	# Rolls avoid other cats' names.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		p.roll(rng)
		check(p.status() == Names.OK, "rolled names are free")

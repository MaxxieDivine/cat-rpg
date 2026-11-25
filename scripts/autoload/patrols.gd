extends Node
## Autoload "Patrols": the patrol the deputy sent Fern on (or is offering).
## A thin Node around scripts/core/patrol.gd. It keeps GameState's patrol
## flags (the deputy's conversation branches on them) and {patrol_mates} in
## step, and emits `changed` whenever the patrol does. game.gd calls
## prepare_offer() as the deputy's conversation starts and after_talk() when
## it ends (the conversation's choices set the flag `patrol` to "accepted",
## "declined" or "reported"); left_camp(), delivered() and mark() as those
## things happen. The game screen calls reset() on a new game.

signal changed

const Patrol := preload("res://scripts/core/patrol.gd")
const Areas := preload("res://scripts/core/areas.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

var patrol := Patrol.new()
## area id -> [scent spot id, ...] (the areas' "scent_spots"), cached.
var _spots: Dictionary = {}


func reset() -> void:
	patrol.reset()
	sync()


func deputy() -> String:
	return patrol.deputy()


func config() -> Dictionary:
	return patrol.config


func is_active() -> bool:
	return patrol.is_active()


func phase() -> String:
	return patrol.phase()


func mates() -> Array:
	return patrol.mates()


## Whether cat `id` could be sent on a patrol (its rank allows it).
func could_go(id: String) -> bool:
	return patrol.could_go(id, GameState.get_cat_rank(id))


## On the running patrol, or picked in the offer being made right now.
func picked(id: String) -> bool:
	return patrol.picked(id, DialogueManager.is_active())


## The deputy's conversation is starting: pick a patrol if there is none.
## None while the story needs Fern elsewhere (Story.blocks_patrols()), and
## never with a cat the story has taken away (Story.absent()).
func prepare_offer() -> void:
	if Story.blocks_patrols() and not patrol.is_active():
		patrol.decline()
		sync()
		return
	var ranks := {}
	for id: String in GameState.state.cats:
		if not Story.absent(id):
			ranks[id] = GameState.get_cat_rank(id)
	patrol.roll_offer(patrol.candidates(ranks), spots())
	sync()


## Every area's scent spot ids (area id -> [id, ...]).
func spots() -> Dictionary:
	if _spots.is_empty():
		var areas := Areas.new()
		for a in areas.ids():
			var ids: Array = []
			for s: Dictionary in areas.area_data(a).get("scent_spots", []):
				ids.append(str(s.get("id", "")))
			if not ids.is_empty():
				_spots[a] = ids
	return _spots


## The deputy's conversation ended: act on what Fern chose.
func after_talk() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	match GameState.get_flag("patrol"):
		"accepted":
			ev = patrol.accept()
		"declined":
			patrol.decline()
		"reported":
			ev = patrol.report()
	sync()
	return ev


func left_camp() -> Array[Dictionary]:
	return _after(patrol.left_camp())


func delivered() -> Array[Dictionary]:
	return _after(patrol.delivered())


func mark(area: String, id: String) -> Array[Dictionary]:
	return _after(patrol.mark(area, id))


func needs_mark(area: String, id: String) -> bool:
	return patrol.needs_mark(area, id)


func _after(ev: Array[Dictionary]) -> Array[Dictionary]:
	if not ev.is_empty():
		sync()
	return ev


## The goal line for the hud ("Scent marks: 1 / 4"), or "".
func goal_text() -> String:
	var g: Dictionary = patrol.goal()
	if g.is_empty():
		return ""
	return GameState.format_text(GameStrings.text(g["key"])).replace("{n}", str(g["n"])).replace("{of}", str(g["of"]))


## "Bram", "Bram and Wick" (current names).
func mates_text(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		names.append(GameState.get_cat_name(str(id)))
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " " + GameStrings.text("patrol.and") + " " + names[names.size() - 1]


## Copies the patrol into GameState's flags and {patrol_mates}.
func sync() -> void:
	var f: Dictionary = patrol.dialogue_flags()
	for k: String in f:
		if f[k] == null:
			GameState.state.clear_flag(k)
		else:
			GameState.set_flag(k, f[k])
	var src: Dictionary = patrol.active if patrol.is_active() else patrol.offer
	GameState.state.set_text_var("patrol_mates", mates_text(src.get("mates", [])))
	changed.emit()

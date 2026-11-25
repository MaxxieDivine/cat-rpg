extends RefCounted
## Story beats: plain data, no Nodes; the Story autoload
## (scripts/autoload/story.gd) holds one. Settings: data/story.json. The
## story's state is GameState flags (data/state.json), so dialogue branches
## on it and it is saved with the flags; this class only adds the counts
## the flags can't hold (border patrols marked) and the rules that read them.
## preload(), no class_name.
##
## "The rogue and the missing Wick", Part A:
##   border_marked()  a border patrol is fully marked: once enough border
##                    patrols have been, Wick goes missing (wick_missing),
##                    unless he is out on that patrol
##   (the deputy's report then tells the news: rogue_news, data/dialogue/rook.json)
##   absent()         Wick isn't in any area while he is missing
##   goal_key()       "Investigate the rogue scent by the river."
##   blocks_patrols() no patrol offers while the investigation runs

const JsonData := preload("res://scripts/core/json_data.gd")
const CONFIG_PATH := "res://data/story.json"

var config: Dictionary = {}
## Border patrols marked in full this game (counted when the last spot is
## marked, so the one that reaches the deputy counts).
var border_patrols := 0


func _init(cfg: Dictionary = {}) -> void:
	config = cfg if not cfg.is_empty() else JsonData.load_dict(CONFIG_PATH)
	reset()


func reset() -> void:
	border_patrols = 0


func rogue() -> Dictionary:
	return config.get("rogue", {})


## The cat who goes missing ("wick").
func missing_cat() -> String:
	return str(rogue().get("missing", "wick"))


## A border patrol with `mates` has marked its last spot. Returns true when
## this makes the missing cat go missing (and sets wick_missing in `state`,
## a scripts/core/game_state.gd).
func border_marked(state, mates: Array) -> bool:
	border_patrols += 1
	if state.get_flag("wick_missing"):
		return false
	if border_patrols < int(rogue().get("after_border_patrols", 1)):
		return false
	# He can't go missing from a patrol Fern is leading: wait for the next.
	if mates.has(missing_cat()):
		return false
	state.set_flag("wick_missing", true)
	return true


## Whether cat `id` is away from every area now.
func absent(state, id: String) -> bool:
	return id == missing_cat() and bool(state.get_flag("wick_missing"))


## The rogue investigation is running (the deputy told the news).
func investigating(state) -> bool:
	return bool(state.get_flag("rogue_news"))


## The deputy hands out no patrols while the story needs Fern elsewhere.
func blocks_patrols(state) -> bool:
	return investigating(state)


## The story goal for the hud (a strings.json key), or "".
func goal_key(state) -> String:
	if investigating(state):
		return str(rogue().get("goal_investigate", "story.goal_investigate"))
	return ""


## What a save file keeps of the story beyond the flags.
## TODO(save): the save milestone (1.5) writes this next to
## GameState.save_data() and calls load_save_data() on load.
func save_data() -> Dictionary:
	return {"border_patrols": border_patrols}


func load_save_data(d: Dictionary) -> void:
	border_patrols = maxi(0, int(d.get("border_patrols", 0)))

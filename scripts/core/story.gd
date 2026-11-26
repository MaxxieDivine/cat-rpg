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
##
## Part B, the rogue by the river (data/dialogue/slate.json):
##   the rogue (rogue.npc) stands in rogue.area while rogue_news is set and
##   rogue_met isn't (his layout entry's "when"); talking sets rogue_choice
##   and rogue_met; leave_plan() says how he goes; the story exit
##   (rogue.exit, "when" rogue_met) is open from then on
##   trail() / way_mark() the scent trail (threaten) or the arrow (bribe)
##   goal_key()       "Follow the rogue."
##
## Part C, the rogue camp (rogue.camp_area, data/rogue_camp.json):
##   Wick is there (absent() everywhere else); hiding behind the log
##   (can_hide()) plays the cutscene (rogue.cutscene) that sets
##   rogue_camp_found; goal_key() "Get back to camp and warn the deputy.";
##   telling the deputy sets rogue_warned (data/dialogue/rook.json): the
##   investigation is over and patrols come back. Wick stays where he is.

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


## Whether cat `id` is away from area `area` now (the missing cat is only
## in the rogue camp).
func absent(state, id: String, area: String = "") -> bool:
	if area != "" and area == camp_area():
		return false
	return id == missing_cat() and bool(state.get_flag("wick_missing"))


## The rogue investigation is running (the deputy told the news, and
## hasn't been warned about the rogue camp yet).
func investigating(state) -> bool:
	return bool(state.get_flag("rogue_news")) and not bool(state.get_flag("rogue_warned"))


## The rogue camp's area id.
func camp_area() -> String:
	return str(rogue().get("camp_area", "rogue_camp"))


## The cutscene file played from hiding.
func cutscene_path() -> String:
	return str(rogue().get("cutscene", ""))


## Hiding behind the log plays the cutscene (once: until the camp is found).
func can_hide(state) -> bool:
	return bool(state.get_flag("rogue_met")) and not bool(state.get_flag("rogue_camp_found"))


## The deputy hands out no patrols while the story needs Fern elsewhere.
func blocks_patrols(state) -> bool:
	return investigating(state)


## The story goal for the hud (a strings.json key), or "".
func goal_key(state) -> String:
	if bool(state.get_flag("rogue_warned")):
		return ""
	if bool(state.get_flag("rogue_camp_found")):
		return str(rogue().get("goal_warn", "story.goal_warn"))
	if bool(state.get_flag("rogue_met")):
		return str(rogue().get("goal_follow", "story.goal_follow"))
	if investigating(state):
		return str(rogue().get("goal_investigate", "story.goal_investigate"))
	return ""


## The rogue's id ("slate").
func rogue_npc() -> String:
	return str(rogue().get("npc", "slate"))


## The rogue's area ("hunting_grounds_2").
func rogue_area() -> String:
	return str(rogue().get("area", ""))


## Where the rogue stands, then the way he leaves (world px).
func rogue_route() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in rogue().get("route", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## How the rogue goes once Fern is done talking (choice = rogue_choice):
## {"mode": "walk" / "run" / "stay", "speed", "route" (without where he
## stands)}. "stay" (bribed): he keeps eating the prey.
func leave_plan(choice: Variant) -> Dictionary:
	var route := rogue_route()
	route = route.slice(1)
	match choice:
		"threaten":
			return {"mode": "run", "speed": float(rogue().get("run_speed", 110)), "route": route}
		"bribe":
			return {"mode": "stay", "speed": 0.0, "route": []}
	return {"mode": "walk", "speed": float(rogue().get("walk_speed", 24)), "route": route}


## The scent trail he left when he bolted: points every trail_every px
## along his route, inside the area (`area_size`). Empty unless Fern
## threatened him and the trail is still worth following.
func trail(state, area_size: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not following(state) or state.get_flag("rogue_choice") != "threaten":
		return out
	var route := rogue_route()
	var every := float(rogue().get("trail_every", 34))
	var left := every * 0.6
	for i in range(1, route.size()):
		var a := route[i - 1]
		var b := route[i]
		var seg := a.distance_to(b)
		var d := left
		while d <= seg:
			var p := a.lerp(b, d / seg)
			if p.x > 8.0 and p.x < area_size.x - 8.0 and p.y > 8.0 and p.y < area_size.y - 8.0:
				out.append(p)
			d += every
		left = d - seg
	return out


## Where the arrow pointing out of the territory goes (bribed), or INF.
func way_mark(state) -> Vector2:
	if not following(state) or state.get_flag("rogue_choice") != "bribe":
		return Vector2.INF
	var p: Array = rogue().get("way_mark", [])
	return Vector2(float(p[0]), float(p[1])) if p.size() >= 2 else Vector2.INF


## Fern met the rogue and should follow him out of the territory (until
## she has found the rogue camp).
func following(state) -> bool:
	return bool(state.get_flag("rogue_met")) and not bool(state.get_flag("rogue_camp_found"))


## What a save file keeps of the story beyond the flags.
## TODO(save): the save milestone (1.5) writes this next to
## GameState.save_data() and calls load_save_data() on load.
func save_data() -> Dictionary:
	return {"border_patrols": border_patrols}


func load_save_data(d: Dictionary) -> void:
	border_patrols = maxi(0, int(d.get("border_patrols", 0)))

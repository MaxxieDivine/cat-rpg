extends "res://tests/test_base.gd"
## Camp landmarks (C.1): the Leader's Rock with the leader on top, the
## leader's den mouth, the deputy beside the rock, and the markers for
## Clan meetings. Core only (scripts/core/world.gd); expected values come
## from data/world.json and data/strings.json.

const World := preload("res://scripts/core/world.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const Dialogue := preload("res://scripts/core/dialogue.gd")
const GameStateCore := preload("res://scripts/core/game_state.gd")

var wdata: Dictionary
var strings: Dictionary
var w


func before_each() -> void:
	wdata = JsonData.load_dict("res://data/world.json")
	strings = JsonData.load_dict("res://data/strings.json")
	w = World.new(wdata)


func _rock() -> Dictionary:
	for p: Dictionary in w.props:
		if p["type"] == "leaders_rock":
			return p
	return {}


## The leader: the cat standing on the rock (perched).
func _leader() -> Dictionary:
	for npc: Dictionary in w.npcs:
		if npc["perch"] > 0.0:
			return npc
	return {}


## The deputy: the cat sitting at the DeputySpot marker.
func _deputy() -> Dictionary:
	for npc: Dictionary in w.npcs:
		if w.markers.has("DeputySpot") and npc["pos"] == w.markers["DeputySpot"]:
			return npc
	return {}


func _run(seconds: float, move: Vector2) -> void:
	var t := 0.0
	while t < seconds:
		w.step(1.0 / 60.0, move, false)
		t += 1.0 / 60.0


## Walks Fern towards `to` (feet) for up to `seconds`; true if she got
## within 2 px (nothing snagged her).
func _walk_to(to: Vector2, seconds: float = 6.0) -> bool:
	var t := 0.0
	while t < seconds and w.player_pos.distance_to(to) > 2.0:
		var d: Vector2 = to - w.player_pos
		w.step(1.0 / 60.0, d.normalized() * minf(1.0, d.length() / 8.0 + 0.3), false)
		t += 1.0 / 60.0
	return w.player_pos.distance_to(to) <= 2.0


func test_the_rock_stands_in_the_clearing() -> void:
	var rock := _rock()
	if not check(not rock.is_empty(), "there is a Leader's Rock"):
		return
	var tex := AssetCatalog.texture(rock["art"])
	var r: Rect2 = rock["rect"]
	check(tex.get_height() >= 32, "drawn taller than a cat (%d px)" % tex.get_height())
	check(r.size.x >= 40.0, "base about three tiles wide (%s)" % r.size)
	check(r.size.y <= 14.0, "collision only on the base (%s)" % r.size)
	check(w.solids.has(r), "the base is solid")
	check_near(r.end.y, rock["pos"].y, 0.01, "the collider sits at the rock's feet")
	# In the middle of the camp, with open ground in front for gathering.
	check(r.position.x > w.size.x * 0.25 and r.end.x < w.size.x * 0.75, "the rock is in the middle part of the camp")
	check(w.zones.has("GatherArea"), "a GatherArea zone")
	var gather: Rect2 = w.zones.get("GatherArea", Rect2())
	check(gather.position.y > r.end.y, "the GatherArea is in front of (below) the rock")
	check(gather.get_center().x > r.position.x and gather.get_center().x < r.end.x, "the GatherArea faces the rock")
	for s: Rect2 in w.solids:
		check(not s.intersects(gather), "nothing solid in the GatherArea (%s)" % s)


func test_fern_walks_round_the_rock_without_snagging() -> void:
	var r: Rect2 = _rock()["rect"]
	var pad := Vector2(w.player_footprint.x / 2.0 + 6.0, 6.0)
	var corners := [
		Vector2(r.position.x - pad.x, r.end.y + pad.y + w.player_footprint.y),
		Vector2(r.end.x + pad.x, r.end.y + pad.y + w.player_footprint.y),
		Vector2(r.end.x + pad.x, r.position.y - pad.y),
		Vector2(r.position.x - pad.x, r.position.y - pad.y),
	]
	w.player_pos = corners[0]
	w.player_vel = Vector2.ZERO
	for i in corners.size() + 1:
		var to: Vector2 = corners[i % corners.size()]
		check(_walk_to(to), "reached %s (stuck at %s)" % [to, w.player_pos])
	# Walking straight into the base stops her at its edge.
	w.player_pos = Vector2(r.get_center().x + 10.0, r.end.y + 20.0)
	_run(2.0, Vector2.UP)
	check(w.player_rect().position.y >= r.end.y - 0.01, "the base blocks (Fern at %s)" % w.player_pos)


func test_the_leader_stands_on_top() -> void:
	var rock := _rock()
	var leader := _leader()
	if not check(not leader.is_empty(), "a cat is perched on the rock"):
		return
	var tex := AssetCatalog.texture(rock["art"])
	var top: float = rock["pos"].y - tex.get_height()
	check(leader["pos"].y >= top and leader["pos"].y <= top + 8.0, "feet on the ledge (%s, rock top %s)" % [leader["pos"], top])
	check(absf(leader["pos"].x - rock["pos"].x) <= 8.0, "on top of the rock, not beside it")
	check(leader["pos"].y + leader["perch"] > rock["pos"].y, "sorted in front of the rock it stands on")
	check_eq(w.markers.get("MeetingSpot"), leader["pos"], "MeetingSpot marker on the ledge, where the leader stands")
	check(not w.solids.has(leader["rect"]), "the leader blocks nothing on the ground")
	check(not World.talkable(leader), "the leader is out of reach")
	var names := JsonData.load_dict("res://data/names/naming.json")
	check_eq(names["cats"][leader["id"]]["rank"], "leader", "%s is the leader" % leader["id"])
	# Next to the rock, the leader never takes the prompt.
	w.player_pos = Vector2(rock["rect"].get_center().x, rock["rect"].position.y - 4.0)
	w.step(0.0, Vector2.ZERO, false)
	check(w.focus_id != leader["id"], "no talk prompt for the leader")


func test_the_deputy_sits_beside_and_talks() -> void:
	var r: Rect2 = _rock()["rect"]
	var dep := _deputy()
	if not check(not dep.is_empty(), "a cat sits at the DeputySpot"):
		return
	var names := JsonData.load_dict("res://data/names/naming.json")
	check_eq(names["cats"][dep["id"]]["rank"], "deputy", "%s is the deputy" % dep["id"])
	check_eq(dep["behavior"], "sit", "the deputy sits")
	var gap: float = maxf(dep["rect"].position.x - r.end.x, r.position.x - dep["rect"].end.x)
	check(gap > w.player_footprint.x and gap <= 32.0, "right beside the rock, with room to walk between (%s px)" % gap)
	check_near(dep["pos"].y, r.end.y, 4.0, "level with the rock's base")
	check(w.ground.any(func(g): return g["art"] == "decor.worn_patch" and (g["pos"] as Vector2).distance_to(dep["pos"]) <= 3.0), "on a worn patch")
	# Walk up and talk.
	w.player_pos = Vector2(dep["rect"].end.x + w.player_footprint.x / 2.0 + 4.0, dep["rect"].end.y)
	w.step(0.0, Vector2.ZERO, false)
	check_eq(w.focus_id, dep["id"], "the deputy has the prompt")
	var ev: Array = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "talk", "interact talks")
	if ev.size() == 1:
		var d = Dialogue.new(GameStateCore.new())
		var line: Dictionary = d.start(JsonData.load_dict(ev[0]["dialogue"]))
		check_eq(line.get("speaker"), dep["id"], "the deputy speaks")
		# No patrol rolled (the Patrols autoload does that in the game).
		check(str(line.get("text", "")).contains("Nothing for you"), "no patrol offered: the idle line (%s)" % line.get("text"))


func _spot_check(sid: String, key: String) -> void:
	var sp: Dictionary = w.spot_by_id(sid)
	if not check(not sp.is_empty(), "spot %s" % sid):
		return
	check(strings.has(key) and str(strings[key]) != "", "%s has a line" % key)
	check_eq(sp["message"], key, "%s says %s" % [sid, key])
	check_eq(w.focus_kind(), "spot", "%s: focus kind" % sid)
	check_eq(w.focus_id, sid, "%s has the prompt" % sid)
	var ev: Array = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "message" and ev[0]["key"] == key, "%s: interact shows its line (%s)" % [sid, ev])
	check(not w.is_talking() and not w.is_busy(), "%s: Fern can move on at once" % sid)


func test_the_leaders_den_waits_for_an_invite() -> void:
	var sp: Dictionary = w.spot_by_id("leaders_den")
	if not check(not sp.is_empty(), "den spot"):
		return
	var r: Rect2 = sp["rect"]
	w.player_pos = Vector2(r.get_center().x, r.end.y + w.player_footprint.y + 3.0)
	w.step(0.0, Vector2.ZERO, false)
	_spot_check("leaders_den", "camp.leaders_den")
	check_eq(str(strings["camp.leaders_den"]), "You should wait to be invited.", "the den's line")
	# Not enterable: walking in stops at the rock.
	var y: float = w.player_pos.y
	_run(1.5, Vector2.UP)
	check(w.player_pos.y >= y - 3.5, "the den can't be entered (moved %s px)" % (y - w.player_pos.y))
	check(_rock()["rect"].has_point(sp["rect"].get_center()) or sp["rect"].position.y >= _rock()["rect"].end.y - 2.0, "the den mouth is at the rock's base")


func test_the_rock_has_its_line() -> void:
	var sp: Dictionary = w.spot_by_id("leaders_rock")
	if not check(not sp.is_empty(), "rock spot"):
		return
	var r: Rect2 = sp["rect"]
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 2.0, r.end.y)
	w.step(0.0, Vector2.ZERO, false)
	_spot_check("leaders_rock", "camp.leaders_rock")
	# Carrying prey doesn't change that (no eating it there).
	w.player_state.carried_item = World.MOUSE
	var ev: Array = w.interact()
	check(ev.size() == 1 and ev[0]["type"] == "message", "still the line while carrying")
	check_eq(w.carrying(), World.MOUSE, "the mouse is kept")


## No spot is in range of both a landmark and a cat (or the pile, or
## another landmark's neighbour cat), so prompts never fight.
func test_landmark_prompts_keep_clear_of_the_cats() -> void:
	for sp: Dictionary in w.spots:
		var area: Rect2 = sp["rect"].grow(sp["talk_radius"] + w.player_footprint.x)
		for npc: Dictionary in w.npcs:
			if not World.talkable(npc):
				continue
			var zone: Rect2 = w.npc_zone(npc)
			var both := 0
			for y in range(int(area.position.y), int(area.end.y + w.player_footprint.y) + 1):
				for x in range(int(area.position.x), int(area.end.x)):
					w.player_pos = Vector2(x, y)
					if w.distance_to_rect(sp["rect"]) <= sp["talk_radius"] and w.distance_to_rect(zone) <= npc["talk_radius"]:
						both += 1
			check_eq(both, 0, "spots in range of both %s and %s" % [sp["id"], npc["id"]])
		if not w.pile.is_empty():
			check(sp["rect"].grow(sp["talk_radius"] + w.pile["talk_radius"] + w.player_footprint.x * 2.0).intersects(w.pile["rect"]) == false, "%s far from the pile" % sp["id"])


func test_markers_are_placed() -> void:
	for n in ["MeetingSpot", "DeputySpot"]:
		check(w.markers.has(n), "%s marker" % n)
	check(w.zones.has("GatherArea"), "GatherArea zone")
	check(Rect2(Vector2.ZERO, w.size).encloses(w.zones.get("GatherArea", Rect2(-1, -1, 1, 1))), "GatherArea inside the camp")

extends "res://tests/test_base.gd"
## The real game screen at the camp landmarks (C.1): the Leader's Rock with
## the leader drawn on top, the den's line by keyboard (desktop) and by the
## paw button (phone), talking to the deputy, and the marker nodes.
## With a display (--shots=<dir>) it saves camp_* screenshots.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var strings: Dictionary


func before_each() -> void:
	strings = JsonData.load_dict("res://data/strings.json")


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	Settings.reset()


func test_camp_rock_leader_and_markers_in_the_scene() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var w = g.world
	var markers: Node = g.world_view.get_node_or_null("Markers")
	if check(markers != null, "a Markers layer"):
		for n in ["MeetingSpot", "DeputySpot", "GatherArea"]:
			var m := markers.get_node_or_null(n)
			check(m is Marker2D, "%s Marker2D in the scene" % n)
		var meet: Node2D = markers.get_node_or_null("MeetingSpot")
		if meet != null:
			check_eq(meet.position, w.markers["MeetingSpot"], "MeetingSpot where world.json puts it")
	var leader_id := ""
	for npc: Dictionary in w.npcs:
		if npc["perch"] > 0.0:
			leader_id = npc["id"]
	var leader: Node2D = g.world_view.npc_nodes.get(leader_id)
	if check(leader != null, "the leader is in the scene"):
		var head: Vector2 = g.world_view.npc_head(leader_id)
		var rock_top: float = 0.0
		for p: Dictionary in w.props:
			if p["type"] == "leaders_rock":
				rock_top = p["pos"].y - AssetCatalog.texture(p["art"]).get_height()
		check(head.y < rock_top, "the leader's head is above the rock (%s < %s)" % [head.y, rock_top])
		var mark: Sprite2D = g.world_view.rank_marks.get(leader_id)
		check(mark != null and mark.visible and mark.position.y < head.y, "the leader's rank symbol over the head")
	# Stand Fern in front of the rock so the camera frames it.
	var gather: Rect2 = w.zones["GatherArea"]
	w.player_pos = gather.get_center()
	w.player_vel = Vector2.ZERO
	await _frames(40)
	if not is_headless():
		_save(await _screen(), "camp_rock_desktop")
	_close(app)


func test_camp_den_line_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var w = g.world
	var sp: Dictionary = w.spot_by_id("leaders_den")
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(sp["rect"].get_center().x, sp["rect"].end.y + w.player_footprint.y + 3.0)
	await _frames(60)
	check_eq(w.focus_id, "leaders_den", "the den has the prompt")
	var paw: Sprite2D = g.world_view.paw
	check(paw.visible, "paw prompt shows")
	check_near(paw.position.x + paw.texture.get_width() / 2.0, sp["prompt"].x, 1.0, "prompt over the den")
	_key(KEY_E)
	await _frames(2)
	check(g.message.visible, "a short line shows")
	check_eq(g.message.text, str(strings["camp.leaders_den"]), "'wait to be invited'")
	check(not g.dialogue.is_open and not w.is_talking(), "no conversation")
	if not is_headless():
		_save(await _screen(), "camp_den_desktop")
	_close(app)


func test_camp_rock_line_and_deputy_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	var w = g.world
	var sp: Dictionary = w.spot_by_id("leaders_rock")
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(sp["rect"].position.x - w.player_footprint.x / 2.0 - 2.0, sp["rect"].end.y)
	await _frames(2)
	check_eq(w.focus_id, "leaders_rock", "the rock has the prompt")
	check(g.touch.highlight, "paw button lit")
	await _paw_button(app)
	check_eq(g.message.text, str(strings["camp.leaders_rock"]), "the rock's line")
	await _frames(130)
	# The deputy.
	var dep_id := ""
	for npc: Dictionary in w.npcs:
		if npc["pos"] == w.markers["DeputySpot"]:
			dep_id = npc["id"]
	var dep: Dictionary = w.npc_by_id(dep_id)
	w.player_pos = Vector2(dep["rect"].end.x + w.player_footprint.x / 2.0 + 4.0, dep["rect"].end.y)
	await _frames(2)
	check_eq(w.focus_id, dep_id, "the deputy has the prompt")
	await _paw_button(app)
	await _frames(2)
	check(w.is_talking(), "talking to the deputy")
	check(g.dialogue.is_open, "the box opens")
	check_eq(str(g.dialogue.line.get("speaker", "")), dep_id, "the deputy speaks")
	check(str(g.dialogue.line.get("text", "")).contains("Dawn patrol"), "the placeholder line")
	await _frames(60)
	if not is_headless():
		_save(await _screen(), "camp_deputy_target_phone")
	_close(app)


# --- helpers (as in needs_smoke.gd)


func _paw_button(app: Control) -> void:
	var tc: Control = app.game.touch
	_touch(app, 1, tc.button_center, true)
	_touch(app, 1, tc.button_center, false)
	await tree.process_frame
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _start(cfg: Array) -> Control:
	ScreenMetrics.override_dpr = cfg[2]
	ScreenMetrics.override_insets_css = cfg[3]
	ScreenMetrics.override_touch = 1 if cfg[4] else 0
	ScreenMetrics.override_fullscreen = 0
	ScreenMetrics.fullscreen_requests = 0
	Settings.debug_overlay = false
	tree.root.size = Vector2i((Vector2(cfg[1]) * float(cfg[2])).round())
	await tree.process_frame
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app.start_game()
	await tree.process_frame
	await tree.process_frame
	check(app.game != null, "%s: game started" % cfg[0])
	return app


func _close(app: Control) -> void:
	DialogueManager.stop()
	tree.root.remove_child(app)
	app.free()


func _touch(app: Control, index: int, ui_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = app.metrics.ui_to_px(ui_pos)
	tree.root.push_input(ev)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		tree.root.push_input(ev)


func _screen() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return tree.root.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	if shots_dir != "":
		var path := shots_dir.path_join("%s.png" % name)
		img.save_png(path)
		print("     shot: ", path)

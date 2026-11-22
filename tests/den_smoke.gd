extends "res://tests/test_base.gd"
## The real game screen at the apprentices' den (C.2):
## - desktop, keyboard: walk up into the den's entrance in camp (fade), the
##   room (DenInterior: floor, nests, Fern's nest, decor slots, decor layer),
##   "Your nest.", and back out to the spawn outside, hunger, thirst and the
##   carried mouse unchanged both ways;
## - phone, touch: the door prompt names the den, the paw button goes in,
##   the joystick walks back out.
## With a display (--shots=<dir>) it saves den_* screenshots.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/app.tscn"
const DEN := "apprentices_den"

const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var tuning: Dictionary
var strings: Dictionary


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	strings = JsonData.load_dict("res://data/strings.json")


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	Needs.hunger_every_s = float(tuning["needs"]["hunger_every_s"])
	Needs.thirst_every_s = float(tuning["needs"]["thirst_every_s"])
	Player.state.carried_item = ""
	Settings.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func test_den_in_and_out_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(52, 41)
	Player.state.carried_item = "mouse"
	_outside(g)
	await _frames(40)
	if not is_headless():
		_save(await _screen(), "den_outside_desktop")
	var saw_fade := await _walk_until_area(app, "move_up", DEN)
	check(saw_fade, "fades on the way in")
	check_eq(g.world.id, DEN, "inside the apprentices' den")
	check_eq(Player.spawn(), "inside", "just inside the doorway")
	await _wait_travel(g)
	check_eq([Needs.hunger(), Needs.thirst()], [52, 41], "hunger and thirst unchanged going in")
	check_eq(Player.carried_item(), "mouse", "still carrying the mouse")
	check(g.world_view.mouth.visible, "the mouse shows in her mouth")
	# The room.
	var den: Node2D = g.world_view.den
	if check(den != null and den.get_parent() != null, "the DenInterior template is in the scene"):
		check_eq(den.scene_file_path, "res://scenes/den_interior.tscn", "built from den_interior.tscn")
		check_eq(den.size_name, g.world.interior["size_name"], "size export")
		check_eq(den.nest_count, g.world.interior["nests"].size(), "nest export")
		check_eq(den.get_node("Nests").get_child_count(), den.nest_count, "a sprite per nest")
		check(den.get_node_or_null("Nests/Nest_player") != null, "Fern's nest is marked")
		var slots: Node = den.get_node("DecorSlots")
		check(slots.get_child_count() >= 4, "decor slots (%d)" % slots.get_child_count())
		check(slots.get_children().all(func(m): return m is Marker2D), "decor slots are Marker2D")
		check(den.get_node_or_null("Decor") != null and den.get_node("Decor").get_child_count() == 0, "an empty Decor layer")
	check(not g.world_view.pollen.emitting and not g.world_view.get_node("Sky").visible, "no sky indoors")
	if not is_headless():
		await _frames(30)
		_save(await _screen(), "den_inside_desktop")
	# Her nest.
	g.world.place_at_spawn("nest")
	await _frames(45)
	check_eq(g.world.focus_kind(), "spot", "her nest has the prompt")
	_key(KEY_E)
	await _frames(2)
	check_eq(g.message.text, str(strings["den.your_nest"]), "'Your nest.'")
	check(g.message.visible, "the line shows")
	check_eq(Player.carried_item(), "mouse", "not eaten at the nest")
	if not is_headless():
		_save(await _screen(), "den_nest_desktop")
	# Out again.
	g.world.place_at_spawn("inside")
	await _frames(20)
	saw_fade = await _walk_until_area(app, "move_down", "camp")
	check(saw_fade, "fades on the way out")
	check_eq(Player.spawn(), "from_apprentices_den", "outside the entrance")
	check_eq(g.world.player_pos, g.world.spawns["from_apprentices_den"]["pos"], "at the spawn outside")
	await _wait_travel(g)
	check_eq([Needs.hunger(), Needs.thirst()], [52, 41], "hunger and thirst unchanged going out")
	check_eq(Player.carried_item(), "mouse", "still carrying the mouse outside")
	await _frames(20)
	check_eq(g.world.id, "camp", "no bounce back in")
	_close(app)


func test_den_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	_outside(g)
	await _frames(40)
	check_eq(g.world.focus_id, "apprentices_den_door", "the doorway has the prompt")
	check(g.prompt_label.visible, "the prompt shows the den's name")
	check_eq(g.prompt_label.text, str(strings["den.apprentices.name"]), "'Apprentices' den'")
	check(app.metrics.safe_rect.encloses(Rect2(g.prompt_label.position, g.prompt_label.size)), "name inside the safe area")
	var paw_ui: Vector2 = g.world_to_ui(g.world_view.paw.position)
	check(g.prompt_label.position.y + g.prompt_label.size.y <= paw_ui.y + 1.0, "name above the paw")
	if not is_headless():
		_save(await _screen(), "den_door_target_phone")
	check(g.touch.highlight, "paw button lit")
	_touch(app, 1, g.touch.button_center, true)
	_touch(app, 1, g.touch.button_center, false)
	var until := Time.get_ticks_msec() + 5000
	while g.world.id != DEN and Time.get_ticks_msec() < until:
		await tree.process_frame
	check_eq(g.world.id, DEN, "the paw button goes in")
	await _wait_travel(g)
	check(not g.prompt_label.visible or g.world.focus_id != "apprentices_den_door", "no door name inside")
	if not is_headless():
		await _frames(30)
		_save(await _screen(), "den_inside_target_phone")
	# Out with the joystick.
	var tc: Control = g.touch
	var start: Vector2 = tc.stick_rest
	_touch(app, 0, start, true)
	_drag(app, 0, start + Vector2(0, tc.stick_radius * 0.7))
	until = Time.get_ticks_msec() + 6000
	while g.world.id != "camp" and Time.get_ticks_msec() < until:
		await tree.process_frame
	_touch(app, 0, start, false)
	check_eq(g.world.id, "camp", "the joystick walks back out")
	await _wait_travel(g)
	_close(app)


# --- helpers (as in travel_smoke.gd)


## Fern just outside the den's entrance, in line with it.
func _outside(g: Control) -> void:
	var w = g.world
	w.place_at_spawn("from_apprentices_den")
	for e: Dictionary in w.exits:
		if e["to"] == DEN:
			w.player_pos.x = (e["rect"] as Rect2).get_center().x
	w.player_vel = Vector2.ZERO


func _freeze_needs(h: int, t: int) -> void:
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", h)
	Needs.set_value("thirst", t)


func _walk_until_area(app: Control, action: String, area: String) -> bool:
	var g: Control = app.game
	var saw_fade := false
	Input.action_press(action)
	var until := Time.get_ticks_msec() + 6000
	while g.world.id != area and Time.get_ticks_msec() < until:
		await tree.process_frame
		saw_fade = saw_fade or (g.fade.visible and g.fade.color.a > 0.3)
	Input.action_release(action)
	return saw_fade


func _wait_travel(g: Control, ms: int = 3000) -> void:
	var until := Time.get_ticks_msec() + ms
	while g.travel.busy() and Time.get_ticks_msec() < until:
		await tree.process_frame
	await tree.process_frame
	check(not g.travel.busy(), "the fade finishes")


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


func _drag(app: Control, index: int, ui_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
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

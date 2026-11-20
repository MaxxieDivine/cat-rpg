extends "res://tests/test_base.gd"
## The real game screen walking between areas and passing out:
## - camp -> Hunting Grounds -> camp by keyboard (desktop) and by the
##   joystick (phone): the fade, the spawn and facing, camera limits per
##   area, hunger / thirst kept, no bounce back through the exit;
## - passing out from the Hunting Grounds (tap to continue) and in camp
##   (continues on its own): control locks, Fern sinks down, black with the
##   message, she wakes at her den with restored needs and nothing carried,
##   and it happens once;
## - the debug overlay: area / spawn in the label, H / T and the buttons.
## With a display (--shots=<dir>) it saves screenshots.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

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
	Settings.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func test_walk_to_the_hunting_grounds_and_back_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(47, 33)
	check_eq(g.world.id, "camp", "the game starts in camp")
	check_eq(Player.area(), "camp", "Player knows it")
	# Near the camp exit, then walk right into it.
	_place_near_exit(g, "hunting_grounds")
	if not is_headless():
		await _settle()
		_save(await _screen(), "travel_camp_exit_desktop")
	var saw_fade := await _walk_until_area(app, "move_right", "hunting_grounds")
	check(saw_fade, "fades to black on the way")
	check_eq(g.world.id, "hunting_grounds", "in the Hunting Grounds")
	check_eq(Player.area(), "hunting_grounds", "Player area follows")
	check_eq(Player.spawn(), "from_camp", "arrived at the exit's spawn")
	check_eq(g.world.player_pos, g.world.spawns["from_camp"]["pos"], "at the spawn point")
	check_eq(g.world.facing, 1, "facing away from the exit (into the grounds)")
	_check_camera(g)
	await _wait_travel(g)
	check_eq([Needs.hunger(), Needs.thirst()], [47, 33], "hunger and thirst carried over")
	check_eq(g.needs_hud.hunger, 47, "the bar too")
	if not is_headless():
		await _settle()
		_save(await _screen(), "travel_hunting_desktop")
	if not is_headless():
		# The middle of the grounds: tall grass, a prey spot, the golden light.
		var spot: Vector2 = g.world.prey_spots[0]["pos"]
		g.world.player_pos = spot + Vector2(0, 6)
		await _settle()
		_save(await _screen(), "hunting_tall_grass_desktop")
		g.world.place_at_spawn("from_camp")
		await _frames(2)
	# Not bounced back: standing still for a while stays here.
	await _frames(20)
	check_eq(g.world.id, "hunting_grounds", "no bounce back through the exit")
	# Walk back left to camp.
	saw_fade = await _walk_until_area(app, "move_left", "camp")
	check(saw_fade, "fades on the way back")
	check_eq(g.world.id, "camp", "back in camp")
	check_eq(Player.spawn(), "from_hunting", "at the camp's spawn for this exit")
	check_eq(g.world.facing, -1, "facing away from the exit (into camp)")
	_check_camera(g)
	await _wait_travel(g)
	check_eq([Needs.hunger(), Needs.thirst()], [47, 33], "still the same needs")
	check(g.world_view.npc_nodes.has("bram"), "the camp cats are back")
	_close(app)


func test_walk_to_the_hunting_grounds_by_joystick() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	check(g.touch.visible, "touch controls on a phone")
	_place_near_exit(g, "hunting_grounds")
	var tc: Control = g.touch
	var start: Vector2 = tc.stick_rest
	_touch(app, 0, start, true)
	_drag(app, 0, start + Vector2(tc.stick_radius * 0.7, 0))
	var saw_fade := false
	var until := Time.get_ticks_msec() + 5000
	while g.world.id != "hunting_grounds" and Time.get_ticks_msec() < until:
		await tree.process_frame
		saw_fade = saw_fade or g.fade.visible
	check(saw_fade, "fade while walking out")
	check(not g.touch.visible, "touch controls hidden during the fade")
	_touch(app, 0, start, false)
	check_eq(g.world.id, "hunting_grounds", "walking into the exit is enough on a phone")
	await _wait_travel(g)
	check(g.touch.visible, "touch controls back after the fade")
	check(g.world.exit_at_player().is_empty(), "not standing in the exit")
	if not is_headless():
		await _settle()
		_save(await _screen(), "travel_hunting_target_phone")
	_close(app)


func test_pass_out_in_the_hunting_grounds() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_fast_collapse(g)
	Player.state.carried_item = "mouse"
	g.load_area("hunting_grounds", "from_camp")
	await _frames(2)
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", 50)
	Needs.set_value("thirst", 0)
	await _frames(2)
	check_eq(g.travel.kind, "collapse", "thirst at 0: Fern passes out")
	check(not g.touch.visible, "controls hidden")
	check_eq(g.world_view.pose, "down", "she sinks down")
	# Control is locked.
	var at: Vector2 = g.world.player_pos
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	check(g.world.player_pos.distance_to(at) < 0.5, "can't walk while passing out")
	# Can't trigger twice.
	check(not g.collapse(), "a second collapse can't start")
	var until := Time.get_ticks_msec() + 4000
	while g.travel.phase != "message" and Time.get_ticks_msec() < until:
		await tree.process_frame
	check_eq(g.travel.phase, "message", "message on black")
	check(g.fade.visible and g.fade.color.a >= 0.99, "the screen is black")
	check(g.fade_message.visible, "message shown")
	check_eq(g.fade_message.text, str(strings["collapse.message"]), "the collapse message")
	check(app.metrics.safe_rect.encloses(Rect2(g.fade_message.position, g.fade_message.size)), "message inside the safe area")
	check_eq(g.world.id, "camp", "carried home to camp")
	check_eq(Player.spawn(), str(tuning["collapse"]["recovery_spawn"]), "at the den")
	check_eq([Needs.hunger(), Needs.thirst()], [int(tuning["needs"]["restore_hunger"]), int(tuning["needs"]["restore_thirst"])], "needs restored")
	check_eq(Player.carried_item(), "", "dropped what she carried")
	check_eq(Player.state.collapses, 1, "one collapse")
	await tree.create_timer(g.travel.min_message_s + 0.1).timeout
	await _frames(1)
	check(g.fade_hint.visible, "tap-to-continue hint")
	if not is_headless():
		_save(await _screen(), "collapse_message_target_phone")
	_touch(app, 3, app.metrics.safe_rect.get_center(), true)
	_touch(app, 3, app.metrics.safe_rect.get_center(), false)
	await _frames(2)
	check(g.travel.phase == "in" or g.travel.phase == "wake", "a tap continues (%s)" % g.travel.phase)
	check_eq(g.world_view.pose, "wake", "she stretches awake")
	await _wait_travel(g)
	check_eq(Player.state.collapses, 1, "still exactly one collapse")
	check(g.touch.visible, "control back")
	at = g.world.player_pos
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	check(g.world.player_pos.x > at.x + 2.0, "can walk again")
	check_eq(g.world_view.pose, "", "awake")
	_close(app)


func test_pass_out_in_camp_continues_on_its_own() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_fast_collapse(g)
	g.travel.message_s = 0.5
	var pile_before: int = g.world.pile["prey"] - 1
	g.world.pile["prey"] = pile_before
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", 0)
	await _frames(2)
	check_eq(g.travel.kind, "collapse", "hunger at 0: Fern passes out")
	await _wait_travel(g, 6000)
	check_eq(g.world.id, "camp", "still camp")
	check_eq(g.world.player_pos, g.world.spawns["den"]["pos"], "wakes at her den")
	check_eq(g.world.pile["prey"], pile_before, "same camp (not reloaded), the pile as it was")
	check_eq(Needs.hunger(), int(tuning["needs"]["restore_hunger"]), "hunger restored")
	check_eq(Player.state.collapses, 1, "once")
	if not is_headless():
		await _settle()
		_save(await _screen(), "collapse_woke_desktop")
	_close(app)


func test_debug_overlay_helpers() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Settings.debug_overlay = true
	await _frames(2)
	app._update_hud()
	check(app.hud.text.contains(g.world.display_name), "label names the area (%s)" % app.hud.text)
	check(app.hud.text.contains(Player.spawn()), "label names the spawn")
	for b: Button in app.debug_buttons:
		check(b.visible, "%s shown with the overlay" % b.name)
		check(b.size.y >= 48.0, "%s is a 48-unit target" % b.name)
		check(b.position.x >= app.metrics.safe_rect.get_center().x, "%s on the right half (not the joystick's)" % b.name)
		check(not Rect2(b.position, b.size).intersects(Rect2(app.volume_button.position, app.volume_button.size)), "%s clear of the volume button" % b.name)
		check(not Rect2(b.position, b.size).intersects(g.needs_hud.hud_rect), "%s clear of the needs bars" % b.name)
	_key(KEY_H)
	await _frames(1)
	check_eq(Needs.hunger(), 5, "H sets hunger to 5")
	app.debug_buttons[1].pressed.emit()
	await _frames(1)
	check_eq(Needs.thirst(), 5, "the button sets thirst to 5")
	if not is_headless():
		_save(await _screen(), "debug_overlay_desktop")
	Settings.debug_overlay = false
	await _frames(1)
	check(not app.debug_buttons[0].visible, "buttons hide with the overlay")
	Needs.set_value("hunger", 80)
	_key(KEY_H)
	await _frames(1)
	check_eq(Needs.hunger(), 80, "H does nothing without the overlay")
	_close(app)


# --- helpers


func _freeze_needs(h: int, t: int) -> void:
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", h)
	Needs.set_value("thirst", t)


func _fast_collapse(g: Control) -> void:
	g.travel.lie_s = 0.2
	g.travel.collapse_fade_s = 0.15
	g.travel.wake_s = 0.1


func _place_near_exit(g: Control, to: String) -> void:
	var w = g.world
	for e: Dictionary in w.exits:
		if e["to"] == to:
			var r: Rect2 = e["rect"]
			var side := -1.0 if r.get_center().x > w.size.x / 2.0 else 1.0
			w.player_pos = Vector2(r.get_center().x + side * 30.0, r.end.y - 6.0)
			w.player_vel = Vector2.ZERO
			w.exits_armed = true


func _walk_until_area(app: Control, action: String, area: String) -> bool:
	var g: Control = app.game
	var saw_fade := false
	Input.action_press(action)
	var until := Time.get_ticks_msec() + 5000
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
	check(not g.fade.visible, "the screen is clear")


func _check_camera(g: Control) -> void:
	var lim: Rect2 = g.world.camera_bounds()
	check_eq(Vector2(g.camera.limit_left, g.camera.limit_top), lim.position, "camera limits follow the area (top-left)")
	check_eq(Vector2(g.camera.limit_right, g.camera.limit_bottom), lim.end, "camera limits follow the area (bottom-right)")
	var vs := Vector2(g.view_size)
	for axis in 2:
		if vs[axis] <= lim.size[axis]:
			check(g.camera_rect.position[axis] >= lim.position[axis] and g.camera_rect.end[axis] <= lim.end[axis], "camera inside the area on axis %d" % axis)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _settle() -> void:
	await _frames(30)


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

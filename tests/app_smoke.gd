extends "res://tests/test_base.gd"
## Runs the real main scene at phone and desktop sizes: title, tap to start,
## integer-scaled game view, touch controls / keyboard, interact, portrait.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

## name, CSS size, devicePixelRatio, insets [top, right, bottom, left] (CSS px), touch
const PHONE := ["phone", Vector2i(844, 390), 3.0, [0.0, 47.0, 21.0, 47.0], true]
const SMALL_PHONE := ["small_phone", Vector2i(667, 375), 2.0, [0.0, 0.0, 0.0, 0.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]
const DESKTOP_HD := ["desktop_hd", Vector2i(1920, 1080), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var strings: Dictionary
var tuning: Dictionary
var world_data: Dictionary


func before_each() -> void:
	strings = JsonData.load_dict("res://data/strings.json")
	tuning = JsonData.load_dict("res://data/tuning.json")
	world_data = JsonData.load_dict("res://data/world.json")


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func test_phone() -> void:
	await _run_config(PHONE)


func test_small_phone() -> void:
	await _run_config(SMALL_PHONE)


func test_desktop() -> void:
	await _run_config(DESKTOP)


func test_desktop_hd() -> void:
	await _run_config(DESKTOP_HD)


func test_portrait_shows_rotate_message_and_pauses() -> void:
	var app: Control = await _open(PHONE)
	await _tap(app, app.metrics.safe_rect.get_center(), app.metrics)
	check(app.game != null, "game started")
	await _resize(app, Vector2i(390, 844), 3.0, [47.0, 0.0, 34.0, 0.0])
	check(app.rotate.visible, "rotate overlay shown in portrait")
	check(app.game.paused, "game paused in portrait")
	check(app.rotate.label.text == str(strings["rotate.touch"]), "rotate text from strings.json")
	if shots_dir != "" and not is_headless():
		await tree.create_timer(1.2).timeout
		await _shot(app, "portrait_rotate")
	var before: Vector2 = app.game.world.player_pos
	Input.action_press("move_right")
	await tree.create_timer(0.2).timeout
	Input.action_release("move_right")
	check_eq(app.game.world.player_pos, before, "no movement while paused")
	await _resize(app, PHONE[1], PHONE[2], PHONE[3])
	check(not app.rotate.visible, "overlay gone in landscape")
	check(not app.game.paused, "game resumes in landscape")
	_close(app)


func _open(cfg: Array) -> Control:
	ScreenMetrics.override_dpr = cfg[2]
	ScreenMetrics.override_insets_css = cfg[3]
	ScreenMetrics.override_touch = 1 if cfg[4] else 0
	tree.root.size = Vector2i((Vector2(cfg[1]) * float(cfg[2])).round())
	await tree.process_frame
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	return app


func _resize(app: Control, css: Vector2i, dpr: float, insets: Array) -> void:
	ScreenMetrics.override_dpr = dpr
	ScreenMetrics.override_insets_css = insets
	tree.root.size = Vector2i((Vector2(css) * dpr).round())
	await tree.process_frame
	app.relayout()  # also wired to size_changed; called directly so the test doesn't depend on it
	await tree.process_frame


func _close(app: Control) -> void:
	tree.root.remove_child(app)
	app.free()


func _run_config(cfg: Array) -> void:
	var name: String = cfg[0]
	var css: Vector2i = cfg[1]
	var dpr: float = cfg[2]
	var touch_device: bool = cfg[4]
	var app: Control = await _open(cfg)
	var m = app.metrics
	var safe: Rect2 = m.safe_rect

	# --- Title screen
	check(app.title != null and app.game == null, "%s: starts on the title screen" % name)
	check(not app.rotate.visible, "%s: no rotate message in landscape" % name)
	var t: Control = app.title
	check_eq(t.start_label.text, str(strings["title.start_touch" if touch_device else "title.start_desktop"]), "%s: start text" % name)
	for l: Control in [t.title_label, t.start_label, t.controls_label]:
		check(safe.encloses(l.get_global_rect()), "%s: title text inside safe area" % name)
	if t.fullscreen_button.visible:
		var fb: Rect2 = t.fullscreen_button.get_global_rect()
		check(safe.encloses(fb), "%s: fullscreen button inside safe area" % name)
		check(fb.size.x * m.px_per_unit.x / dpr >= 48.0 - 0.01 and fb.size.y * m.px_per_unit.y / dpr >= 48.0 - 0.01, "%s: fullscreen button >= 48 CSS px" % name)
	check_near(t.cat.scale.x * m.px_per_unit.x, t.cat_scale, 0.001, "%s: title cat is whole-number scaled" % name)
	_check_hud(app, name)
	if shots_dir != "" and not is_headless():
		await _shot(app, name + "_title")

	# --- Tap to start
	await _tap(app, Vector2(safe.get_center().x, safe.end.y - 30), m)
	check(app.game != null, "%s: a tap starts the game" % name)
	if app.game == null:
		_close(app)
		return
	await tree.process_frame
	var g: Control = app.game

	# --- Game view: largest whole-number scale that fits the safe area
	var safe_px: Rect2i = m.safe_rect_px()
	var expect_k := maxi(1, floori(minf(safe_px.size.x / 480.0, safe_px.size.y / 270.0)))
	check_eq(g.view_scale, expect_k, "%s: world view scale" % name)
	var vp: Vector2 = g.view_rect.position * m.px_per_unit
	var vs: Vector2 = g.view_rect.size * m.px_per_unit
	check_near(vs.x, 480.0 * expect_k, 0.01, "%s: view width in device px" % name)
	check_near(vs.y, 270.0 * expect_k, 0.01, "%s: view height in device px" % name)
	check_near(vp.x, roundf(vp.x), 0.01, "%s: view x on a whole device px" % name)
	check_near(vp.y, roundf(vp.y), 0.01, "%s: view y on a whole device px" % name)
	check(safe.grow(0.01).encloses(g.view_rect), "%s: world view inside safe area" % name)
	check_near(g.view_rect.get_center().x, safe.get_center().x, 1.0, "%s: view centred x" % name)
	_check_hud(app, name)

	if not is_headless():
		await _check_view_pixels(app, name)

	# --- Controls
	check_eq(g.touch.visible, touch_device, "%s: touch controls shown only on touch devices" % name)
	if touch_device:
		await _check_touch(app, name)
	else:
		await _check_keyboard(app, name)

	if shots_dir != "" and not is_headless():
		await _shot(app, name)
	_close(app)


func _check_hud(app: Control, name: String) -> void:
	check(app.hud.text.begins_with("build "), "%s: build label '%s'" % [name, app.hud.text])
	check(app.metrics.safe_rect.encloses(app.hud.get_global_rect()), "%s: build label inside safe area" % name)


func _check_touch(app: Control, name: String) -> void:
	var g: Control = app.game
	var tc: Control = g.touch
	var m = app.metrics
	var safe: Rect2 = m.safe_rect
	var t: Dictionary = tuning["touch"]
	var margin := float(t["edge_margin"])
	for r: Rect2 in [tc.stick_rect(), tc.button_rect()]:
		check(safe.grow(-margin + 0.01).encloses(r), "%s: touch control %s keeps %s px from safe edges" % [name, r, margin])
		check(r.size.x * m.px_per_unit.x / m.dpr >= float(t["min_target"]) - 0.01, "%s: touch control >= %s CSS px" % [name, t["min_target"]])
	check(tc.stick_rect().get_center().x < safe.get_center().x, "%s: stick on the left" % name)
	check(tc.button_rect().get_center().x > safe.get_center().x, "%s: button on the right" % name)

	# Half-push the stick to the right: walk.
	var w = g.world
	w.player_pos = Vector2(150, 175)
	w.player_vel = Vector2.ZERO
	var start: Vector2 = tc.stick_rest
	var radius := float(t["stick_radius"])
	_touch(app, 0, start, true)
	_drag(app, 0, start + Vector2(radius * 0.6, 0))
	await tree.create_timer(0.4).timeout
	check(w.player_pos.x > 155.0, "%s: stick moves the cat right (x=%s)" % [name, w.player_pos.x])
	check(not tc.trot, "%s: half push does not trot" % name)
	check(w.speed() < float(tuning["player"]["walk_speed"]) + 0.01, "%s: half push walks" % name)
	# Push all the way: trot.
	_drag(app, 0, start + Vector2(radius * 1.5, 0))
	await tree.create_timer(0.3).timeout
	check(tc.trot, "%s: full push trots" % name)
	check(w.speed() > float(tuning["player"]["walk_speed"]), "%s: trotting is faster than walking" % name)
	# Let go: stop.
	_touch(app, 0, start + Vector2(radius * 1.5, 0), false)
	await tree.create_timer(0.3).timeout
	check_eq(tc.stick_vector, Vector2.ZERO, "%s: stick released" % name)
	check_eq(w.speed(), 0.0, "%s: cat stops when the thumb lifts" % name)

	# Walk up to the cow and press the paw button with a second finger.
	_place_next_to_cow(w)
	await tree.process_frame
	await tree.process_frame
	check(tc.highlight, "%s: paw button lights up next to the cow" % name)
	_touch(app, 1, tc.button_center, true)
	_touch(app, 1, tc.button_center, false)
	await tree.process_frame
	_check_bubble(app, name)
	# A tap on the right half away from the button does nothing.
	g.bubble.hide_bubble()
	_touch(app, 2, Vector2(safe.end.x - 60, safe.position.y + 60), true)
	_touch(app, 2, Vector2(safe.end.x - 60, safe.position.y + 60), false)
	await tree.process_frame
	check(not g.bubble.visible, "%s: tapping empty space does not interact" % name)
	check_eq(tc.stick_vector, Vector2.ZERO, "%s: right-half tap does not move the stick" % name)


func _check_keyboard(app: Control, name: String) -> void:
	var g: Control = app.game
	var w = g.world
	w.player_pos = Vector2(150, 175)
	w.player_vel = Vector2.ZERO
	Input.action_press("move_right")
	await tree.create_timer(0.4).timeout
	Input.action_release("move_right")
	check(w.player_pos.x > 155.0, "%s: keyboard moves the cat (x=%s)" % [name, w.player_pos.x])
	check_eq(w.facing, 1, "%s: facing right" % name)
	await tree.create_timer(0.2).timeout
	check_eq(w.speed(), 0.0, "%s: stops when the key is released" % name)

	_place_next_to_cow(w)
	await tree.process_frame
	await tree.process_frame
	check(g.prompt.visible, "%s: interact prompt shown next to the cow" % name)
	check_eq(g.prompt.text(), str(strings["hint.interact_desktop"]), "%s: prompt text" % name)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.keycode = KEY_E
	ev.pressed = true
	tree.root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	tree.root.push_input(up)
	await tree.process_frame
	_check_bubble(app, name)
	check(not g.prompt.visible, "%s: prompt hidden while the cow talks" % name)


func _check_bubble(app: Control, name: String) -> void:
	var g: Control = app.game
	check(g.bubble.visible, "%s: speech bubble shown" % name)
	check_eq(g.bubble.text(), str(strings[world_data["npcs"][0]["say"]]), "%s: bubble text from strings.json" % name)
	var r: Rect2 = g.bubble.get_global_rect()
	check(app.metrics.safe_rect.encloses(r), "%s: bubble inside safe area" % name)
	var head: Vector2 = g.world_to_ui(g.world_view.npc_head("cow"))
	check(r.end.y <= head.y + 0.01, "%s: bubble above the cow's head" % name)


func _place_next_to_cow(w) -> void:
	var cow: Rect2 = w.npcs[0]["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(cow.position.x - w.player_footprint.x / 2.0 - 4.0, cow.end.y)


## The world view on screen must be the SubViewport image scaled by exactly k:
## every world pixel covers k x k device pixels of one colour.
func _check_view_pixels(app: Control, name: String) -> void:
	var g: Control = app.game
	var touch_was: bool = g.touch.visible
	g.touch.visible = false
	app.hud.visible = false
	g.prompt.hide_bubble()
	g.bubble.hide_bubble()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var src: Image = g.viewport.get_texture().get_image()
	var shot: Image = tree.root.get_texture().get_image()
	var k: int = g.view_scale
	if OS.get_environment("DUMP_PIXELS") != "":
		src.save_png(OS.get_environment("DUMP_PIXELS") + "/src_%s.png" % name)
		shot.save_png(OS.get_environment("DUMP_PIXELS") + "/shot_%s.png" % name)
	var origin := Vector2i((g.view_rect.position * app.metrics.px_per_unit).round())
	var bad := 0
	var checked := 0
	var bad_box := Rect2i()
	for y in range(0, src.get_height(), 2):
		for x in range(0, src.get_width(), 2):
			var c := src.get_pixel(x, y)
			for corner in [Vector2i(0, 0), Vector2i(k - 1, 0), Vector2i(0, k - 1), Vector2i(k - 1, k - 1)]:
				var s := shot.get_pixelv(origin + Vector2i(x, y) * k + corner)
				checked += 1
				if absf(s.r - c.r) > 0.02 or absf(s.g - c.g) > 0.02 or absf(s.b - c.b) > 0.02:
					bad_box = Rect2i(x, y, 1, 1) if bad == 0 else bad_box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
					bad += 1
	check_eq(bad, 0, "%s: device pixels that don't match their world pixel (of %d checked; bad world pixels in %s; k=%d origin=%s)" % [name, checked, bad_box, k, origin])
	g.touch.visible = touch_was
	app.hud.visible = true


func _shot(app: Control, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	var path := shots_dir.path_join("app_%s.png" % name)
	img.save_png(path)
	print("     shot: ", path)


func _tap(app: Control, ui_pos: Vector2, m) -> void:
	var px: Vector2 = m.ui_to_px(ui_pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		tree.root.push_input(ev)
	await tree.process_frame


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

extends "res://tests/test_base.gd"
## The real game screen with needs: the hunger / thirst bars (size, place,
## pulse), eating at the fresh-catch pile by touch, drinking at the pond by
## keyboard, the short "empty" / "not hungry" lines and the paw prompt.
## With a display (--shots=<dir>) it saves phone and desktop screenshots.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const World := preload("res://scripts/core/world.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

## name, CSS size, devicePixelRatio, insets [top, right, bottom, left] (CSS px), touch
const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const PHONE := ["phone", Vector2i(844, 390), 3.0, [0.0, 47.0, 21.0, 47.0], true]
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


func test_bars_target_phone() -> void:
	await _bars(TARGET_PHONE)


func test_bars_phone() -> void:
	await _bars(PHONE)


func test_bars_desktop() -> void:
	await _bars(DESKTOP)


## The bars sit top-left inside the safe area, big enough to read, clear of
## the corner buttons and the joystick, and go down over time.
func _bars(cfg: Array) -> void:
	var app: Control = await _start(cfg)
	var g: Control = app.game
	var hud: Control = g.needs_hud
	var m = app.metrics
	var name: String = cfg[0]
	check(hud.visible, "%s: needs bars shown" % name)
	check(m.safe_rect.encloses(hud.hud_rect), "%s: bars inside the safe area" % name)
	check(hud.hud_rect.get_center().x < m.safe_rect.get_center().x and hud.hud_rect.get_center().y < m.safe_rect.get_center().y, "%s: bars in the top-left" % name)
	var css: float = m.px_per_unit.y / m.dpr  # CSS px per UI unit
	for r: Rect2 in hud.bar_rects:
		check(r.size.y * css >= 10.0, "%s: bar at least 10 CSS px tall (%.1f)" % [name, r.size.y * css])
		check(r.size.x * css >= 70.0, "%s: bar at least 70 CSS px wide (%.1f)" % [name, r.size.x * css])
	check(not hud.hud_rect.intersects(Rect2(app.fullscreen_button.position, app.fullscreen_button.size)), "%s: clear of the fullscreen button" % name)
	check(not hud.hud_rect.intersects(Rect2(app.volume_button.position, app.volume_button.size)), "%s: clear of the volume button" % name)
	if g.touch.visible:
		check(not hud.hud_rect.intersects(g.touch.button_rect()), "%s: clear of the paw button" % name)
	check_eq(hud.hunger, int(tuning["needs"]["start"]), "%s: hunger bar starts at %s" % [name, tuning["needs"]["start"]])
	# Tick fast: the bars follow the needs_changed signal.
	Needs.hunger_every_s = 0.02
	Needs.thirst_every_s = 0.02
	for i in 6:
		await tree.process_frame
	check(hud.hunger < int(tuning["needs"]["start"]) and hud.hunger == Needs.hunger(), "%s: hunger bar goes down (%d)" % [name, hud.hunger])
	check(hud.thirst < int(tuning["needs"]["start"]) and hud.thirst == Needs.thirst(), "%s: thirst bar goes down (%d)" % [name, hud.thirst])
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.needs.hunger = 10
	Needs.needs.thirst = 60
	Needs.refresh()
	await tree.process_frame
	check(hud.is_low(0) and not hud.is_low(1), "%s: only the hunger bar pulses" % name)
	# The debug label moves the bars down instead of covering them.
	Settings.debug_overlay = true
	await tree.process_frame
	check(not hud.hud_rect.intersects(Rect2(app.hud.position, app.hud.size)), "%s: bars below the build / fps label" % name)
	Settings.debug_overlay = false
	await tree.process_frame
	if not is_headless():
		var img: Image = await _screen()
		_save(img, "needs_%s" % name)
		var bar: Rect2 = hud.bar_rects[1]
		var p := Vector2i((bar.position + bar.size * Vector2(0.25, 0.5)) * m.px_per_unit)
		check(img.get_pixelv(p).b > img.get_pixelv(p).r, "%s: thirst bar is drawn blue" % name)
	_close(app)


func test_eat_at_the_pile_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	var w = g.world
	var full: int = w.pile["prey"]
	Needs.hunger_every_s = 0.0
	Needs.needs.hunger = 30
	Needs.refresh()
	await _go_to_pile(app)
	check(g.world_view.paw.visible, "paw prompt over the pile")
	check(g.touch.highlight, "paw button lit")
	var head: Vector2 = g.world_view.pile.head()
	check(g.world_view.paw.position.y < head.y and absf(g.world_view.paw.position.x + 5.0 - head.x) <= 2.0, "prompt sits above the pile")
	await _paw_button(app)
	check_eq(Needs.hunger(), 30 + int(tuning["needs"]["eat"]), "eating fills hunger")
	check_eq(g.needs_hud.hunger, Needs.hunger(), "the bar follows")
	check_eq(w.pile["prey"], full - 1, "one prey gone")
	check_eq(g.world_view.pile.frame, full - 1, "the pile shows one fewer")
	check(w.is_busy() and g.world_view.player.anim == "lick", "Fern eats (lick animation)")
	check(not g.world_view.paw.visible, "no prompt mid-bite")
	if not is_headless():
		_save(await _screen(), "needs_eat_target_phone")
	# Full now: a short line instead of eating.
	await _wait_idle(app)
	Needs.needs.hunger = 95
	Needs.refresh()
	await _paw_button(app)
	check(g.message.visible, "a short line shows")
	check_eq(g.message.text, str(strings["needs.not_hungry"]), "'not hungry' line")
	check_eq(w.pile["prey"], full - 1, "no prey wasted")
	check(app.metrics.safe_rect.encloses(Rect2(g.message.position, g.message.size)), "line inside the safe area")
	# Empty the pile.
	w.pile["prey"] = 0
	Needs.needs.hunger = 20
	await tree.process_frame
	check_eq(g.world_view.pile.frame, 0, "the pile looks empty")
	await _paw_button(app)
	check_eq(g.message.text, str(strings["needs.pile_empty"]), "'pile is empty' line")
	check_eq(Needs.hunger(), 20, "nothing eaten")
	if not is_headless():
		_save(await _screen(), "needs_empty_target_phone")
	_close(app)


func test_drink_at_the_pond_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var w = g.world
	Needs.thirst_every_s = 0.0
	Needs.needs.thirst = 20
	Needs.refresh()
	var r: Rect2 = w.pond["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 2.0, r.get_center().y)
	await tree.process_frame
	await tree.process_frame
	check_eq(w.focus_id, World.POND_ID, "pond in focus from the west bank")
	check(g.world_view.paw.visible, "paw prompt at the water's edge")
	_key(KEY_E)
	await tree.process_frame
	await tree.process_frame
	check_eq(Needs.thirst(), 20 + int(tuning["needs"]["drink"]), "drinking fills thirst")
	check_eq(w.facing, 1, "Fern faces the water")
	check(g.world_view.ripple.visible, "ripples on the water")
	check(g.sound.played.get("drink", 0) >= 1, "a lap sound")
	if not is_headless():
		for i in 30:
			await tree.process_frame  # let the camera catch up with Fern
		_save(await _screen(), "needs_drink_desktop")
	_close(app)


func _go_to_pile(app: Control) -> void:
	var w = app.game.world
	var r: Rect2 = w.pile["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(r.end.x + w.player_footprint.x / 2.0 + 4.0, r.end.y)
	await tree.process_frame
	await tree.process_frame
	check_eq(w.focus_id, World.PILE_ID, "pile in range")


func _wait_idle(app: Control) -> void:
	var until := Time.get_ticks_msec() + 4000
	while app.game.world.is_busy() and Time.get_ticks_msec() < until:
		await tree.process_frame
	check(not app.game.world.is_busy(), "eating ends")


func _paw_button(app: Control) -> void:
	var tc: Control = app.game.touch
	_touch(app, 1, tc.button_center, true)
	_touch(app, 1, tc.button_center, false)
	await tree.process_frame
	await tree.process_frame


# --- Driving the app (as in dialogue_smoke.gd)


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

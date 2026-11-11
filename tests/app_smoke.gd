extends "res://tests/test_base.gd"
## Runs the real main scene at phone and desktop sizes: title, tap to start,
## integer-scaled game view, touch controls / keyboard, talking to the cow
## (the dialogue system's test NPC), portrait. The conversations with the
## cats are in dialogue_smoke.gd.

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
var cow_line: String


func before_each() -> void:
	strings = JsonData.load_dict("res://data/strings.json")
	tuning = JsonData.load_dict("res://data/tuning.json")
	world_data = JsonData.load_dict("res://data/world.json")
	cow_line = str(JsonData.load_dict("res://data/dialogue/cow.json")["nodes"]["moo"]["text"])


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, 0.0)
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


## Very wide and squarish screens: the world (meadow, then forest) still
## reaches every edge, nothing flat past it.
const ODD_SCREENS := [
	["ultrawide", Vector2i(3440, 1440), 1.0, [0.0, 0.0, 0.0, 0.0], false],
	["superwide", Vector2i(3840, 1080), 1.0, [0.0, 0.0, 0.0, 0.0], false],
	["squarish", Vector2i(1280, 1024), 1.0, [0.0, 0.0, 0.0, 0.0], false],
	["tablet", Vector2i(1180, 820), 2.0, [24.0, 0.0, 20.0, 0.0], true],
]


func test_no_dead_margins_on_odd_screens() -> void:
	for cfg in ODD_SCREENS:
		var name: String = cfg[0]
		var app: Control = await _open(cfg)
		await _tap(app, app.metrics.safe_rect.get_center(), app.metrics)
		var g: Control = app.game
		var w = g.world
		var screen_ui := Rect2(Vector2.ZERO, app.metrics.ui_size)
		check(g.view_rect.grow(0.01).encloses(screen_ui), "%s: world view covers the screen (%s)" % [name, g.view_rect])
		# Walk to every corner: the camera never shows past the forest.
		for corner in [Vector2(8, 12), Vector2(w.size.x - 8, 12), Vector2(8, w.size.y - 2), w.size - Vector2(8, 2)]:
			w.player_pos = corner
			w.player_vel = Vector2.ZERO
			await tree.process_frame
			var WorldView := load("res://scripts/view/world_view.gd")
			check(w.camera_bounds().grow(WorldView.FOREST_REACH).encloses(g.camera_rect), "%s: forest under the camera at %s" % [name, corner])
			if not is_headless():
				var img: Image = await _screen_image()
				var letter := Color(str(JsonData.load_dict("res://data/palette.json")["ui"]["letterbox"]))
				var flat := 0
				for x in range(0, img.get_width(), 9):
					for y in [0, img.get_height() - 1]:
						if img.get_pixel(x, y).is_equal_approx(letter):
							flat += 1
				for y in range(0, img.get_height(), 9):
					for x in [0, img.get_width() - 1]:
						if img.get_pixel(x, y).is_equal_approx(letter):
							flat += 1
				check_eq(flat, 0, "%s at %s: edge pixels showing the letterbox colour" % [name, corner])
		if shots_dir != "" and not is_headless():
			await _shot(app, name)
		_close(app)
		after_each()


func test_volume_button_cycles_and_sits_by_fullscreen() -> void:
	for cfg in [PHONE, DESKTOP]:
		var app: Control = await _open(cfg)
		var vb: Control = app.volume_button
		var fb: Control = app.fullscreen_button
		var m = app.metrics
		check(vb.visible, "%s: volume button shown" % cfg[0])
		check(m.safe_rect.encloses(vb.get_global_rect()), "%s: volume button inside the safe area" % cfg[0])
		check(vb.size.x * m.px_per_unit.x / m.dpr >= 48.0 - 0.01, "%s: volume button >= 48 CSS px" % cfg[0])
		check(not vb.get_global_rect().intersects(fb.get_global_rect()), "%s: next to, not on, the fullscreen button" % cfg[0])
		check(absf(vb.get_global_rect().end.x - fb.get_global_rect().position.x) <= 1.0, "%s: just left of the fullscreen button" % cfg[0])
		var steps: Array = tuning["audio"]["volume_steps"]
		for i in steps.size():
			check_near(db_to_linear(AudioServer.get_bus_volume_db(0)) if not AudioServer.is_bus_mute(0) else 0.0, float(steps[i]), 0.01, "%s: master volume step %d" % [cfg[0], i])
			await _tap(app, vb.get_global_rect().get_center(), m)
			await tree.process_frame
		check(app.title != null, "%s: the volume button doesn't start the game" % cfg[0])
		check(not AudioServer.is_bus_mute(0), "%s: back to full volume after a full cycle" % cfg[0])
		# Fullscreen: the volume button takes the corner.
		await _tap(app, m.safe_rect.get_center(), m)
		app.relayout()
		check(not fb.visible, "%s: fullscreen button hidden while fullscreen" % cfg[0])
		check(absf(vb.get_global_rect().end.x - (m.safe_rect.end.x - 4.0)) <= 1.0, "%s: volume button moves into the corner" % cfg[0])
		_close(app)
		after_each()


func _screen_image() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return tree.root.get_texture().get_image()


func test_fullscreen_button_on_title_does_not_start_the_game() -> void:
	for cfg in [PHONE, DESKTOP]:
		var app: Control = await _open(cfg)
		var fb: Rect2 = app.fullscreen_button.get_global_rect()
		check(app.fullscreen_button.visible, "%s: button visible on the title" % cfg[0])
		# Finger / mouse down and up on the button, as separate frames.
		await _tap(app, fb.get_center(), app.metrics)
		await tree.process_frame
		await tree.process_frame
		check_eq(ScreenMetrics.fullscreen_requests, 1, "%s: button requests fullscreen" % cfg[0])
		check(app.game == null, "%s: tapping the fullscreen button does not start the game" % cfg[0])
		check(app.title != null, "%s: still on the title" % cfg[0])
		_close(app)
		after_each()


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


## Windowed browser -> fullscreen (or home-screen app), with a thumb on the
## stick during the switch. name, windowed CSS size, fullscreen CSS size, DPR,
## windowed insets, fullscreen insets.
const FULLSCREEN_SWITCHES := [
	["iphone", Vector2i(750, 342), Vector2i(844, 390), 3.0, [0.0, 47.0, 0.0, 47.0], [0.0, 47.0, 21.0, 47.0]],
	["android", Vector2i(780, 312), Vector2i(873, 393), 2.75, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]],
]


func test_touch_controls_after_entering_fullscreen_iphone() -> void:
	await _fullscreen_switch(FULLSCREEN_SWITCHES[0])


func test_touch_controls_after_entering_fullscreen_android() -> void:
	await _fullscreen_switch(FULLSCREEN_SWITCHES[1])


func _fullscreen_switch(sw: Array) -> void:
	var name: String = "fullscreen_" + sw[0]
	var dpr: float = sw[3]
	var app: Control = await _open([name, sw[1], dpr, sw[4], true])
	check(app.fullscreen_button.visible, "%s: fullscreen button shown in the browser window" % name)
	await _tap(app, app.metrics.safe_rect.get_center(), app.metrics)
	check_eq(ScreenMetrics.fullscreen_requests, 1, "%s: tap to start requests fullscreen" % name)
	var g: Control = app.game
	var tc: Control = g.touch
	var w = g.world
	w.player_pos = Vector2(150, 175)
	w.player_vel = Vector2.ZERO
	var old_rest: Vector2 = tc.stick_rest
	var old_button: Vector2 = tc.button_center
	var radius := float(tuning["touch"]["stick_radius"])
	# Thumb on the stick, pushing right...
	_touch(app, 0, old_rest, true)
	_drag(app, 0, old_rest + Vector2(radius * 0.6, 0))
	await tree.create_timer(0.2).timeout
	# ...while the browser goes fullscreen (the page resizes).
	await _resize(app, sw[2], dpr, sw[5])
	var m = app.metrics
	var safe: Rect2 = m.safe_rect
	check_near(m.ui_size.x, sw[2].x, 1.0, "%s: now fullscreen size" % name)
	check(not app.fullscreen_button.visible, "%s: fullscreen button hidden while fullscreen" % name)
	_check_view(app, name)
	_check_hud(app, name)

	# Controls re-laid out for the new safe area.
	var t: Dictionary = tuning["touch"]
	var margin := float(t["edge_margin"])
	var br := float(t["button_radius"])
	check_eq(tc.stick_rest, Vector2(safe.position.x + margin + radius, safe.end.y - margin - radius), "%s: stick rest moved to the new bottom-left" % name)
	check_eq(tc.button_center, Vector2(safe.end.x - margin - br, safe.end.y - margin - br), "%s: paw moved to the new bottom-right" % name)
	check(tc.button_center != old_button, "%s: paw button actually moved" % name)
	for r: Rect2 in [Rect2(tc.stick_rest - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), tc.button_rect()]:
		check(safe.grow(-margin + 0.01).encloses(r), "%s: control %s keeps %s px inside the safe area %s" % [name, r, margin, safe])
		check(r.size.x * m.px_per_unit.x / m.dpr >= float(t["min_target"]) - 0.01, "%s: control >= %s CSS px" % [name, t["min_target"]])
	check(not tc.button_rect().intersects(app.fullscreen_button.get_global_rect()), "%s: paw clear of the fullscreen button" % name)

	# The thumb that was down during the switch still steers, then lets go.
	var x0: float = w.player_pos.x
	_drag(app, 0, tc.stick_base + Vector2(radius * 0.6, 0))
	await tree.create_timer(0.3).timeout
	check(w.player_pos.x > x0 + 5.0, "%s: held stick still moves the cat after the switch" % name)
	_touch(app, 0, tc.stick_base + Vector2(radius * 0.6, 0), false)
	await tree.create_timer(0.3).timeout
	check_eq(tc.stick_vector, Vector2.ZERO, "%s: stick released" % name)
	check_eq(tc.stick_base, tc.stick_rest, "%s: stick returns to the new rest position" % name)
	check_eq(w.speed(), 0.0, "%s: cat stopped" % name)

	# A fresh thumb anywhere on the left still grabs the stick.
	_touch(app, 3, Vector2(safe.position.x + 120, safe.get_center().y), true)
	_drag(app, 3, Vector2(safe.position.x + 120 - radius, safe.get_center().y))
	await tree.process_frame
	check(tc.stick_vector.x < -0.5, "%s: new thumb on the left drives the stick" % name)
	_touch(app, 3, Vector2(safe.position.x + 120 - radius, safe.get_center().y), false)
	await tree.process_frame

	# The paw at its new spot talks to the cow.
	_place_next_to_cow(w)
	await tree.process_frame
	await tree.process_frame
	_touch(app, 1, tc.button_center, true)
	_touch(app, 1, tc.button_center, false)
	await tree.process_frame
	await _check_cow_talk(app, name, true)
	if not is_headless():
		await _check_view_pixels(app, name)
		if shots_dir != "":
			await _shot(app, name)
	_close(app)


func _open(cfg: Array) -> Control:
	ScreenMetrics.override_dpr = cfg[2]
	ScreenMetrics.override_insets_css = cfg[3]
	ScreenMetrics.override_touch = 1 if cfg[4] else 0
	# Pretend "not fullscreen" so requests are counted, not sent to the OS.
	ScreenMetrics.override_fullscreen = 0
	ScreenMetrics.fullscreen_requests = 0
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
	var fb_node: Control = app.fullscreen_button
	check(fb_node.visible, "%s: fullscreen button shown while not fullscreen" % name)
	var fb: Rect2 = fb_node.get_global_rect()
	check(safe.encloses(fb), "%s: fullscreen button inside safe area" % name)
	check(fb.position.x > safe.get_center().x and fb.position.y < safe.get_center().y, "%s: fullscreen button in the top-right corner" % name)
	check(fb.size.x * m.px_per_unit.x / dpr >= 48.0 - 0.01 and fb.size.y * m.px_per_unit.y / dpr >= 48.0 - 0.01, "%s: fullscreen button >= 48 CSS px" % name)
	check_near(t.cat.scale.x * m.px_per_unit.x, t.cat_scale, 0.001, "%s: title cat is whole-number scaled" % name)
	_check_hud(app, name)
	if shots_dir != "" and not is_headless():
		await _shot(app, name + "_title")

	# --- Tap to start
	await _tap(app, Vector2(safe.get_center().x, safe.end.y - 30), m)
	check(app.game != null, "%s: a tap starts the game" % name)
	check_eq(ScreenMetrics.fullscreen_requests, 1, "%s: the start tap requests fullscreen (inside the tap handler)" % name)
	app.relayout()
	check(not app.fullscreen_button.visible, "%s: fullscreen button hidden while fullscreen" % name)
	if app.game == null:
		_close(app)
		return
	await tree.process_frame
	var g: Control = app.game

	_check_view(app, name)
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


## Expand with integer scaling: k is the largest whole scale at which the
## 480x270 base fits the screen; the view then fills the screen at k (up to
## view.max), and the camera never shows past the world's edge.
func _check_view(app: Control, name: String) -> void:
	var g: Control = app.game
	var m = app.metrics
	var v: Dictionary = tuning["view"]
	var base := Vector2(v["base"][0], v["base"][1])
	var max_view := Vector2(v["max"][0], v["max"][1])
	var screen := Vector2(m.px_size)
	var expect_k := maxi(1, floori(minf(screen.x / base.x, screen.y / base.y)))
	check_eq(g.view_scale, expect_k, "%s: world view scale" % name)
	var expect_size := (screen / expect_k).ceil().min(max_view)
	check_eq(Vector2(g.view_size), expect_size, "%s: view expands to fill the screen" % name)
	check(Vector2(g.view_size).x >= base.x and Vector2(g.view_size).y >= base.y, "%s: at least the base view is visible" % name)
	var vp: Vector2 = g.view_rect.position * m.px_per_unit
	var vs: Vector2 = g.view_rect.size * m.px_per_unit
	check_near(vs.x, g.view_size.x * expect_k, 0.01, "%s: view width in device px" % name)
	check_near(vs.y, g.view_size.y * expect_k, 0.01, "%s: view height in device px" % name)
	check_near(vp.x, roundf(vp.x), 0.01, "%s: view x on a whole device px" % name)
	check_near(vp.y, roundf(vp.y), 0.01, "%s: view y on a whole device px" % name)
	var screen_ui := Rect2(Vector2.ZERO, m.ui_size)
	if expect_size == (screen / expect_k).ceil():
		check(g.view_rect.grow(0.01).encloses(screen_ui), "%s: no letterbox, the world fills the screen" % name)
	check_near(g.view_rect.get_center().x, screen_ui.get_center().x, 1.0, "%s: view centred x" % name)
	check_eq(g.viewport.size, g.view_size, "%s: SubViewport matches the view" % name)
	var lim: Rect2 = g.world.camera_bounds()
	for axis in 2:
		if g.camera_rect.size[axis] <= lim.size[axis]:
			check(g.camera_rect.position[axis] >= lim.position[axis] and g.camera_rect.end[axis] <= lim.end[axis], "%s: camera inside the meadow + forest border on axis %d (camera %s)" % [name, axis, g.camera_rect])
	check_eq(g.camera.position, g.camera_rect.position, "%s: Camera2D at the camera rect" % name)
	check(g.camera.limit_left == int(lim.position.x) and g.camera.limit_right == int(lim.end.x) and g.camera.limit_bottom == int(lim.end.y), "%s: Camera2D limits are the meadow + forest border" % name)
	# No dead margins: the world view covers the whole screen.
	check(g.view_rect.grow(0.01).encloses(screen_ui), "%s: the world reaches every edge (view %s, screen %s)" % [name, g.view_rect, screen_ui])


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
	await _check_cow_talk(app, name, true)
	# A tap on the right half away from the button does nothing.
	_touch(app, 2, Vector2(safe.end.x - 60, safe.position.y + 60), true)
	_touch(app, 2, Vector2(safe.end.x - 60, safe.position.y + 60), false)
	await tree.process_frame
	check(not g.dialogue.is_open, "%s: tapping empty space does not interact" % name)
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
	var paw: Sprite2D = g.world_view.paw
	check(paw.visible, "%s: paw prompt shown next to the cow" % name)
	var head: Vector2 = g.world_view.npc_head("cow")
	check(paw.position.y + paw.texture.get_height() <= head.y and absf(paw.position.x + paw.texture.get_width() / 2.0 - head.x) <= 1.0, "%s: paw prompt above the cow's head" % name)
	_key(KEY_E)
	await tree.process_frame
	check(not paw.visible, "%s: paw prompt hidden while the cow talks" % name)
	await _check_cow_talk(app, name, false)


## The cow's conversation is open: one "Moo!" line in the box, inside the
## safe area, movement locked. Finishes and closes it with a tap or a key.
func _check_cow_talk(app: Control, name: String, by_touch: bool) -> void:
	var g: Control = app.game
	var box: Control = g.dialogue
	check(box.is_open, "%s: dialogue box open" % name)
	check_eq(str(box.line.get("speaker", "")), "cow", "%s: the cow speaks" % name)
	check(g.world.is_talking(), "%s: talking locks movement" % name)
	check(not g.touch.visible, "%s: touch controls hidden while talking" % name)
	check(app.metrics.safe_rect.encloses(box.box_rect.grow(0.01)), "%s: box inside safe area" % name)
	await tree.create_timer(0.4).timeout
	check_eq(box.visible_text(), cow_line, "%s: cow line from cow.json" % name)
	if by_touch:
		_touch(app, 4, app.metrics.safe_rect.get_center(), true)
		_touch(app, 4, app.metrics.safe_rect.get_center(), false)
	else:
		_key(KEY_E)
	await tree.process_frame
	check(not box.is_open, "%s: the box closes after the last line" % name)
	check(not g.world.is_talking(), "%s: can move again" % name)
	check_eq(g.touch.visible, by_touch, "%s: touch controls back after talking" % name)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		tree.root.push_input(ev)


func _place_next_to_cow(w) -> void:
	var cow: Rect2 = w.npc_by_id("cow")["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(cow.position.x - w.player_footprint.x / 2.0 - 4.0, cow.end.y)


## The world view on screen must be the SubViewport image scaled by exactly k:
## every world pixel covers k x k device pixels of one colour.
func _check_view_pixels(app: Control, name: String) -> void:
	var g: Control = app.game
	var touch_was: bool = g.touch.visible
	var paused_was: bool = g.paused
	g.paused = true  # freeze overlay updates (hiding touch would show the keyboard prompt)
	g.touch.visible = false
	app.hud.visible = false
	app.volume_button.visible = false
	var box_was: bool = g.dialogue.visible
	g.dialogue.visible = false
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
				var sp: Vector2i = origin + Vector2i(x, y) * k + corner
				if sp.x < 0 or sp.y < 0 or sp.x >= shot.get_width() or sp.y >= shot.get_height():
					continue  # the expanded view may overhang the screen by < k px
				var s := shot.get_pixelv(sp)
				checked += 1
				if absf(s.r - c.r) > 0.02 or absf(s.g - c.g) > 0.02 or absf(s.b - c.b) > 0.02:
					bad_box = Rect2i(x, y, 1, 1) if bad == 0 else bad_box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
					bad += 1
	check_eq(bad, 0, "%s: device pixels that don't match their world pixel (of %d checked; bad world pixels in %s; k=%d origin=%s)" % [name, checked, bad_box, k, origin])
	g.touch.visible = touch_was
	g.paused = paused_was
	g.dialogue.visible = box_was
	app.hud.visible = true
	app.volume_button.visible = true


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

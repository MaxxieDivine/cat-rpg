extends "res://tests/test_base.gd"
## Polish P2 on the real game screen: soft paw steps follow Fern's legs.
## - desktop, keyboard: walking gives evenly spaced steps in paw order,
##   trotting (Shift) gives pairs with gaps; standing still is silent;
## - phone, touch: the joystick walks and (pushed past stick_trot) trots
##   with the same rhythm;
## - gamepad: the left stick walks, B trots;
## - ?steps=classic (Settings.footsteps) brings back the old footsteps.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const MAIN_SCENE := "res://scenes/app.tscn"
const PHONE := ["phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

## The most Fern moved in one frame while recording: steps are only seen once
## a frame, so measured gaps are off by up to this (slow xvfb frames: ~5 px).
var _frame_px := 0.0


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	Settings.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	_stick(JOY_AXIS_LEFT_X, 0.0)


func test_keyboard_walk_and_trot() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	check_eq(g.sound.footstep_style(), "soft", "soft footsteps by default")
	_open_ground(g)
	var walk := await _record(g, func(on: bool) -> void: _hold("move_right", on), 1.6)
	_check_walk(walk, "keyboard")
	g.world.player_vel = Vector2.ZERO
	await _frames(30)
	var before: int = g.sound.played.get("paw", 0)
	await _frames(30)
	check_eq(int(g.sound.played.get("paw", 0)), before, "standing still: no steps")
	_open_ground(g)
	var run := await _record(g, func(on: bool) -> void:
		_hold("run", on)
		_hold("move_right", on), 1.6)
	_check_run(run, "keyboard")
	_close(app)


func test_touch_walk_and_trot() -> void:
	var app: Control = await _start(PHONE)
	var g: Control = app.game
	var tc: Control = g.touch
	_open_ground(g)
	var walk := await _record(g, func(on: bool) -> void:
		_touch(app, 0, tc.stick_rest, on)
		if on:
			_drag(app, 0, tc.stick_rest + Vector2(tc.stick_radius * 0.8, 0.0)), 1.6)
	_check_walk(walk, "touch")
	_open_ground(g)
	var run := await _record(g, func(on: bool) -> void:
		_touch(app, 0, tc.stick_rest, on)
		if on:
			_drag(app, 0, tc.stick_rest + Vector2(tc.stick_radius * 1.0, 0.0)), 1.6)
	_check_run(run, "touch")
	_close(app)


func test_gamepad_walk_and_trot() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_open_ground(g)
	var walk := await _record(g, func(on: bool) -> void: _stick(JOY_AXIS_LEFT_X, 1.0 if on else 0.0), 1.6)
	_check_walk(walk, "gamepad")
	_open_ground(g)
	var run := await _record(g, func(on: bool) -> void:
		_pad(JOY_BUTTON_B, on)
		_stick(JOY_AXIS_LEFT_X, 1.0 if on else 0.0), 1.6)
	_check_run(run, "gamepad")
	_close(app)


func test_classic_footsteps_stay_available() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	Settings.footsteps = "classic"
	_open_ground(g)
	var paws: int = g.sound.played.get("paw", 0)
	await _record(g, func(on: bool) -> void: _hold("move_right", on), 0.8)
	var classic := int(g.sound.played.get("step_grass", 0)) + int(g.sound.played.get("step_path", 0))
	check(classic >= 3, "the old footsteps play (%d)" % classic)
	check_eq(int(g.sound.played.get("paw", 0)), paws, "and the new ones don't")
	_close(app)


# --- checks


## Walk: paws in order BL FL BR FR, evenly spaced (a quarter stride).
func _check_walk(steps: Array, how: String) -> void:
	if not check(steps.size() >= 6, "%s: walking plays steps (%d)" % [how, steps.size()]):
		return
	var g_stride: float = 36.0
	var order := ["back_left", "front_left", "back_right", "front_right"]
	var ok_order := true
	var ok_even := true
	for i in range(2, steps.size()):
		var a: Dictionary = steps[i - 1]
		var b: Dictionary = steps[i]
		ok_order = ok_order and order[(order.find(a["paw"]) + 1) % 4] == b["paw"]
		ok_even = ok_even and absf(b["d"] - a["d"] - g_stride / 4.0) <= _frame_px + 0.5
		ok_order = ok_order and not b["running"]
	check(ok_order, "%s: walk paws in order %s" % [how, steps.map(func(s): return s["paw"])])
	check(ok_even, "%s: evenly spaced %s" % [how, _gaps(steps)])
	check(steps.all(func(s): return s["pitch"] < 0.95), "%s: low pitch" % how)


## Run: back pair close, front pair close, a gap between pairs (the tuned
## gaps are 0.1 and 0.35 / 0.45 of a 56 px stride; split halfway between).
func _check_run(steps: Array, how: String) -> void:
	if not check(steps.size() >= 6, "%s: trotting plays steps (%d)" % [how, steps.size()]):
		return
	var shorts := 0
	var longs := 0
	var ok := true
	for i in range(2, steps.size()):
		var gap: float = steps[i]["d"] - steps[i - 1]["d"]
		var paw: String = steps[i]["paw"]
		var second := paw == "back_right" or paw == "front_right"
		if second:
			shorts += 1
			ok = ok and gap <= 5.6 + _frame_px + 0.5
		else:
			longs += 1
			ok = ok and gap >= 19.6 - _frame_px - 0.5
	check(_frame_px < 7.0, "%s: frames fine enough to hear the pairs (%.1f px)" % [how, _frame_px])
	check(ok and shorts >= 2 and longs >= 2, "%s: paired run rhythm %s (frame %.1f px)" % [how, _gaps(steps), _frame_px])
	check(steps.all(func(s): return s["running"]), "%s: run steps" % how)


func _gaps(steps: Array) -> Array:
	var out: Array = []
	for i in range(1, steps.size()):
		out.append(snappedf(steps[i]["d"] - steps[i - 1]["d"], 0.1))
	return out


# --- helpers


## Holds the input (`press` true / false) for `seconds`, recording every paw
## step with Fern's distance walked when it played. Skips the first steps
## (speeding up, the gait switching).
func _record(g: Control, press: Callable, seconds: float) -> Array:
	press.call(true)
	var out: Array = []
	var seen: int = g.sound.step_log.size()
	var t := 0.0
	_frame_px = 0.0
	var was: float = g.world.distance
	while t < seconds:
		await tree.process_frame
		if t > 0.25:
			_frame_px = maxf(_frame_px, g.world.distance - was)
		was = g.world.distance
		t += tree.root.get_process_delta_time() if tree.root.get_process_delta_time() > 0.0 else 1.0 / 60.0
		var log: Array = g.sound.step_log
		var n := log.size()
		for i in range(mini(seen, n), n):
			var st: Dictionary = log[i].duplicate()
			st["d"] = g.world.distance
			if t > 0.25:
				out.append(st)
		seen = n
		if n >= 60:
			g.sound.step_log.clear()
			seen = 0
	press.call(false)
	await _frames(10)
	return out


## Puts Fern at the west end of an open, grassy strip of the Hunting Grounds
## facing east.
func _open_ground(g: Control) -> void:
	if g.world.id != "hunting_grounds":
		g.load_area("hunting_grounds", "start")
	g.world.player_pos = Vector2(260, 300)
	g.world.player_vel = Vector2.ZERO
	g.gait.reset(g.world.distance)


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _pad(button: JoyButton, on: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = on
	# Through Input, like a real pad, so the actions see it.
	Input.parse_input_event(ev)


func _stick(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


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
	check(app.game != null and app.game.sound != null, "%s: game started with sound" % cfg[0])
	return app


func _close(app: Control) -> void:
	DialogueManager.stop()
	tree.root.remove_child(app)
	app.free()

extends "res://tests/test_base.gd"
## The real game screen hunting: touch Crouch / Pounce / Eat buttons (size,
## place, dimmed / lit), stalking and pouncing by touch, keyboard and
## gamepad, the landing ring, the "!" and alert bars, carrying the mouse home
## and dropping it on the pile, eating it, losing it by passing out, and the
## debug mouse spawner. With a display it saves screenshots (hunt_*).

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const World := preload("res://scripts/core/world.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

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
	Hunting.reset()
	Settings.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact", "crouch", "pounce"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func test_touch_buttons_target_phone() -> void:
	await _buttons(TARGET_PHONE)


func test_touch_buttons_phone() -> void:
	await _buttons(PHONE)


## Crouch and Pounce: big enough for a thumb, inside the safe area, clear of
## each other, the paw, the joystick, the bars and the corner buttons; only
## where there are mice.
func _buttons(cfg: Array) -> void:
	var app: Control = await _start(cfg)
	var g: Control = app.game
	var tc: Control = g.touch
	var name: String = cfg[0]
	check(not tc.hunt_buttons, "%s: no Crouch / Pounce in camp" % name)
	await _to_grounds(g)
	check(tc.hunt_buttons, "%s: Crouch / Pounce in the Hunting Grounds" % name)
	var m = app.metrics
	var css: float = m.px_per_unit.y / m.dpr
	var cm_css := 96.0 / 2.54  # 1 cm in CSS px
	for pair in [["crouch", tc.crouch_rect()], ["pounce", tc.pounce_rect()]]:
		var r: Rect2 = pair[1]
		check(r.size.y * css >= cm_css, "%s: %s at least 1 cm (%.0f CSS px)" % [name, pair[0], r.size.y * css])
		check(m.safe_rect.encloses(r), "%s: %s inside the safe area" % [name, pair[0]])
		check(not r.intersects(tc.button_rect()), "%s: %s clear of the paw" % [name, pair[0]])
		check(r.position.x > m.safe_rect.get_center().x, "%s: %s on the right (thumb) side" % [name, pair[0]])
		check(not r.intersects(g.needs_hud.hud_rect), "%s: %s clear of the bars" % [name, pair[0]])
		check(not r.intersects(Rect2(app.volume_button.position, app.volume_button.size)), "%s: %s clear of the volume button" % [name, pair[0]])
	check(not tc.crouch_rect().intersects(tc.pounce_rect()), "%s: crouch and pounce don't overlap" % name)
	check(tc.pounce_shown() and not tc.can_pounce, "%s: Pounce shown, dimmed with no mouse in range" % name)
	_close(app)


func test_stalk_and_pounce_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	var tc: Control = g.touch
	await _to_grounds(g)
	_freeze_needs(30, 70)
	await _tap(app, tc.crouch_center)
	check(tc.crouch_on, "the Crouch button toggles crouch on")
	await _frames(2)
	check(g.world.crouching, "Fern crouches")
	check_eq(g.world_view.player.anim, "stretch", "crouched pose (low stretch frames)")
	var m := _ready_mouse(g, "feed", 28.0)
	await _frames(3)
	check(tc.can_pounce, "Pounce lights up with a mouse in range")
	check(g.world_view.ring.visible, "landing ring on the mouse")
	check((g.world_view.ring.position - (m["pos"] as Vector2).round()).length() <= 2.0, "ring at the mouse")
	if not is_headless():
		await _frames(10)
		_save(await _screen(), "hunt_ring_target_phone")
	await _tap(app, tc.pounce_center)
	check(g.world.is_leaping(), "the Pounce button leaps")
	check(g.sound.played.get("pounce", 0) >= 1, "pounce sound")
	await _until(func() -> bool: return not g.world.is_leaping() and not g.world.is_busy())
	check_eq(Player.carried_item(), "mouse", "caught it")
	check(g.sound.played.get("catch", 0) >= 1, "catch sound")
	check(g.world_view.mouth.visible, "the mouse is in Fern's mouth")
	check(tc.eat_shown() and not tc.pounce_shown(), "Eat replaces Pounce while carrying")
	await _tap(app, tc.crouch_center)
	check(not tc.crouch_on, "Crouch toggles off")
	if not is_headless():
		await _frames(10)
		_save(await _screen(), "hunt_carry_target_phone")
	await _tap(app, tc.pounce_center)
	check_eq(Needs.hunger(), 30 + int(tuning["needs"]["eat"]), "the Eat button eats it: +hunger")
	check_eq(Player.carried_item(), "", "gone")
	check_eq(g.message.text, str(strings["hunt.ate"]), "a short line says so")
	_close(app)


func test_keyboard_hunt_carry_home_and_deliver() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	await _to_grounds(g)
	_freeze_needs(50, 70)
	Input.action_press("crouch")
	var m := _ready_mouse(g, "look", 50.0)
	await _frames(3)
	check(g.world.crouching, "holding C crouches")
	check(g.world_view.mouse_marks[m["id"]].visible, "'!' over a mouse with its head up")
	check(g.world_view.mouse_nodes[m["id"]].frame == 2, "head-up pose")
	# Red light: holding still doesn't scare it.
	await _frames(30)
	check_eq(m["alert"], 0.0, "still while it looks: alert stays 0")
	if not is_headless():
		_save(await _screen(), "hunt_look_desktop")
	# Green light: it feeds, creep in.
	_hold(m, "feed")
	Input.action_press("move_right")
	await _until(func() -> bool: return g.world.can_pounce(), 4000)
	Input.action_release("move_right")
	check(g.world.can_pounce(), "crept into range")
	check_eq(m["alert"], 0.0, "creeping while it fed raised nothing")
	_key(KEY_SPACE)
	await _frames(2)
	check(g.world.is_leaping() or Player.carried_item() == "mouse", "Space pounces")
	await _until(func() -> bool: return not g.world.is_leaping() and not g.world.is_busy())
	Input.action_release("crouch")
	check_eq(Player.carried_item(), "mouse", "caught")
	# Carry it home.
	g.load_area("camp", "from_hunting")
	await _frames(2)
	check_eq(Player.carried_item(), "mouse", "still carrying in camp")
	check(g.world_view.mouth.visible, "mouse still in her mouth")
	var w = g.world
	var before: int = w.pile["prey"]
	var r: Rect2 = w.pile["rect"]
	w.player_pos = Vector2(r.end.x + w.player_footprint.x / 2.0 + 4.0, r.end.y)
	await _frames(2)
	_key(KEY_E)
	await _frames(2)
	check_eq(w.pile["prey"], before + 1, "dropped on the pile: +1")
	check_eq(g.world_view.pile.frame, before + 1, "the pile looks fuller")
	check_eq(Player.carried_item(), "", "mouth empty")
	check_eq(Needs.hunger(), 50, "delivering doesn't feed Fern")
	if not is_headless():
		await _frames(20)
		_save(await _screen(), "hunt_delivered_desktop")
	_close(app)


func test_moving_while_it_looks_scares_it() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	await _to_grounds(g)
	_freeze_needs(70, 70)
	var m := _ready_mouse(g, "look", 50.0)
	Input.action_press("move_right")
	await _until(func() -> bool: return m["state"] == "flee", 3000)
	Input.action_release("move_right")
	check_eq(m["state"], "flee", "walking up while it looks: it bolts")
	check(g.sound.played.get("flee", 0) >= 1, "a squeak as it runs")
	await _until(func() -> bool: return g.world.hunt.mouse_by_id(m["id"]).is_empty(), 4000)
	check(g.world.hunt.mouse_by_id(m["id"]).is_empty(), "gone into the grass")
	await _frames(2)
	check(not g.world_view.mouse_nodes.has(m["id"]), "its sprite is gone too")
	_close(app)


func test_gamepad_crouch_and_pounce() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	await _to_grounds(g)
	_freeze_needs(70, 70)
	_pad(JOY_BUTTON_LEFT_SHOULDER, true)
	_ready_mouse(g, "feed", 28.0)
	await _frames(3)
	check(g.world.crouching, "a held shoulder button crouches")
	check(g.world.can_pounce(), "in range")
	_pad(JOY_BUTTON_A, true)
	_pad(JOY_BUTTON_A, false)
	await _until(func() -> bool: return not g.world.is_leaping() and not g.world.is_busy())
	_pad(JOY_BUTTON_LEFT_SHOULDER, false)
	check_eq(Player.carried_item(), "mouse", "South pounces and catches")
	_close(app)


func test_passing_out_loses_the_mouse() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	await _to_grounds(g)
	g.travel.lie_s = 0.1
	g.travel.collapse_fade_s = 0.1
	g.travel.message_s = 0.2
	g.travel.wake_s = 0.1
	Player.state.carried_item = "mouse"
	await _frames(2)
	check(g.world_view.mouth.visible, "carrying")
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("thirst", 0)
	await _until(func() -> bool: return g.world.id == "camp" and not g.travel.busy(), 6000)
	check_eq(Player.carried_item(), "", "the mouse is lost")
	check(not g.world_view.mouth.visible, "nothing in her mouth")
	_close(app)


func test_debug_mouse_spawner_and_label() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	await _to_grounds(g)
	_freeze_needs(70, 70)
	Settings.debug_overlay = true
	for m in g.world.hunt.mice.duplicate():
		g.world.hunt._remove(m)
	var spot: Dictionary = g.world.hunt.spots[2]
	g.world.player_pos = (spot["pos"] as Vector2) + Vector2(-40, 10)
	await _frames(1)
	_key(KEY_M)
	await _frames(2)
	check(g.world.hunt.mice.any(func(m): return m["spot"] == 2), "M puts a mouse at the nearest prey spot")
	app._update_hud()
	check(app.hud.text.contains(spot["id"]), "the label lists the mouse (%s)" % app.hud.text)
	check(app.hud.text.contains("down") or app.hud.text.contains("UP"), "with head up / down")
	check(app.debug_buttons.size() == 3 and app.debug_buttons[2].visible, "a Mouse button too")
	_close(app)


# --- helpers


## A mouse held in `state` with Fern `gap` px to its left, crouch as it is.
func _ready_mouse(g: Control, state: String, gap: float) -> Dictionary:
	var h = g.world.hunt
	if h.mice.is_empty():
		h.spawn_at(0)
	var m: Dictionary = h.mice[0]
	_hold(m, state)
	m["alert"] = 0.0
	m["squeak_t"] = 999.0
	g.world.player_pos = (m["pos"] as Vector2) - Vector2(gap, 0)
	g.world.player_vel = Vector2.ZERO
	g.world.facing = 1
	return m


func _hold(m: Dictionary, state: String) -> void:
	m["state"] = state
	m["t"] = 999.0
	m["wander_t"] = 999.0
	m["wander_to"] = m["pos"]


func _to_grounds(g: Control) -> void:
	g.load_area("hunting_grounds", "from_camp")
	await _frames(2)


func _freeze_needs(h: int, t: int) -> void:
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", h)
	Needs.set_value("thirst", t)


func _until(cond: Callable, ms: int = 3000) -> void:
	var until := Time.get_ticks_msec() + ms
	while not cond.call() and Time.get_ticks_msec() < until:
		await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _tap(app: Control, ui_pos: Vector2) -> void:
	_touch(app, 4, ui_pos, true)
	await tree.process_frame
	_touch(app, 4, ui_pos, false)
	await tree.process_frame


func _pad(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


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

extends "res://tests/test_base.gd"
## The Name Editor in the real game scene: asking Sorrel (the name-giver,
## data/names/naming.json) for a new name, the editor over the paused world,
## wheels by tap, swipe, mouse wheel, keyboard and gamepad, the tabs, locks
## and Randomize, blocked names, Confirm and Cancel, the new name in her
## reply and in later lines and name plates, and the debug shortcut. With a
## display it also checks pixels and saves screenshots (name_editor_*).

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const NamePicker := preload("res://scripts/core/name_picker.gd")
const Names := preload("res://scripts/core/names.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

## name, CSS size, devicePixelRatio, insets [top, right, bottom, left] (CSS px), touch
const PHONE := ["phone", Vector2i(844, 390), 3.0, [0.0, 47.0, 21.0, 47.0], true]
const SMALL_PHONE := ["small_phone", Vector2i(667, 375), 2.0, [0.0, 0.0, 0.0, 0.0], true]
const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var tuning: Dictionary
var names
var _renamed: Array[String] = []


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	names = Names.shared()
	_renamed = []


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	Settings.debug_overlay = false


# --- Touch


func test_rename_by_touch_on_phones() -> void:
	for cfg in [TARGET_PHONE, SMALL_PHONE, PHONE]:
		await _rename_by_touch(cfg)


func _rename_by_touch(cfg: Array) -> void:
	var name: String = cfg[0]
	var app: Control = await _start(cfg)
	var g: Control = app.game
	var ed: Control = g.name_editor
	var m = app.metrics
	GameState.name_changed.connect(_on_renamed)
	var start_name := GameState.get_player_name()
	await _to_editor(app, true)
	if not check(ed.is_open, "%s: asking Sorrel opens the Name Editor" % name):
		_close(app)
		return
	check(not g.dialogue.is_open, "%s: the dialogue box steps aside" % name)
	check(g.world.is_talking(), "%s: Fern stays put (talk lock)" % name)
	check(not g.touch.visible, "%s: no joystick behind the editor" % name)
	await _until(func() -> bool: return not ed.animating(), 1.0)
	check(not ed.animating(), "%s: open animation done" % name)

	# The world waits: no needs drain, no time of day.
	var hunger_t: float = Needs.needs._hunger_t
	var day_t: float = g.day.t
	await tree.create_timer(0.4).timeout
	check_eq(Needs.needs._hunger_t, hunger_t, "%s: needs don't drain behind the editor" % name)
	check_eq(g.day.t, day_t, "%s: time of day waits" % name)

	# Layout: inside the safe area, big enough for thumbs.
	check(m.safe_rect.encloses(ed.panel_rect), "%s: panel inside the safe area (%s in %s)" % [name, ed.panel_rect, m.safe_rect])
	var min_css := float(tuning["name_editor"]["min_target_css"])
	var targets: Array[Rect2] = [ed.random_rect, ed.cancel_rect, ed.confirm_rect]
	targets.append_array(ed.up_rects)
	targets.append_array(ed.down_rects)
	targets.append_array(ed.lock_rects)
	targets.append_array(ed.tab_rects)
	for r in targets:
		var css := _css(m, r.size.y)
		check(css >= min_css, "%s: target %s is %.1f CSS px tall (>= %s, about 1 cm)" % [name, r, css, min_css])
		check(_css(m, r.size.x) >= min_css * 0.9, "%s: target %s wide enough" % [name, r])
	check_eq(ed.shown_name(), names.build(GameState.state.prefix_id, ed.picker.suffix_id()), "%s: opens on the current prefix" % name)
	check(not app.volume_button.visible and not app.fullscreen_button.visible, "%s: no corner buttons over the panel" % name)
	if not is_headless():
		_save(await _screen(), "name_editor_" + name)

	# Arrows.
	var p0: String = ed.picker.prefix_id()
	await _tap_at(app, ed.down_rects[0].get_center())
	check(ed.picker.prefix_id() != p0, "%s: the down arrow scrolls the prefix" % name)
	check_eq(ed.shown_name(), names.build(ed.picker.prefix_id(), ed.picker.suffix_id()), "%s: the preview follows at once" % name)
	await _tap_at(app, ed.up_rects[0].get_center())
	check_eq(ed.picker.prefix_id(), p0, "%s: and the up arrow back" % name)

	# Swipe up three words on the suffix wheel.
	var si: int = ed.picker.index[NamePicker.SUFFIX]
	var n_suf: int = ed.picker.suffix_list.size()
	var step: float = float(tuning["name_editor"]["swipe_px"]) * ed.unit
	await _swipe(app, ed.wheel_rects[1].get_center() + Vector2(-20, step * 1.5), -step * 3.2)
	check_eq(ed.picker.index[NamePicker.SUFFIX], posmod(si + 3, n_suf), "%s: swiping up moves the suffix three words" % name)
	check_eq(ed.picker.focus, NamePicker.SUFFIX, "%s: the swiped wheel has focus" % name)
	await _swipe(app, ed.wheel_rects[1].get_center() + Vector2(-20, -step * 1.5), step * 1.2)
	check_eq(ed.picker.index[NamePicker.SUFFIX], posmod(si + 2, n_suf), "%s: swiping down moves it back one" % name)

	# Tabs.
	var weather: int = ed.picker.tabs().find("Weather")
	await _tap_at(app, ed.tab_rects[weather].get_center())
	check_eq(ed.picker.category_name(), "Weather", "%s: the Weather tab" % name)
	check_eq(str(ed.picker.word(NamePicker.PREFIX)["category"]), "Weather", "%s: a weather prefix" % name)
	await _tap_at(app, ed.tab_rects[ed.tab_rects.size() - 1].get_center())
	check_eq(ed.picker.category_name(), "All", "%s: back to All" % name)

	# Lock the prefix, randomize: only the suffix changes.
	await _tap_at(app, ed.lock_rects[0].get_center())
	check(ed.picker.locked[0], "%s: the prefix lock is on" % name)
	var locked_prefix: String = ed.picker.prefix_id()
	var suffixes := {}
	for i in 6:
		await _tap_at(app, ed.random_rect.get_center())
		check_eq(ed.picker.prefix_id(), locked_prefix, "%s: Randomize keeps the locked prefix" % name)
		check(ed.picker.can_confirm(), "%s: rolled names are allowed" % name)
		suffixes[ed.picker.suffix_id()] = true
	check(suffixes.size() >= 2, "%s: the suffix rolls" % name)
	await _tap_at(app, ed.lock_rects[0].get_center())
	check(not ed.picker.locked[0], "%s: unlocked" % name)

	# A blocked name can't be confirmed.
	ed.picker.open("moss", "step")
	await _frames(2)
	check(not ed.picker.can_confirm(), "%s: Mossstep is blocked" % name)
	check(ed.note() != "", "%s: with a note (%s)" % [name, ed.note()])
	if not is_headless():
		_save(await _screen(), "name_editor_blocked_" + name)
	await _tap_at(app, ed.confirm_rect.get_center())
	await _frames(3)
	check(ed.is_open, "%s: Confirm does nothing while blocked" % name)
	check_eq(GameState.get_player_name(), start_name, "%s: name unchanged" % name)

	# Pick Birchsong with the wheels and confirm.
	ed.picker.open("birch", "song")
	await _frames(1)
	await _tap_at(app, ed.down_rects[1].get_center())
	await _tap_at(app, ed.up_rects[1].get_center())
	check_eq(ed.shown_name(), "Birchsong", "%s: Birchsong shown" % name)
	await _tap_at(app, ed.confirm_rect.get_center())
	check_eq(GameState.get_player_name(), "Birchsong", "%s: confirmed at once" % name)
	check(_renamed.has("Birchsong"), "%s: name_changed fired" % name)
	await _until(func() -> bool: return not ed.is_open, 2.0)
	check(not ed.is_open, "%s: editor closes after the sparkle" % name)
	await _until(func() -> bool: return g.dialogue.is_open, 1.0)
	check(g.dialogue.is_open and str(g.dialogue.line.get("node", "")) == "named", "%s: Sorrel's reply" % name)
	check(str(g.dialogue.line.get("text", "")).contains("Birchsong"), "%s: her reply uses the new name (%s)" % [name, g.dialogue.line.get("text", "")])
	await _finish_conversation(app, true)
	check(not g.world.is_talking(), "%s: free to walk again" % name)
	check(g.touch.visible, "%s: joystick back" % name)
	check(app.volume_button.visible, "%s: the volume button is back" % name)

	# Later lines: Bram's repeat names her, and so does her own plate.
	GameState.set_flag("talked_bram", true)
	await _open_talk(app, "bram", true)
	check(str(g.dialogue.line.get("text", "")).contains("Birchsong"), "%s: Bram uses the new name (%s)" % [name, g.dialogue.line.get("text", "")])
	await _finish_conversation(app, true)
	# Ask again and cancel: the old (new) name stays.
	await _to_editor(app, true)
	check(ed.is_open, "%s: editor again" % name)
	await _frames(2)
	await _tap_at(app, ed.down_rects[0].get_center())
	await _tap_at(app, ed.cancel_rect.get_center())
	check(not ed.is_open, "%s: Cancel closes" % name)
	check_eq(GameState.get_player_name(), "Birchsong", "%s: Cancel keeps the name" % name)
	await _until(func() -> bool: return g.dialogue.is_open, 1.0)
	check_eq(str(g.dialogue.line.get("node", "")), "kept", "%s: Sorrel's cancel line" % name)
	check(str(g.dialogue.line.get("text", "")).contains("Birchsong"), "%s: with the name" % name)
	await _finish_conversation(app, true)
	GameState.name_changed.disconnect(_on_renamed)
	_close(app)


func _on_renamed(n: String) -> void:
	_renamed.append(n)


# --- Keyboard, mouse and gamepad


func test_rename_by_keyboard_and_mouse_on_desktop() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var ed: Control = g.name_editor
	var start_name := GameState.get_player_name()
	await _to_editor(app, false)
	if not check(ed.is_open, "desktop: E through Sorrel's lines opens the editor"):
		_close(app)
		return
	await _frames(2)
	check_eq(ed.picker.focus, NamePicker.PREFIX, "the prefix wheel has focus first")
	var pi: int = ed.picker.index[0]
	var si: int = ed.picker.index[1]
	_key(KEY_RIGHT)
	_key(KEY_DOWN)
	_key(KEY_DOWN)
	await _frames(1)
	check_eq(ed.picker.focus, NamePicker.SUFFIX, "Right: suffix")
	check_eq(ed.picker.index[1], posmod(si + 2, ed.picker.suffix_list.size()), "Down twice: two suffixes on")
	_key(KEY_LEFT)
	_key(KEY_UP)
	await _frames(1)
	check_eq(ed.picker.index[0], posmod(pi - 1, ed.picker.prefix_list.size()), "Left, Up: the prefix before")
	check_eq(ed.shown_name(), names.build(ed.picker.prefix_id(), ed.picker.suffix_id()), "the preview follows")
	# The mouse wheel over the suffix wheel.
	await _wheel(app, ed.wheel_rects[1].get_center(), false)
	check_eq(ed.picker.index[1], posmod(si + 3, ed.picker.suffix_list.size()), "mouse wheel down: one more suffix")
	# Tab cycles the categories.
	_key(KEY_TAB)
	await _frames(1)
	check_eq(ed.picker.category_name(), ed.picker.tabs()[0], "Tab: the first category")
	# L locks the focused wheel, R randomizes.
	_key(KEY_LEFT)
	_key(KEY_L)
	await _frames(1)
	var locked_prefix: String = ed.picker.prefix_id()
	for i in 5:
		_key(KEY_R)
		await _frames(1)
		check_eq(ed.picker.prefix_id(), locked_prefix, "R keeps the locked prefix")
	if not is_headless():
		_save(await _screen(), "name_editor_desktop")
	# Esc cancels.
	_key(KEY_ESCAPE)
	await _frames(2)
	check(not ed.is_open, "Esc cancels")
	check_eq(GameState.get_player_name(), start_name, "the old name stays")
	await _until(func() -> bool: return g.dialogue.is_open, 1.0)
	check_eq(str(g.dialogue.line.get("node", "")), "kept", "Sorrel's cancel line")
	await _finish_conversation(app, false)
	# Again, Enter confirms.
	await _to_editor(app, false)
	await _frames(2)
	ed.picker.open("clover", "tail")
	_key(KEY_RIGHT)
	_key(KEY_DOWN)
	await _frames(1)
	var want: String = ed.shown_name()
	_key(KEY_ENTER)
	await _until(func() -> bool: return not ed.is_open, 2.0)
	check_eq(GameState.get_player_name(), want, "Enter confirms %s" % want)
	await _until(func() -> bool: return g.dialogue.is_open, 1.0)
	check(str(g.dialogue.line.get("text", "")).contains(want), "the reply names %s" % want)
	# Her plate in a Fern line shows it too: ask again.
	await _finish_conversation(app, false)
	await _open_talk(app, "sorrel", false)
	await _keys_until_choices(app)
	_key(KEY_E)  # "Can I have a new name?"
	await _frames(2)
	check_eq(str(g.dialogue.line.get("speaker", "")), names.player_speaker(), "Fern echoes the choice")
	check_eq(g.dialogue.name_label.text, want, "Fern's name plate shows the new name")
	_close(app)


func test_gamepad_drives_the_editor() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var ed: Control = g.name_editor
	var start_name := GameState.get_player_name()
	check(g.open_name_editor(), "the editor opens outside a conversation (debug)")
	await _frames(2)
	var si: int = ed.picker.index[1]
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	check_eq(ed.picker.focus, NamePicker.SUFFIX, "d-pad right: suffix")
	check_eq(ed.picker.index[1], posmod(si + 1, ed.picker.suffix_list.size()), "d-pad down: next suffix")
	_stick(JOY_AXIS_LEFT_Y, 1.0)
	_stick(JOY_AXIS_LEFT_Y, 0.0)
	await _frames(1)
	check_eq(ed.picker.index[1], posmod(si + 2, ed.picker.suffix_list.size()), "stick down: one more")
	_stick(JOY_AXIS_LEFT_X, -1.0)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await _frames(1)
	check_eq(ed.picker.focus, NamePicker.PREFIX, "stick left: prefix")
	_pad(JOY_BUTTON_Y)
	await _frames(1)
	check(ed.picker.locked[0], "North locks the prefix")
	var p: String = ed.picker.prefix_id()
	for i in 4:
		_pad(JOY_BUTTON_X)
		await _frames(1)
		check_eq(ed.picker.prefix_id(), p, "West randomizes, prefix kept")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(1)
	check_eq(ed.picker.category_name(), ed.picker.tabs()[0], "a shoulder changes the tab")
	_pad(JOY_BUTTON_B)
	await _frames(2)
	check(not ed.is_open, "East cancels")
	check_eq(GameState.get_player_name(), start_name, "name kept")
	check(not g.world.is_talking(), "no conversation to resume")
	g.open_name_editor()
	await _frames(2)
	_pad(JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	var want: String = ed.shown_name()
	_pad(JOY_BUTTON_A)
	await _until(func() -> bool: return not ed.is_open, 2.0)
	check_eq(GameState.get_player_name(), want, "South confirms")
	_close(app)


func test_debug_key_opens_the_editor_anywhere() -> void:
	var app: Control = await _start(PHONE)
	var g: Control = app.game
	_key(KEY_N)
	await _frames(1)
	check(not g.name_editor.is_open, "N does nothing without the debug overlay")
	Settings.debug_overlay = true
	await _frames(1)
	_key(KEY_N)
	await _frames(2)
	check(g.name_editor.is_open, "N opens the editor")
	var x: float = g.world.player_pos.x
	Input.action_press("move_right")
	await _frames(5)
	Input.action_release("move_right")
	check_eq(g.world.player_pos.x, x, "the world is paused behind it")
	_key(KEY_ESCAPE)
	await _frames(2)
	check(not g.name_editor.is_open, "Esc closes it")
	app._place_hud()
	var b: Array = app.debug_buttons.filter(func(b: Button) -> bool: return b.name == "Debug_name")
	check(b.size() == 1 and b[0].visible, "a Name debug button")
	if b.size() == 1:
		b[0].pressed.emit()
		await _frames(2)
		check(g.name_editor.is_open, "the button opens it")
		g.name_editor.cancel()
	for d: Button in app.debug_buttons:
		check(app.metrics.safe_rect.encloses(Rect2(d.position, d.size)), "debug button %s inside the safe area" % d.name)
	_close(app)


func test_editor_pixels_are_whole_and_crisp() -> void:
	if is_headless():
		return
	for cfg in [TARGET_PHONE, DESKTOP]:
		var app: Control = await _start(cfg)
		var g: Control = app.game
		var ed: Control = g.name_editor
		var m = app.metrics
		g.open_name_editor()
		await _frames(15)
		var img: Image = await _screen()
		# Paper just inside the frame, and the k x k block around it.
		var px := Vector2i((ed.panel_rect.position + Vector2(ed.panel_rect.size.x / 2.0, 4.5 * ed.unit)) * m.px_per_unit)
		var paper := Color(str(JsonData.load_dict("res://data/palette.json")["ui"]["paper"]))
		var c := img.get_pixelv(px)
		check(absf(c.r - paper.r) < 0.03 and absf(c.g - paper.g) < 0.03 and absf(c.b - paper.b) < 0.03, "%s: paper inside the panel (%s)" % [cfg[0], c.to_html(false)])
		# The outer border is ink, exactly k device pixels thick.
		var top := Vector2i((ed.panel_rect.position + Vector2(ed.panel_rect.size.x / 2.0, 0)) * m.px_per_unit)
		var ink := 0
		for y in range(top.y, top.y + ed.k * 3):
			if img.get_pixel(top.x, y).get_luminance() < 0.2:
				ink += 1
		check_eq(ink, ed.k, "%s: the 1-px frame is k = %d device px" % [cfg[0], ed.k])
		_save(img, "name_editor_pixels_" + cfg[0])
		_close(app)


# --- Helpers


func _css(m, ui: float) -> float:
	return ui * m.px_per_unit.y / m.dpr


## Talks to the name-giver and asks for a new name: through her lines, then
## "Can I have a new name?".
func _to_editor(app: Control, by_touch: bool) -> void:
	var g: Control = app.game
	var giver: String = names.giver()
	await _open_talk(app, giver, by_touch)
	var guard := 0
	while not g.name_editor.is_open and guard < 60:
		guard += 1
		var box: Control = g.dialogue
		if not box.is_open:
			await tree.process_frame
			continue
		var naming: bool = str(box.line.get("conversation", "")) == str(names.giver_dialogue())
		if box.choices_shown() and naming:
			if by_touch:
				await _tap_at(app, box.choice_rects[0].get_center())
			else:
				while box.selected != 0:
					_key(KEY_UP)
					await tree.process_frame
				_key(KEY_E)
				await tree.process_frame
		else:
			await _press(app, by_touch)


func _finish_conversation(app: Control, by_touch: bool) -> void:
	var box: Control = app.game.dialogue
	var guard := 0
	while box.is_open and guard < 40:
		guard += 1
		if box.choices_shown():
			# Decline the naming offer.
			if by_touch:
				await _tap_at(app, box.choice_rects[box.choice_rects.size() - 1].get_center())
			else:
				_key(KEY_DOWN)
				await tree.process_frame
				_key(KEY_E)
				await tree.process_frame
		else:
			await _press(app, by_touch)
	await _frames(12)


func _until(cond: Callable, seconds: float) -> void:
	var waited := 0.0
	while not cond.call() and waited < seconds:
		await tree.process_frame
		waited += 1.0 / 60.0
		await tree.create_timer(0.016).timeout


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _swipe(app: Control, from: Vector2, dy: float) -> void:
	_touch(app, 3, from, true)
	await tree.process_frame
	var steps := 6
	for i in range(1, steps + 1):
		var ev := InputEventScreenDrag.new()
		ev.index = 3
		ev.position = app.metrics.ui_to_px(from + Vector2(0, dy * i / steps))
		tree.root.push_input(ev)
		await tree.process_frame
	_touch(app, 3, from + Vector2(0, dy), false)
	await tree.process_frame


func _wheel(app: Control, at: Vector2, up: bool) -> void:
	var px: Vector2 = app.metrics.ui_to_px(at)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		tree.root.push_input(ev)
	await tree.process_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		tree.root.push_input(ev)


func _stick(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	tree.root.push_input(ev)


func _open(cfg: Array) -> Control:
	ScreenMetrics.override_dpr = cfg[2]
	ScreenMetrics.override_insets_css = cfg[3]
	ScreenMetrics.override_touch = 1 if cfg[4] else 0
	ScreenMetrics.override_fullscreen = 0
	ScreenMetrics.fullscreen_requests = 0
	tree.root.size = Vector2i((Vector2(cfg[1]) * float(cfg[2])).round())
	await tree.process_frame
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	return app


func _start(cfg: Array) -> Control:
	var app: Control = await _open(cfg)
	await _tap(app, app.metrics.safe_rect.get_center())
	check(app.game != null, "%s: game started" % cfg[0])
	await _frames(2)
	return app


func _close(app: Control) -> void:
	DialogueManager.stop()
	tree.root.remove_child(app)
	app.free()


func _open_talk(app: Control, id: String, by_touch: bool) -> void:
	var g: Control = app.game
	var w = g.world
	var npc: Dictionary = w.npc_by_id(id)
	var r: Rect2 = npc["rect"]
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(r.position.x - w.player_footprint.x / 2.0 - 4.0, r.end.y)
	await tree.process_frame
	await tree.process_frame
	check_eq(w.focus_id, id, "%s in range" % id)
	if by_touch:
		var tc: Control = g.touch
		_touch(app, 1, tc.button_center, true)
		_touch(app, 1, tc.button_center, false)
	else:
		_key(KEY_E)
	await tree.process_frame
	await tree.process_frame


func _press(app: Control, by_touch: bool) -> void:
	if by_touch:
		await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
	else:
		_key(KEY_E)
		await tree.process_frame


func _keys_until_choices(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 20:
		if box.choices_shown() or not box.is_open:
			return
		_key(KEY_E)
		await tree.process_frame


func _tap_at(app: Control, ui: Vector2) -> void:
	_touch(app, 5, ui, true)
	await tree.process_frame
	_touch(app, 5, ui, false)
	await tree.process_frame


func _tap(app: Control, ui_pos: Vector2) -> void:
	var px: Vector2 = app.metrics.ui_to_px(ui_pos)
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


func _save(img: Image, n: String) -> void:
	if shots_dir != "":
		var path := shots_dir.path_join("%s.png" % n)
		img.save_png(path)
		print("     shot: ", path)

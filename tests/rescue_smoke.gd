extends "res://tests/test_base.gd"
## Rescuing Wick, Part A, in the real game:
## - scene select: a button on the title screen (always, even without the
##   debug overlay) opens the menu and a tap jumps to "Rest for the
##   night" (phone, touch); F1 in the game opens it, arrows + Enter pick
##   "After the rogue camp", Esc closes it (keyboard); every preset loads;
## - keyboard: the entrance is closed ("stay in camp"), sleeping in the
##   nest wakes Fern at night (line on black, night tint, the other
##   apprentices asleep, goal), out of camp at night (Rook gone), on foot
##   to the rogue camp, "Stay out of sight...", hide at the log, the look
##   at Wick and Slate, "Sneak to Wick"; the flags survive the save hook;
## - touch on a phone: lucky coin flip -> Wick wakes, home with him;
## - gamepad: caught -> the prisoner den (captives, ivy), walking out ->
##   "To be continued" -> camp;
## - the "Prisoner den" preset arrives from black, just waking.
## With a display (--shots=<dir>) it saves screenshots (rescue_*).

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const ScenePresets := preload("res://scripts/core/scene_presets.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var tuning: Dictionary
var strings: Dictionary
var rs: Dictionary


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	strings = JsonData.load_dict("res://data/strings.json")
	rs = JsonData.load_dict("res://data/story.json")["rescue"]


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	Needs.hunger_every_s = float(tuning["needs"]["hunger_every_s"])
	Needs.thirst_every_s = float(tuning["needs"]["thirst_every_s"])
	Settings.reset()
	Story.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact", "crouch"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _text(key: String) -> String:
	return GameState.format_text(str(strings[key]))


# --- Scene select


func test_scene_select_without_the_debug_overlay() -> void:
	# The title button is always there (phones have no F1); in the game the
	# menu stays behind the debug overlay.
	var app: Control = await _app(TARGET_PHONE, false)
	check(app.scene_button.visible, "the title has a Scene select button")
	var r := Rect2(app.scene_button.position, app.scene_button.size)
	await _tap_button(app, r.get_center())
	check(app.scene_select.is_open and app.game == null, "a tap opens the menu, the game doesn't start")
	app.scene_select.close()
	await _frames(2)
	check(app.scene_button.visible and not app.scene_select.is_open, "closed again, button back")
	app.start_game()
	await _frames(2)
	check(not app.scene_button.visible, "no title button in the game")
	_key(KEY_F1)
	await _frames(2)
	check(not app.scene_select.is_open, "F1 does nothing without the overlay")
	_close(app)


func test_scene_select_from_the_title_by_touch() -> void:
	var app: Control = await _app(TARGET_PHONE, true)
	check(app.scene_button.visible and app.game == null, "a Scene select button on the title")
	var r := Rect2(app.scene_button.position, app.scene_button.size)
	check(app.metrics.safe_rect.encloses(r) and r.size.y >= 48.0, "inside the safe area, thumb-sized (%s)" % r)
	await _tap_button(app, r.get_center())
	check(app.scene_select.is_open, "the menu opens")
	check(app.game == null, "and the game hasn't started")
	var labels: Array[String] = []
	for b: Button in app.scene_select.buttons:
		labels.append(b.text)
		var br := Rect2(b.position, b.size)
		check(br.size.y >= 48.0 and app.metrics.safe_rect.encloses(br), "%s: thumb-sized, on screen" % b.text)
	for want in ["Camp, day", "After the rogue camp", "Rest for the night", "Night: at the log", "Prisoner den"]:
		check(labels.has(want), "entry '%s'" % want)
	if not is_headless():
		await _frames(10)
		_save(await _screen(), "rescue_scene_select_phone")
	var rest: Button = app.scene_select.buttons[labels.find("Rest for the night")]
	await _tap_button(app, Rect2(rest.position, rest.size).get_center())
	await _frames(3)
	check(app.game != null and not app.scene_select.is_open, "jumped into the game")
	var g: Control = app.game
	check_eq(g.world.id, "apprentices_den", "in the apprentices' den")
	check_eq(GameState.get_flag("told_rook"), true, "the story flags are set")
	check_eq(g.goal_label.text, _text("story.goal_rest"), "goal: rest")
	check(not g.held, "the game runs")
	_close(app)


func test_scene_select_in_game_by_keyboard() -> void:
	var app: Control = await _app(DESKTOP, true)
	app.start_game()
	await _frames(3)
	var g: Control = app.game
	_key(KEY_F1)
	await _frames(2)
	check(app.scene_select.is_open and g.held, "F1 opens it; the game waits")
	var at: Vector2 = g.world.player_pos
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	check(g.world.player_pos.distance_to(at) < 0.5, "Fern doesn't move behind the menu")
	_key(KEY_ESCAPE)
	await _frames(2)
	check(not app.scene_select.is_open and not g.held, "Esc closes it")
	_key(KEY_F1)
	await _frames(2)
	_key(KEY_DOWN)
	await _frames(2)
	_key(KEY_ENTER)
	await _frames(3)
	check(not app.scene_select.is_open, "Enter picks")
	check_eq(GameState.get_flag("rogue_camp_found"), true, "After the rogue camp: flags")
	check_eq(g.world.id, "camp", "in camp")
	check_eq(g.world.focus_id, "rook", "standing by Rook")
	check_eq(g.goal_label.text, _text("story.goal_warn"), "goal: warn the deputy")
	_close(app)


func test_every_preset_loads() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var sp = ScenePresets.new()
	for id in sp.ids():
		check(g.jump_to(id), "%s jumps" % id)
		await _frames(2)
		var p: Dictionary = sp.resolved(id)
		check_eq(g.world.id, str(p["area"]), "%s: area" % id)
		for f: String in p.get("flags", {}):
			check_eq(GameState.get_flag(f), p["flags"][f], "%s: %s" % [id, f])
		check(not g.in_cutscene() and not g.is_talking(), "%s: nothing playing" % id)
	check(not g.jump_to("no_such_preset"), "unknown preset refused")
	_close(app)


# --- Rest, night, the trip, the log


func test_rest_and_the_night_trip_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	g.jump_to("after_rogue_camp")
	_freeze_needs(70, 70)
	await _frames(2)
	await _keys_until_closed(app, true)
	check_eq(GameState.get_flag("told_rook"), true, "told Rook")
	# The entrance: "stay in camp".
	_place_near_exit(g, "hunting_grounds")
	Input.action_press("move_right")
	await _until(func() -> bool: return g.message.visible and g.message.text == _text("story.stay_in_camp"), 4000)
	Input.action_release("move_right")
	check_eq(g.message.text, _text("story.stay_in_camp"), "Rook said to stay in camp")
	check_eq(g.world.id, "camp", "still in camp")
	# The den, the nest.
	g.load_area("apprentices_den", "inside")
	await _frames(2)
	check(g.world.npc_by_id("sleeper_a").is_empty(), "nobody asleep by day")
	g.world.player_pos = g.world.spawns["nest"]["pos"]
	await _frames(2)
	await _until(func() -> bool: return not g.message.visible, 4000)
	await _frames(2)
	check_eq(g.world.focus_id, "my_nest", "the nest has focus")
	check(g.prompt_label.visible and g.prompt_label.text == _text("story.sleep_label"), "a 'Sleep' label over it")
	_key(KEY_E)
	await _frames(2)
	check(g.travel.busy(), "she lies down to sleep")
	await _until(func() -> bool: return g.travel.phase == "message", 5000)
	check(g.fade_message.visible and g.fade_message.text == _text("story.sleep_message"), "on black: %s" % g.fade_message.text)
	if not is_headless():
		_save(await _screen(), "rescue_sleep_desktop")
	await _wait_travel(g)
	check_eq(GameState.get_flag("night"), true, "night")
	check(g.world.is_night, "the world knows")
	var want: Color = g.world_view._pal_grade("night") * Color(str(rs["tint"]))
	check(g.world_view.grade.color.is_equal_approx(want), "night tint (%s)" % g.world_view.grade.color)
	check(not g.world.npc_by_id("sleeper_a").is_empty() and not g.world.npc_by_id("sleeper_b").is_empty(), "the others asleep")
	check(g.world_view.npc_nodes.has("sleeper_a"), "and drawn")
	check_eq(g.goal_label.text, _text("story.goal_rescue"), "goal: rescue Wick")
	if not is_headless():
		await _settle()
		_save(await _screen(), "rescue_den_night_desktop")
	# Out of the den and the camp.
	g.load_area("camp", "from_apprentices_den")
	await _frames(2)
	check(g.world.npc_by_id("rook").is_empty(), "Rook isn't watching the entrance")
	if not is_headless():
		await _settle()
		_save(await _screen(), "rescue_camp_night_desktop")
	_place_near_exit(g, "hunting_grounds")
	await _walk_until_area(app, "move_right", "hunting_grounds")
	await _wait_travel(g)
	check(g.world.is_night, "night in the Hunting Grounds")
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	_place_near_exit(g, "rogue_camp")
	await _walk_until_area(app, "move_right", "rogue_camp")
	await _wait_travel(g)
	check(g.world.is_night, "night in the rogue camp")
	check(g.message.visible and g.message.text == _text("story.stay_hidden"), "Stay out of sight...")
	for id in ["wick", "slate", "vex"]:
		check(g.world_view.npc_nodes.has(id), "%s is there" % id)
	# The log.
	await _walk_to(app, "hide_log_night")
	await _until(func() -> bool: return not g.message.visible, 4000)
	await _frames(2)
	check(g.prompt_label.visible and g.prompt_label.text == _text("story.hide_label"), "Hide")
	_key(KEY_E)
	await _frames(2)
	check(g.in_cutscene() and g.world.hiding, "hiding behind the log")
	var r := await _watch(app, "key")
	check(r["lines"].contains("There's Wick") and r["lines"].contains("Slate"), "she sees Wick and Slate (%s)" % r["lines"])
	check(r["furthest"] > 380.0, "the camera went over to them (%.0f)" % r["furthest"])
	await _frames(3)
	check_eq(g.world.focus_id, "sneak_log", "the log offers sneaking")
	await _until(func() -> bool: return not g.message.visible, 4000)
	check(g.prompt_label.visible and g.prompt_label.text == _text("story.sneak_label"), "Sneak to Wick (%s)" % g.prompt_label.text)
	if not is_headless():
		await _settle()
		_save(await _screen(), "rescue_log_night_desktop")
	# The save hook.
	var saved := JSON.stringify({"state": GameState.state.save_data(), "story": Story.save_data()})
	GameState.reset()
	Story.reset()
	var back: Dictionary = JSON.parse_string(saved)
	GameState.state.load_save_data(back["state"])
	Story.load_save_data(back["story"])
	for k in ["told_rook", "night", "log_watched", "rogue_camp_found"]:
		check_eq(GameState.get_flag(k), true, "loaded %s" % k)
	check(Story.sneaking(), "loaded: still out at night")
	_close(app)


func test_lucky_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	g.jump_to("night_log")
	Story.lucky_chance = 1.0
	_freeze_needs(70, 70)
	await _frames(3)
	check_eq(g.world.focus_id, "sneak_log", "behind the log")
	check(g.touch.visible and g.touch.highlight, "the paw button is lit")
	await _paw_button(app)
	check(g.in_cutscene(), "sneaking")
	if not is_headless():
		await _until(func() -> bool: return g.dialogue.is_open, 6000)
		_save(await _screen(), "rescue_sneak_phone")
	var r := await _watch(app, "touch")
	check(r["lines"].contains("Wake up") and r["lines"].contains("You came for me"), "she wakes Wick (%s)" % r["lines"])
	check(g.travel.busy(), "then a fade")
	await _until(func() -> bool: return g.travel.phase == "message", 5000)
	check_eq(g.fade_message.text, _text("story.home_with_wick"), "home with Wick")
	await _tap_at(app, app.metrics.safe_rect.get_center())
	await _wait_travel(g)
	check_eq(g.world.id, "camp", "back in camp")
	check_eq(GameState.get_flag("rescue"), "rescued", "rescued")
	check(not g.world.is_night, "morning")
	check(not g.world.npc_by_id("wick").is_empty(), "Wick is home")
	check(not g.goal_label.visible, "mission done")
	check(g.touch.visible, "touch controls back")
	_close(app)


func test_caught_by_gamepad_and_the_prisoner_den() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	g.jump_to("night_log")
	Story.lucky_chance = 0.0
	_freeze_needs(70, 70)
	await _frames(3)
	_pad(JOY_BUTTON_A)
	await _frames(2)
	check(g.in_cutscene(), "South sneaks")
	var r := await _watch(app, "pad")
	check(r["lines"].contains("Look what crept out") and r["lines"].contains("Put it with the others"), "caught (%s)" % r["lines"])
	await _until(func() -> bool: return g.travel.phase == "message", 6000)
	check_eq(g.fade_message.text, _text("story.dragged_away"), "dragged away")
	await _wait_travel(g)
	check_eq(g.world.id, "prisoner_den", "in the prisoner den")
	check_eq(GameState.get_flag("rescue"), "captured", "captured")
	for id in ["captive_a", "captive_b", "captive_c"]:
		check(g.world_view.npc_nodes.has(id), "%s drawn" % id)
	check(g.world.props.any(func(pr): return pr["type"] == "ivy"), "ivy over the doorway")
	check(g.world_view.find_child("DenInterior", true, false) != null, "drawn by the den template")
	if not is_headless():
		await _settle()
		_save(await _screen(), "rescue_prisoner_den_desktop")
	# Walking out: the placeholder ending.
	var door: Rect2 = g.world.exits[0]["rect"]
	g.world.player_pos = Vector2(door.get_center().x, door.position.y - 12.0)
	g.world.exits_armed = true
	Input.action_press("move_down")
	await _until(func() -> bool: return g.travel.busy(), 4000)
	Input.action_release("move_down")
	await _until(func() -> bool: return g.travel.phase == "message", 5000)
	check_eq(g.fade_message.text, _text("story.to_be_continued"), "To be continued")
	_pad(JOY_BUTTON_A)
	await _wait_travel(g)
	check_eq(g.world.id, "camp", "sent home")
	check_eq(GameState.get_flag("rescue"), "escaped", "rescue settled for now")
	check(not g.world.is_night, "morning")
	_close(app)


func test_prisoner_den_preset_wakes_from_black() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	g.jump_to("prisoner_den")
	await _frames(2)
	check_eq(g.world.id, "prisoner_den", "the prisoner den")
	check(g.travel.busy() and g.travel.phase == "message", "from black")
	check_eq(g.fade_message.text, _text("story.prison_wake"), "just woken (%s)" % g.fade_message.text)
	if not is_headless():
		_save(await _screen(), "rescue_prison_wake_phone")
	await _tap_at(app, app.metrics.safe_rect.get_center())
	await _wait_travel(g)
	check(not g.travel.busy(), "control back")
	check(g.world.player_pos.distance_to(g.world.spawns["nest"]["pos"]) < 1.0, "on the bedding")
	check(g.touch.visible, "touch controls")
	if not is_headless():
		await _settle()
		_save(await _screen(), "rescue_prisoner_den_phone")
	_close(app)


# --- helpers (as in story_smoke.gd)


## Every line by E until the box closes (`open_first`: E starts the talk).
func _keys_until_closed(app: Control, open_first: bool = false) -> void:
	var box: Control = app.game.dialogue
	if open_first:
		_key(KEY_E)
		await _frames(2)
	for i in 40:
		if not box.is_open:
			break
		_key(KEY_E)
		await _frames(2)
	await _frames(2)


func _walk_to(app: Control, spot: String) -> void:
	var w = app.game.world
	var sp: Dictionary = w.spot_by_id(spot)
	var target: Vector2 = sp["prompt"] + Vector2(0, 6)
	for i in 400:
		if w.focus_id == spot:
			break
		w.player_pos += (target - w.player_pos).limit_length(1.5)
		await tree.process_frame
	check_eq(w.focus_id, spot, "%s has the prompt" % spot)


func _watch(app: Control, how: String) -> Dictionary:
	var g: Control = app.game
	var box: Control = g.dialogue
	var lines: Array[String] = []
	var furthest := 0.0
	var until := Time.get_ticks_msec() + 40000
	while g.in_cutscene() and Time.get_ticks_msec() < until:
		furthest = maxf(furthest, g.camera_rect.get_center().x)
		if box.is_open:
			var t := GameState.format_text(str(box.line.get("text", "")))
			if lines.is_empty() or lines[lines.size() - 1] != t:
				lines.append(t)
			match how:
				"key":
					_key(KEY_E)
				"pad":
					_pad(JOY_BUTTON_A)
				"touch":
					await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
		await _frames(3)
	check(not g.in_cutscene(), "the cutscene ends (%s)" % how)
	return {"lines": " | ".join(lines), "n": lines.size(), "furthest": furthest}


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		tree.root.push_input(ev)


func _freeze_needs(h: int, t: int) -> void:
	Needs.hunger_every_s = 0.0
	Needs.thirst_every_s = 0.0
	Needs.set_value("hunger", h)
	Needs.set_value("thirst", t)


func _place_near_exit(g: Control, to: String) -> void:
	var w = g.world
	for e: Dictionary in w.exits:
		if e["to"] == to:
			var r: Rect2 = e["rect"]
			var side := -1.0 if r.get_center().x > w.size.x / 2.0 else 1.0
			w.player_pos = Vector2(r.get_center().x + side * 30.0, r.end.y - 6.0)
			w.player_vel = Vector2.ZERO
			w.exits_armed = true


func _walk_until_area(app: Control, action: String, area: String) -> void:
	var g: Control = app.game
	Input.action_press(action)
	await _until(func() -> bool: return g.world.id == area, 5000)
	Input.action_release(action)
	check_eq(g.world.id, area, "walked into %s" % area)


func _wait_travel(g: Control) -> void:
	await _until(func() -> bool: return not g.travel.busy(), 6000)
	await tree.process_frame
	check(not g.travel.busy(), "the fade finishes")


func _tap_at(app: Control, ui: Vector2) -> void:
	_touch(app, 5, ui, true)
	await tree.process_frame
	_touch(app, 5, ui, false)
	await tree.process_frame


## A tap on an ordinary button: what touch-to-mouse emulation sends it.
func _tap_button(app: Control, ui: Vector2) -> void:
	var px: Vector2 = app.metrics.ui_to_px(ui)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		ev.device = InputEvent.DEVICE_ID_EMULATION
		tree.root.push_input(ev)
		await tree.process_frame


func _paw_button(app: Control) -> void:
	var tc: Control = app.game.touch
	_touch(app, 1, tc.button_center, true)
	_touch(app, 1, tc.button_center, false)
	await _frames(2)


func _until(cond: Callable, ms: int = 3000) -> void:
	var until := Time.get_ticks_msec() + ms
	while not cond.call() and Time.get_ticks_msec() < until:
		await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _settle() -> void:
	await _frames(30)


## The app on its title screen (`debug`: the debug overlay on).
func _app(cfg_: Array, debug: bool) -> Control:
	ScreenMetrics.override_dpr = cfg_[2]
	ScreenMetrics.override_insets_css = cfg_[3]
	ScreenMetrics.override_touch = 1 if cfg_[4] else 0
	ScreenMetrics.override_fullscreen = 0
	ScreenMetrics.fullscreen_requests = 0
	Settings.debug_overlay = debug
	tree.root.size = Vector2i((Vector2(cfg_[1]) * float(cfg_[2])).round())
	await tree.process_frame
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	return app


func _start(cfg_: Array) -> Control:
	var app: Control = await _app(cfg_, false)
	app.start_game()
	await tree.process_frame
	await tree.process_frame
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

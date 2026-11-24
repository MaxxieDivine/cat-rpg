extends "res://tests/test_base.gd"
## Patrols in the real game screen:
## - a solo hunting patrol by keyboard: talk to the deputy, accept, the goal
##   under the needs bars, out through the camp entrance, catch a mouse,
##   carry it home to the pile: done;
## - a border patrol with two mates by touch on a phone: the circled patrol
##   icons, the mates walking to the camp entrance, following Fern out by
##   joystick into the Hunting Grounds and Hunting Grounds 2;
## - turning an offer down.
## With a display (--shots=<dir>) it saves screenshots (patrol_*).

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

const TARGET_PHONE := ["target_phone", Vector2i(923, 411), 2.625, [0.0, 0.0, 0.0, 30.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var tuning: Dictionary
var strings: Dictionary
var cfg: Dictionary


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	strings = JsonData.load_dict("res://data/strings.json")
	cfg = JsonData.load_dict("res://data/patrols.json")


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	Needs.hunger_every_s = float(tuning["needs"]["hunger_every_s"])
	Needs.thirst_every_s = float(tuning["needs"]["thirst_every_s"])
	Settings.reset()
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact", "crouch"]:
		if InputMap.has_action(a):
			Input.action_release(a)


## What the deputy will offer (instead of a roll), for a predictable test.
func _set_offer(kind: String, mates: Array) -> void:
	var p = Patrols.patrol
	p.offer = {"kind": kind, "mates": mates, "prey_goal": int(cfg["prey_goal"]["solo" if mates.is_empty() else "group"]),
		"marks": p._roll_marks(Patrols.spots()) if kind == "border" else []}
	Patrols.sync()


func _near_deputy(g: Control) -> void:
	var w = g.world
	var dep: Dictionary = w.npc_by_id(Patrols.deputy())
	w.player_pos = Vector2(dep["rect"].end.x + w.player_footprint.x / 2.0 + 4.0, dep["rect"].end.y)
	w.player_vel = Vector2.ZERO
	await _frames(2)
	check_eq(w.focus_id, Patrols.deputy(), "the deputy has the prompt")


func _mark_key(g: Control, id: String) -> String:
	var pm: Sprite2D = g.world_view.patrol_marks.get(id)
	return str(pm.get_meta("key", "")) if pm != null and pm.visible else ""


func test_solo_hunting_patrol_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(60, 70)
	check(not g.goal_label.visible, "no goal before a patrol")
	check_eq(_mark_key(g, "fern"), "ui.patrol", "Fern has the patrol icon")
	check_eq(_mark_key(g, "bram"), "ui.patrol", "Bram (warrior) has it")
	check_eq(_mark_key(g, "wick"), "ui.patrol", "Wick (apprentice) has it")
	for id in ["sorrel", "larch", "rook"]:
		check_eq(_mark_key(g, id), "", "%s has none" % id)
	_set_offer("hunting", [])
	await _near_deputy(g)
	_key(KEY_E)
	await _frames(2)
	check(g.dialogue.is_open, "talking to the deputy")
	check(str(g.dialogue.line.get("text", "")).begins_with("Hunting patrol"), "the deputy names the patrol (%s)" % g.dialogue.line.get("text", ""))
	check_eq(_mark_key(g, "fern"), "ui.patrol_picked", "picked: Fern's icon is circled while the deputy says so")
	check_eq(_mark_key(g, "bram"), "ui.patrol", "Bram isn't picked")
	await _keys_until_choices(app)
	if not is_headless():
		_save(await _screen(), "patrol_offer_desktop")
	check(g.dialogue.choices_shown(), "accept or not")
	_key(KEY_E)  # "On my way." is selected first
	await _keys_until_closed(app)
	check(Patrols.is_active(), "the patrol started")
	check_eq(Patrols.phase(), "gather", "meet at the entrance")
	await _frames(2)
	check(g.goal_label.visible, "the goal shows")
	check_eq(g.goal_label.text, strings["patrol.goal_gather"], "meet at the camp entrance")
	check(g.goal_label.position.y >= g.needs_hud.hud_rect.end.y, "under the needs bars")
	check_eq(_mark_key(g, "fern"), "ui.patrol_picked", "still circled on the patrol")
	# Out through the camp entrance.
	_place_near_exit(g, "hunting_grounds")
	await _walk_until_area(app, "move_right", "hunting_grounds")
	check_eq(Patrols.phase(), "out", "set out")
	await _wait_travel(g)
	check_eq(g.goal_label.text, strings["patrol.goal_prey"].replace("{n}", "0").replace("{of}", "1"), "goal: bring back prey")
	check(g.world.followers().is_empty(), "solo: nobody follows")
	# Catch a mouse.
	Input.action_press("crouch")
	var m := _ready_mouse(g)
	Input.action_press("move_right")
	await _until(func() -> bool: return g.world.can_pounce(), 4000)
	Input.action_release("move_right")
	_key(KEY_SPACE)
	await _until(func() -> bool: return Player.carried_item() == "mouse" and not g.world.is_busy(), 3000)
	Input.action_release("crouch")
	check_eq(Player.carried_item(), "mouse", "caught (%s)" % m["state"])
	# Home with it.
	g.world.place_at_spawn("from_camp")
	await _frames(2)
	await _walk_until_area(app, "move_left", "camp")
	await _wait_travel(g)
	check(Patrols.is_active(), "not done until it's on the pile")
	var w = g.world
	var r: Rect2 = w.pile["rect"]
	w.player_pos = Vector2(r.end.x + w.player_footprint.x / 2.0 + 4.0, r.end.y)
	await _frames(2)
	_key(KEY_E)
	await _frames(2)
	check(not Patrols.is_active(), "prey on the pile: patrol done")
	check_eq(Patrols.patrol.completed, 1, "one patrol done")
	check_eq(g.message.text, strings["patrol.done"], "Patrol done!")
	check(not g.goal_label.visible, "goal gone")
	check_eq(_mark_key(g, "fern"), "ui.patrol", "icon back to plain")
	if not is_headless():
		await _frames(10)
		_save(await _screen(), "patrol_done_desktop")
	_close(app)


func test_border_patrol_with_mates_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	_set_offer("border", ["bram", "wick"])
	await _near_deputy(g)
	await _paw_button(app)
	check(g.dialogue.is_open, "the paw button talks to the deputy")
	check_eq(_mark_key(g, "bram"), "ui.patrol_picked", "Bram circled while the deputy picks him")
	check_eq(_mark_key(g, "wick"), "ui.patrol_picked", "Wick too")
	await _tap_until_choices(app)
	check(str(g.dialogue.line.get("text", "")).contains("will go with you"), "the deputy names who goes (%s)" % g.dialogue.line.get("text", ""))
	check(str(g.dialogue.line.get("text", "")).contains("Bram and Wick"), "Bram and Wick")
	if not is_headless():
		_save(await _screen(), "patrol_picked_phone")
	await _tap_at(app, g.dialogue.choice_rects[0].get_center())
	await _tap_until_closed(app)
	check(Patrols.is_active(), "accepted by tap")
	var w = g.world
	for id in ["bram", "wick"]:
		check_eq(w.npc_by_id(id)["mode"], "goto", "%s walks to the entrance" % id)
	# They get there and wait.
	await _until(func() -> bool: return w.npc_by_id("bram")["mode"] == "wait" and w.npc_by_id("wick")["mode"] == "wait", 12000)
	var meet: Vector2 = w.markers[cfg["meet"]]
	for id in ["bram", "wick"]:
		check_eq(w.npc_by_id(id)["mode"], "wait", "%s waits" % id)
		check(w.npc_by_id(id)["pos"].distance_to(meet) <= 40.0, "%s at the camp entrance" % id)
	_place_near_exit(g, "hunting_grounds")
	await _frames(20)
	if not is_headless():
		await _settle()
		_save(await _screen(), "patrol_meet_phone")
	# Out by joystick: they follow.
	await _joystick_until_area(app, Vector2.RIGHT, "hunting_grounds")
	await _wait_travel(g)
	w = g.world
	check_eq(w.followers(), ["bram", "wick"], "Bram and Wick follow into the Hunting Grounds")
	check(g.world_view.npc_nodes.has("bram") and g.world_view.npc_nodes.has("wick"), "drawn there")
	check(g.goal_label.text.begins_with("Scent marks: 0 / "), "goal: scent marks (%s)" % g.goal_label.text)
	var tc: Control = g.touch
	_touch(app, 0, tc.stick_rest, true)
	_drag(app, 0, tc.stick_rest + Vector2(tc.stick_radius * 0.7, tc.stick_radius * 0.3))
	var bram_walked := false
	for f in 90:
		await tree.process_frame
		bram_walked = bram_walked or g.world_view.npc_nodes["bram"].cat.anim == "walk"
	_touch(app, 0, tc.stick_rest, false)
	await _frames(60)
	var bram: Dictionary = w.npc_by_id("bram")
	check(bram["pos"].distance_to(w.player_pos) < float(cfg["follow_gap"]) * 1.5, "Bram kept up (%.0f px)" % bram["pos"].distance_to(w.player_pos))
	check(bram_walked, "Bram walks (his walk sheet) while following")
	check(g.world_view.npc_nodes["bram"].cat.anim != "walk", "and stops walking when Fern stops")
	if not is_headless():
		await _settle()
		_save(await _screen(), "patrol_follow_phone")
	# On to the border.
	_place_near_exit(g, "hunting_grounds_2")
	await _joystick_until_area(app, Vector2.RIGHT, "hunting_grounds_2")
	await _wait_travel(g)
	check_eq(g.world.followers(), ["bram", "wick"], "still following in Hunting Grounds 2")
	if not is_headless():
		g.world.player_pos = Vector2(300, g.world.stream_y(300) + 30)
		g.world.reset_trail()
		await _settle()
		_save(await _screen(), "patrol_border_phone")
	# Into the den they don't come; back in camp they follow again.
	g.load_area("camp", "from_hunting")
	await _frames(2)
	check_eq(g.world.followers(), ["bram", "wick"], "following in camp")
	g.load_area("apprentices_den", "inside")
	await _frames(2)
	check(g.world.followers().is_empty(), "not into the den")
	_close(app)


func test_turning_the_deputy_down() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	await _near_deputy(g)
	_key(KEY_E)
	await _frames(2)
	check(not Patrols.patrol.offer.is_empty(), "talking rolled an offer")
	await _keys_until_choices(app)
	g.dialogue.move_selection(1)
	_key(KEY_E)
	await _keys_until_closed(app)
	check(not Patrols.is_active(), "no patrol")
	check(Patrols.patrol.offer.is_empty(), "the offer is dropped")
	check_eq(_mark_key(g, "fern"), "ui.patrol", "nobody circled")
	check(not g.goal_label.visible, "no goal")
	_close(app)


## Border patrol, solo, by keyboard: every spot in Hunting Grounds 2 and
## the first grounds marked with E, the counter, the rings, then home to
## report to the deputy.
func test_border_patrol_marking_and_report_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	_set_offer("border", [])
	# One extra spot in the first grounds, for a predictable test.
	Patrols.patrol.offer["marks"].append({"area": "hunting_grounds", "id": "north_2"})
	var total: int = Patrols.patrol.offer["marks"].size()
	await _near_deputy(g)
	_key(KEY_E)
	await _keys_until_choices(app)
	_key(KEY_E)
	await _keys_until_closed(app)
	_place_near_exit(g, "hunting_grounds")
	await _walk_until_area(app, "move_right", "hunting_grounds")
	await _wait_travel(g)
	var goal := func(n: int) -> String: return strings["patrol.goal_marks"].replace("{n}", str(n)).replace("{of}", str(total))
	check_eq(g.goal_label.text, goal.call(0), "Scent marks: 0 / %d" % total)
	# The extra spot in the first grounds shows; the others don't.
	check(g.world_view.scent_nodes["north_2"].visible, "the wanted spot shows here")
	check(not g.world_view.scent_nodes["north_1"].visible, "spots this patrol doesn't want are hidden")
	var n := 0
	n = await _mark_by(app, "north_2", "key", n)
	check_eq(g.goal_label.text, goal.call(n), "counter: %d" % n)
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	for ss: Dictionary in g.world.scent_spots:
		check(g.world_view.scent_nodes[ss["id"]].visible, "%s shows" % ss["id"])
		check_eq(str(g.world_view.scent_nodes[ss["id"]].get_meta("key", "")), "ui.scent_ring", "%s unmarked: a dashed ring" % ss["id"])
	if not is_headless():
		g.world.player_pos = g.world.scent_spots[0]["pos"] + Vector2(40, 50)
		await _settle()
		_save(await _screen(), "patrol_spot_unmarked_desktop")
	for ss: Dictionary in g.world.scent_spots:
		n = await _mark_by(app, ss["id"], "key", n)
		check_eq(str(g.world_view.scent_nodes[ss["id"]].get_meta("key", "")), "ui.scent_marked", "%s looks marked" % ss["id"])
		if n < total:
			check_eq(g.goal_label.text, goal.call(n), "counter: %d" % n)
	check_eq(Patrols.phase(), "report", "all marked: go and report")
	check_eq(g.goal_label.text, GameState.format_text(strings["patrol.goal_report"]), "goal: tell the deputy")
	if not is_headless():
		g.world.player_pos = g.world.scent_spots[3]["pos"] + Vector2(-40, 50)
		await _settle()
		_save(await _screen(), "patrol_spot_marked_desktop")
	# Home and report.
	g.load_area("camp", "from_hunting")
	await _frames(2)
	await _near_deputy(g)
	_key(KEY_E)
	await _frames(2)
	check(str(g.dialogue.line.get("text", "")).contains("border's marked"), "the deputy asks (%s)" % g.dialogue.line.get("text", ""))
	await _keys_until_choices(app)
	_key(KEY_E)
	await _keys_until_closed(app)
	check(not Patrols.is_active(), "reported: patrol done")
	check_eq(Patrols.patrol.completed, 1, "counted")
	check(not g.goal_label.visible, "no goal")
	_close(app)


## Border patrol with a mate on a phone: marks by the paw button and by a
## gamepad's South button; the mate stays with Fern.
func test_border_marking_by_touch_and_gamepad() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	_set_offer("border", ["wick"])
	Patrols.patrol.offer["marks"] = Patrols.patrol.offer["marks"].filter(func(m): return m["area"] == "hunting_grounds_2")
	Patrols.prepare_offer()
	await _near_deputy(g)
	await _paw_button(app)
	await _tap_until_choices(app)
	await _tap_at(app, g.dialogue.choice_rects[0].get_center())
	await _tap_until_closed(app)
	_place_near_exit(g, "hunting_grounds")
	await _joystick_until_area(app, Vector2.RIGHT, "hunting_grounds")
	await _wait_travel(g)
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	check_eq(g.world.followers(), ["wick"], "Wick along")
	var n := 0
	var spots: Array = g.world.scent_spots
	for i in spots.size():
		n = await _mark_by(app, spots[i]["id"], "touch" if i % 2 == 0 else "pad", n)
		if i == 0 and not is_headless():
			await _settle()
			_save(await _screen(), "patrol_marking_phone")
	check_eq(Patrols.phase(), "report", "every spot marked by touch and gamepad")
	# The test jumps Fern from spot to spot; Wick catches up on foot.
	var wick: Dictionary = g.world.npc_by_id("wick")
	await _until(func() -> bool: return wick["pos"].distance_to(g.world.player_pos) < float(cfg["follow_gap"]) * 1.5, 6000)
	check(wick["pos"].distance_to(g.world.player_pos) < float(cfg["follow_gap"]) * 1.5, "Wick catches up with Fern (%.0f px)" % wick["pos"].distance_to(g.world.player_pos))
	_close(app)


## Walks Fern up to spot `id` from below and marks it by "key" (E),
## "touch" (the paw button) or "pad" (South). Returns the new count.
func _mark_by(app: Control, id: String, how: String, n: int) -> int:
	var g: Control = app.game
	var w = g.world
	var ss: Dictionary = w.scent_by_id(id)
	w.player_pos = ss["pos"] + Vector2(0, 24)
	w.player_vel = Vector2.ZERO
	w.reset_trail()
	# Teleported: refresh focus now (it still names the spot she left).
	w.step(0.0, Vector2.ZERO, false)
	Input.action_press("move_up")
	await _until(func() -> bool: return w.focus_id == w.SCENT_PREFIX + id, 3000)
	Input.action_release("move_up")
	await _frames(2)
	check_eq(w.focus_id, w.SCENT_PREFIX + id, "%s: walking up gives it the paw prompt" % id)
	check(g.world_view.paw.visible, "%s: paw prompt" % id)
	match how:
		"key":
			_key(KEY_E)
		"touch":
			# Back to touch after a gamepad press (that hid the buttons).
			await _tap_at(app, app.metrics.safe_rect.get_center() + Vector2(0, -60))
			check(g.touch.visible and g.touch.highlight, "%s: the paw button shows, lit" % id)
			await _paw_button(app)
		"pad":
			for pressed in [true, false]:
				var ev := InputEventJoypadButton.new()
				ev.button_index = JOY_BUTTON_A
				ev.pressed = pressed
				tree.root.push_input(ev)
	await _frames(2)
	check_eq(w.action, "mark", "%s: marking (%s)" % [id, how])
	await _until(func() -> bool: return not w.is_busy(), 3000)
	await _frames(2)
	check(Patrols.patrol.is_marked(w.id, id), "%s marked by %s" % [id, how])
	check_eq(Patrols.patrol.marks_done(), n + 1, "%s: count %d" % [id, n + 1])
	return n + 1


# --- helpers


func _ready_mouse(g: Control) -> Dictionary:
	var h = g.world.hunt
	if h.mice.is_empty():
		h.spawn_at(0)
	var m: Dictionary = h.mice[0]
	m["state"] = "feed"
	m["t"] = 999.0
	m["wander_t"] = 999.0
	m["wander_to"] = m["pos"]
	m["alert"] = 0.0
	m["squeak_t"] = 999.0
	g.world.player_pos = (m["pos"] as Vector2) - Vector2(50, 0)
	g.world.player_vel = Vector2.ZERO
	g.world.facing = 1
	return m


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


func _joystick_until_area(app: Control, dir: Vector2, area: String) -> void:
	var g: Control = app.game
	var tc: Control = g.touch
	_touch(app, 0, tc.stick_rest, true)
	_drag(app, 0, tc.stick_rest + dir * tc.stick_radius * 0.7)
	await _until(func() -> bool: return g.world.id == area, 5000)
	_touch(app, 0, tc.stick_rest, false)
	check_eq(g.world.id, area, "walked into %s by joystick" % area)


func _wait_travel(g: Control) -> void:
	await _until(func() -> bool: return not g.travel.busy(), 3000)
	await tree.process_frame
	check(not g.travel.busy(), "the fade finishes")


func _keys_until_choices(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 30:
		if box.choices_shown() or not box.is_open:
			return
		_key(KEY_E)
		await _frames(2)


func _keys_until_closed(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 30:
		if not box.is_open:
			break
		_key(KEY_E)
		await _frames(2)
	await _frames(2)


func _tap_until_choices(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 30:
		if box.choices_shown() or not box.is_open:
			return
		await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))


func _tap_until_closed(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 30:
		if not box.is_open:
			break
		await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
	await _frames(2)


func _tap_at(app: Control, ui: Vector2) -> void:
	_touch(app, 5, ui, true)
	await tree.process_frame
	_touch(app, 5, ui, false)
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


func _start(cfg_: Array) -> Control:
	ScreenMetrics.override_dpr = cfg_[2]
	ScreenMetrics.override_insets_css = cfg_[3]
	ScreenMetrics.override_touch = 1 if cfg_[4] else 0
	ScreenMetrics.override_fullscreen = 0
	ScreenMetrics.fullscreen_requests = 0
	Settings.debug_overlay = false
	tree.root.size = Vector2i((Vector2(cfg_[1]) * float(cfg_[2])).round())
	await tree.process_frame
	var app: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
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

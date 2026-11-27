extends "res://tests/test_base.gd"
## "The rogue and the missing Wick", Part A, in the real game screen:
## - by keyboard on a desktop: a solo border patrol out and marked, Wick is
##   gone from camp when Fern comes home, Bram asks about him, the deputy's
##   report gives the rogue news once, the goal shows, the deputy then only
##   reminds (no patrol offer), and all of it survives the save hook;
## - by touch on a phone: the report and the news, the goal under the bars.
## Part B, the rogue Slate by the river in Hunting Grounds 2:
## - keyboard: question him + the red-fur question; he walks off; the story
##   exit opens; into rogue land and back; the choice survives the save hook;
## - touch on a phone, carrying prey: three choices; threaten him; he bolts
##   and leaves a scent trail;
## - gamepad: bribe him with the mouse (+ the red-fur question); he keeps
##   it and stays; the arrow shows the way.
## Part C, the rogue camp:
## - keyboard: "Stay out of sight...", Wick lying in the corner, the hedge
##   ("Too risky..."), the log's Hide prompt, the cutscene (control locked,
##   the camera goes over and back, Slate walks to Vex, every line), the
##   goal, back home on foot to warn the deputy (he stalls: "Go rest."),
##   the goal turns to resting, no patrols yet, save hook;
## - touch on a phone and a gamepad: hide and tap / press through.
## With a display (--shots=<dir>) it saves screenshots (story_*).

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


## A solo border patrol of Hunting Grounds 2's spots only.
func _set_border_offer() -> void:
	var p = Patrols.patrol
	p.offer = {"kind": "border", "mates": [], "prey_goal": 1,
		"marks": p._roll_marks(Patrols.spots()).filter(func(m): return m["area"] == "hunting_grounds_2")}
	Patrols.sync()


func _near(g: Control, id: String) -> void:
	var w = g.world
	var npc: Dictionary = w.npc_by_id(id)
	w.player_pos = Vector2(npc["rect"].end.x + w.player_footprint.x / 2.0 + 4.0, npc["rect"].end.y)
	w.player_vel = Vector2.ZERO
	await _frames(2)
	check_eq(w.focus_id, id, "%s has the prompt" % id)


## Every line of the conversation, keyboard: E through, first choice.
func _talk_by_keys(app: Control) -> Array[String]:
	var box: Control = app.game.dialogue
	var lines: Array[String] = []
	_key(KEY_E)
	await _frames(2)
	for i in 60:
		if not box.is_open:
			break
		var t := GameState.format_text(str(box.line.get("text", "")))
		if lines.is_empty() or lines[lines.size() - 1] != t:
			lines.append(t)
		_key(KEY_E)
		await _frames(2)
	await _frames(2)
	return lines


func _talk_by_touch(app: Control) -> Array[String]:
	var box: Control = app.game.dialogue
	var lines: Array[String] = []
	await _paw_button(app)
	for i in 60:
		if not box.is_open:
			break
		var t := GameState.format_text(str(box.line.get("text", "")))
		if lines.is_empty() or lines[lines.size() - 1] != t:
			lines.append(t)
		if box.choices_shown():
			await _tap_at(app, box.choice_rects[0].get_center())
		else:
			await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
	await _frames(2)
	return lines


func test_rogue_news_after_a_border_patrol_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	check(not g.world.npc_by_id("wick").is_empty(), "Wick is in camp at the start")
	check(g.world_view.npc_nodes.has("wick"), "and drawn")
	GameState.set_flag("talked_bram", true)
	_set_border_offer()
	await _near(g, Patrols.deputy())
	var lines := await _talk_by_keys(app)
	check(" ".join(lines).contains("Border patrol"), "a border patrol (%s)" % " | ".join(lines))
	check_eq(Patrols.phase(), "gather", "accepted")
	_place_near_exit(g, "hunting_grounds")
	await _walk_until_area(app, "move_right", "hunting_grounds")
	await _wait_travel(g)
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	var n := 0
	for ss: Dictionary in g.world.scent_spots:
		n = await _mark_by(app, ss["id"], "key", n)
	check_eq(Patrols.phase(), "report", "all marked")
	check_eq(GameState.get_flag("wick_missing"), true, "Wick has gone missing")
	check(Story.goal_text() == "", "no story goal before the news")
	# Home: Wick's spot is empty.
	g.load_area("camp", "from_hunting")
	await _frames(2)
	check(g.world.npc_by_id("wick").is_empty(), "Wick isn't in camp")
	check(not g.world_view.npc_nodes.has("wick"), "nor drawn")
	check(not g.world.npc_by_id("bram").is_empty(), "Bram is")
	# Bram asks about him.
	await _near(g, "bram")
	lines = await _talk_by_keys(app)
	check(lines.size() == 1 and lines[0].contains("Have you seen Wick?"), "Bram asks (%s)" % " | ".join(lines))
	# The report: the news instead of "Rest a while".
	await _near(g, Patrols.deputy())
	lines = await _talk_by_keys(app)
	var all := " | ".join(lines)
	check(lines[0].contains("border's marked"), "the report (%s)" % lines[0])
	check(all.contains("strange scent down by the river"), "the news (%s)" % all)
	check(all.contains("Wick hasn't come back"), "Wick is missing")
	check(not all.contains("Rest a while"), "not the normal line")
	check(not Patrols.is_active(), "the patrol is done")
	check_eq(GameState.get_flag("rogue_news"), true, "rogue_news")
	await _frames(2)
	var goal: String = strings["story.goal_investigate"]
	check(g.goal_label.visible, "a goal shows")
	check_eq(g.goal_label.text, goal, "the investigation goal")
	if not is_headless():
		await _settle()
		_save(await _screen(), "story_goal_desktop")
	# Again: only a reminder, no patrol offer.
	lines = await _talk_by_keys(app)
	check(lines.size() == 1 and lines[0].contains("river"), "a reminder (%s)" % " | ".join(lines))
	check(Patrols.patrol.offer.is_empty() and not Patrols.is_active(), "no patrol offered")
	check_eq(GameState.get_flag("rogue_news"), true, "still investigating")
	# Save and load (the hook the save milestone will write to disk).
	var saved := JSON.stringify({"state": GameState.state.save_data(), "story": Story.save_data()})
	GameState.reset()
	Story.reset()
	g.load_area("camp", "start")
	await _frames(2)
	check(not g.world.npc_by_id("wick").is_empty(), "a new game: Wick is back")
	check(not g.goal_label.visible, "no goal")
	var d: Dictionary = JSON.parse_string(saved)
	GameState.state.load_save_data(d["state"])
	Story.load_save_data(d["story"])
	g.load_area("camp", "start")
	await _frames(2)
	check(g.world.npc_by_id("wick").is_empty(), "loaded: Wick is still missing")
	check_eq(g.goal_label.text, goal, "loaded: the goal is back")
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	check(g.world.npc_by_id("wick").is_empty(), "nor in Hunting Grounds 2")
	check_eq(g.goal_label.text, goal, "the goal shows out there too")
	_close(app)


func test_rogue_news_by_touch_on_a_phone() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	# A border patrol already marked, waiting for the report.
	_set_border_offer()
	Patrols.patrol.accept()
	Patrols.patrol.left_camp()
	for m: Dictionary in Patrols.patrol.active["marks"]:
		Patrols.patrol.mark(m["area"], m["id"])
	Patrols.sync()
	check(Story.border_marked([]), "Wick goes missing")
	g.load_area("camp", "from_hunting")
	await _frames(2)
	check(g.world.npc_by_id("wick").is_empty(), "no Wick in camp")
	await _near(g, Patrols.deputy())
	var lines := await _talk_by_touch(app)
	check(" ".join(lines).contains("strange scent"), "the news by touch (%s)" % " | ".join(lines))
	check_eq(GameState.get_flag("rogue_news"), true, "rogue_news")
	await _frames(2)
	check_eq(g.goal_label.text, strings["story.goal_investigate"], "the goal on the phone")
	var safe: Rect2 = app.metrics.safe_rect
	var r := Rect2(g.goal_label.position, g.goal_label.size)
	check(safe.encloses(r), "the goal is inside the safe area (%s in %s)" % [r, safe])
	if not is_headless():
		await _settle()
		_save(await _screen(), "story_goal_phone")
	_close(app)


# --- Part B


## Fern investigating, in Hunting Grounds 2.
func _investigate(g: Control) -> void:
	GameState.set_flag("wick_missing", true)
	GameState.set_flag("rogue_news", true)
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)


func _story_exit(g: Control) -> Dictionary:
	for e: Dictionary in g.world.exits:
		if e["id"] == str(JsonData.load_dict("res://data/story.json")["rogue"]["exit"]):
			return e
	return {}


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		tree.root.push_input(ev)


## Talks to whoever has focus by "key", "touch" or "pad", picking choice
## number picks[i] at the i-th set of choices. Returns {"lines", "choices"}.
func _converse(app: Control, how: String, picks: Array) -> Dictionary:
	var box: Control = app.game.dialogue
	var lines: Array[String] = []
	var shown: Array = []
	match how:
		"key":
			_key(KEY_E)
		"pad":
			_pad(JOY_BUTTON_A)
		"touch":
			await _paw_button(app)
	await _frames(2)
	for i in 80:
		if not box.is_open:
			break
		var t := GameState.format_text(str(box.line.get("text", "")))
		if lines.is_empty() or lines[lines.size() - 1] != t:
			lines.append(t)
		if box.choices_shown():
			shown.append(box.line["choices"])
			var pick: int = picks.pop_front() if not picks.is_empty() else 0
			match how:
				"touch":
					await _tap_at(app, box.choice_rects[pick].get_center())
				"key":
					for k in pick:
						_key(KEY_DOWN)
					_key(KEY_E)
				"pad":
					for k in pick:
						_pad(JOY_BUTTON_DPAD_DOWN)
					_pad(JOY_BUTTON_A)
		else:
			match how:
				"touch":
					await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
				"key":
					_key(KEY_E)
				"pad":
					_pad(JOY_BUTTON_A)
		await _frames(2)
	await _frames(2)
	return {"lines": " | ".join(lines), "choices": shown}


func test_question_slate_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	await _investigate(g)
	var slate := Story.rogue_npc()
	check(not g.world.npc_by_id(slate).is_empty(), "Slate is by the river")
	check(g.world_view.npc_nodes.has(slate), "and drawn")
	var e := _story_exit(g)
	check(not e.is_empty() and not g.world.is_open(e), "the story exit is closed")
	check_eq(g.goal_label.text, strings["story.goal_investigate"], "goal: investigate")
	await _near(g, slate)
	if not is_headless():
		await _settle()
		_save(await _screen(), "story_slate_desktop")
	var r := await _converse(app, "key", [0, 0])
	check_eq((r["choices"][0] as Array).size(), 2, "not carrying: no prey choice (%s)" % [r["choices"][0]])
	check(r["lines"].contains("With friends"), "he lets it slip (%s)" % r["lines"])
	check(r["lines"].contains("didn't come quietly"), "the red fur (%s)" % r["lines"])
	check_eq(GameState.get_flag("rogue_choice"), "question", "choice saved")
	check(g.world.is_leaving(slate), "he walks off")
	check(g.world.trail_marks.is_empty(), "no scent trail: he's in plain sight")
	check_eq(g.goal_label.text, strings["story.goal_follow"], "goal: follow the rogue")
	check(g.world.is_open(e), "the story exit is open")
	await _until(func() -> bool: return g.world.npc_by_id(slate).is_empty(), 9000)
	check(g.world.npc_by_id(slate).is_empty(), "he's gone through the exit")
	await _frames(2)
	check(not g.world_view.npc_nodes.has(slate), "his sprite too")
	# After him: into rogue land, and back.
	_place_near_exit(g, "rogue_camp")
	await _walk_until_area(app, "move_right", "rogue_camp")
	await _wait_travel(g)
	check_eq(g.goal_label.text, strings["story.goal_follow"], "the goal stays")
	if not is_headless():
		await _settle()
		_save(await _screen(), "story_rogue_land_desktop")
	_place_near_exit(g, "hunting_grounds_2")
	await _walk_until_area(app, "move_left", "hunting_grounds_2")
	await _wait_travel(g)
	check_eq(Player.spawn(), "from_rogue_land", "back by the old trail")
	check(g.world.npc_by_id(slate).is_empty(), "Slate doesn't come back")
	# The choice survives the save hook.
	var saved := JSON.stringify(GameState.state.save_data())
	GameState.reset()
	GameState.state.load_save_data(JSON.parse_string(saved))
	check_eq(GameState.get_flag("rogue_choice"), "question", "loaded: the choice")
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	check(g.world.npc_by_id(slate).is_empty() and g.world.is_open(_story_exit(g)), "loaded: no Slate, the exit open")
	_close(app)


func test_threaten_slate_by_touch_while_carrying() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	Player.state.carried_item = "mouse"
	await _investigate(g)
	var slate := Story.rogue_npc()
	await _near(g, slate)
	var r := await _converse(app, "touch", [1, 1])
	check_eq((r["choices"][0] as Array).size(), 3, "carrying: the prey choice too (%s)" % [r["choices"][0]])
	check(" ".join(r["choices"][1]).contains("red on your fur"), "the red-fur question offered")
	check(r["lines"].contains("precious border"), "he backs off (%s)" % r["lines"])
	check_eq(GameState.get_flag("rogue_choice"), "threaten", "choice saved")
	check(g.world.is_leaving(slate), "he bolts")
	check_eq(Player.carried_item(), "mouse", "Fern keeps her mouse")
	check(g.world.trail_marks.size() >= 2, "a scent trail (%d rings)" % g.world.trail_marks.size())
	await _frames(2)
	check_eq(g.world_view.trail_nodes.size(), g.world.trail_marks.size(), "drawn")
	if not is_headless():
		await _frames(10)
		_save(await _screen(), "story_trail_phone")
	await _until(func() -> bool: return g.world.npc_by_id(slate).is_empty(), 4000)
	check(g.world.npc_by_id(slate).is_empty(), "gone fast")
	# The trail stays when Fern comes back.
	g.load_area("hunting_grounds_2", "from_hunting_grounds")
	await _frames(2)
	check(g.world_view.trail_nodes.size() >= 2, "the trail is still there after a reload")
	_place_near_exit(g, "rogue_camp")
	await _joystick_until_area(app, Vector2.RIGHT, "rogue_camp")
	_close(app)


func test_bribe_slate_by_gamepad() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	Player.state.carried_item = "mouse"
	await _investigate(g)
	var slate := Story.rogue_npc()
	await _near(g, slate)
	var r := await _converse(app, "pad", [2, 0])
	check(r["lines"].contains("I brought you prey"), "Fern offers the mouse (%s)" % r["lines"])
	check(r["lines"].contains("didn't come quietly"), "the red fur (%s)" % r["lines"])
	check(r["lines"].contains("old trail east"), "he tells her where (%s)" % r["lines"])
	check_eq(GameState.get_flag("rogue_choice"), "bribe", "choice saved")
	check_eq(Player.carried_item(), "", "he took the mouse")
	check(not g.world.npc_by_id(slate).is_empty() and not g.world.is_leaving(slate), "he stays to eat")
	await _frames(2)
	check(g.world_view.way_arrow.visible, "the arrow shows the way")
	check(g.world.is_open(_story_exit(g)), "the exit is open")
	if not is_headless():
		g.world.player_pos = Vector2(820, 170)
		await _settle()
		_save(await _screen(), "story_arrow_desktop")
	await _near(g, slate)
	r = await _converse(app, "pad", [])
	check(r["lines"].contains("get lost"), "after: get lost (%s)" % r["lines"])
	check(g.world_view.way_arrow.visible, "the arrow stays")
	_close(app)


# --- Part C


## Fern following Slate, arrived in the rogue camp.
func _in_rogue_camp(g: Control) -> void:
	for k in ["wick_missing", "rogue_news", "rogue_met"]:
		GameState.set_flag(k, true)
	GameState.set_flag("rogue_choice", "question")
	g.load_area(Story.camp_area(), "from_hunting_grounds_2")
	await _frames(2)


## Walks Fern from the entrance to the log until it has focus.
func _walk_to_log(app: Control) -> void:
	var g: Control = app.game
	var w = g.world
	var sp: Dictionary = w.spot_by_id("hide_log")
	var target: Vector2 = sp["prompt"] + Vector2(0, 6)
	for i in 400:
		if w.focus_id == "hide_log":
			break
		var d: Vector2 = target - w.player_pos
		w.player_pos += d.limit_length(1.5)
		await tree.process_frame
	check_eq(w.focus_id, "hide_log", "the log has the prompt")


## Presses through the cutscene ("key", "pad" or "touch") until it ends.
## Returns the lines shown and the furthest the camera went (world x).
func _watch(app: Control, how: String) -> Dictionary:
	var g: Control = app.game
	var box: Control = g.dialogue
	var lines: Array[String] = []
	var furthest := 0.0
	var until := Time.get_ticks_msec() + 30000
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


func test_rogue_camp_cutscene_by_keyboard() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	await _in_rogue_camp(g)
	check(g.message.visible and g.message.text == strings["story.stay_hidden"], "Stay out of sight... (%s)" % g.message.text)
	for id in ["wick", "vex", "slate"]:
		check(g.world_view.npc_nodes.has(id), "%s is drawn" % id)
	check_eq(g.world_view.npc_nodes["wick"].cat.rest, "sleep", "Wick lies down")
	# Walking into the open: stopped, and told.
	Input.action_press("move_right")
	await _until(func() -> bool: return g.message.text == strings["story.too_risky"], 4000)
	Input.action_release("move_right")
	check_eq(g.message.text, strings["story.too_risky"], "Too risky. Find somewhere to hide.")
	check(g.world.player_pos.x < g.world.barriers[0]["rect"].position.x, "she stays in the entrance pocket")
	# The log.
	await _walk_to_log(app)
	# (The label waits until the last line over Fern has faded.)
	await _until(func() -> bool: return not g.message.visible, 4000)
	await _frames(2)
	check(g.prompt_label.visible and g.prompt_label.text == strings["story.hide_label"], "a 'Hide' label over the prompt")
	if not is_headless():
		await _settle()
		_save(await _screen(), "story_log_desktop")
	_key(KEY_E)
	await _frames(2)
	check(g.in_cutscene(), "hiding starts the cutscene")
	check(g.world.hiding and g.world.crouching, "Fern crouches behind the log")
	var at: Vector2 = g.world.player_pos
	Input.action_press("move_left")
	await _frames(20)
	Input.action_release("move_left")
	check(g.world.player_pos.distance_to(at) < 0.5, "no walking during the cutscene")
	check(not g.touch.visible, "no touch controls")
	await _frames(2)
	check(not g.world_view.paw.visible and not g.prompt_label.visible, "no paw prompt or Hide label while hiding")
	check(not g.goal_label.visible, "no goal line over the cutscene")
	var shot := false
	var box: Control = g.dialogue
	await _until(func() -> bool: return box.is_open, 8000)
	if not is_headless():
		await _until(func() -> bool: return not box.is_typing(), 4000)
		_save(await _screen(), "story_cutscene_desktop")
		shot = true
	var r := await _watch(app, "key")
	var data := JsonData.load_dict(Story.cutscene_path())
	var says: int = (data["steps"] as Array).filter(func(st): return st.has("say")).size()
	check_eq(r["n"], says, "every line shown (%s)" % r["lines"])
	check(r["lines"].contains("patrol times") and r["lines"].contains("Let them come to us"), "the overheard talk")
	check(r["furthest"] > 340.0, "the camera went over to the rogues (%.0f)" % r["furthest"])
	check(g.camera_rect.has_point(g.world.player_pos), "and back to Fern")
	check(g.world.npc_by_id("slate")["pos"].distance_to(Vector2(424, 162)) < 1.0, "Slate walked over to Vex")
	check(not g.world.hiding, "Fern can move again")
	check_eq(GameState.get_flag("rogue_camp_found"), true, "rogue_camp_found")
	await _frames(2)
	check_eq(g.goal_label.text, strings["story.goal_warn"], "goal: warn the deputy")
	check(g.world.spot_by_id("hide_log").is_empty() or not g.world.is_open(g.world.spot_by_id("hide_log")), "no hiding again")
	# Home on foot through Hunting Grounds 2, then the deputy.
	_place_near_exit(g, "hunting_grounds_2")
	await _walk_until_area(app, "move_left", "hunting_grounds_2")
	await _wait_travel(g)
	check(g.world.npc_by_id("wick").is_empty(), "Wick stays behind")
	g.load_area("camp", "from_hunting")
	await _frames(2)
	await _near(g, Patrols.deputy())
	var lines := await _talk_by_keys(app)
	var all := " | ".join(lines)
	check(all.contains("What did you find?") and all.contains("where they're keeping Wick"), "Fern warns him (%s)" % all)
	check(all.contains("past the border") and all.contains("speak to Larch") and all.contains("Go rest"), "he stalls (%s)" % all)
	check_eq(GameState.get_flag("rogue_warned"), true, "rogue_warned")
	check_eq(GameState.get_flag("told_rook"), true, "told_rook")
	await _frames(2)
	check_eq(g.goal_label.text, strings["story.goal_rest"], "goal: rest in the den")
	lines = await _talk_by_keys(app)
	check(lines.size() == 1 and lines[0].contains("I said rest"), "Rook only says to rest (%s)" % " | ".join(lines))
	check(g.world.npc_by_id("wick").is_empty(), "Wick still isn't in camp")
	# The save hook.
	var saved := JSON.stringify(GameState.state.save_data())
	GameState.reset()
	GameState.state.load_save_data(JSON.parse_string(saved))
	for k in ["rogue_camp_found", "rogue_warned", "wick_missing", "told_rook"]:
		check_eq(GameState.get_flag(k), true, "loaded: %s" % k)
	g.load_area(Story.camp_area(), "from_hunting_grounds_2")
	await _frames(2)
	check(not g.world.npc_by_id("wick").is_empty(), "loaded: Wick still in the rogue camp")
	check(g.message.text != strings["story.stay_hidden"] or not g.message.visible, "no 'stay out of sight' once found")
	_close(app)


func test_rogue_camp_cutscene_by_touch() -> void:
	var app: Control = await _start(TARGET_PHONE)
	var g: Control = app.game
	_freeze_needs(70, 70)
	await _in_rogue_camp(g)
	await _walk_to_log(app)
	await _frames(2)
	check(g.touch.visible and g.touch.highlight, "the paw button is lit at the log")
	await _paw_button(app)
	check(g.in_cutscene(), "the paw button hides Fern")
	check(not g.touch.visible, "touch controls hidden")
	await _until(func() -> bool: return g.dialogue.is_open, 8000)
	if not is_headless():
		await _until(func() -> bool: return not g.dialogue.is_typing(), 4000)
		_save(await _screen(), "story_cutscene_phone")
	var r := await _watch(app, "touch")
	check(r["lines"].contains("Let them come to us"), "tapped through (%s)" % r["lines"])
	check_eq(GameState.get_flag("rogue_camp_found"), true, "found")
	await _frames(2)
	check(g.touch.visible, "touch controls back")
	_close(app)


func test_rogue_camp_cutscene_by_gamepad() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	_freeze_needs(70, 70)
	await _in_rogue_camp(g)
	await _walk_to_log(app)
	_pad(JOY_BUTTON_A)
	await _frames(2)
	check(g.in_cutscene(), "South hides Fern")
	var r := await _watch(app, "pad")
	check(r["lines"].contains("Let them come to us"), "pressed through (%s)" % r["lines"])
	check_eq(GameState.get_flag("rogue_camp_found"), true, "found")
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

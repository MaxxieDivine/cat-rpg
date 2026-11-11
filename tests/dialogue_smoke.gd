extends "res://tests/test_base.gd"
## Talking to the cats in the real game scene, at phone and desktop sizes:
## whole conversations by touch and by keyboard, the typewriter and
## Interact, choices, flags changing later lines, the paw prompt, facing,
## voice blips, and (with a display) pixel checks of the dialogue box with a
## line and with choices. Lines and expected values come from data/.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const World := preload("res://scripts/core/world.gd")
const DialogueBox := preload("res://scripts/view/dialogue_box.gd")
const MAIN_SCENE := "res://scenes/app.tscn"

## name, CSS size, devicePixelRatio, insets [top, right, bottom, left] (CSS px), touch
const PHONE := ["phone", Vector2i(844, 390), 3.0, [0.0, 47.0, 21.0, 47.0], true]
const SMALL_PHONE := ["small_phone", Vector2i(667, 375), 2.0, [0.0, 0.0, 0.0, 0.0], true]
const DESKTOP := ["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0], false]

var tuning: Dictionary
var speakers: Dictionary
var convs: Dictionary = {}


func before_each() -> void:
	tuning = JsonData.load_dict("res://data/tuning.json")
	speakers = JsonData.load_dict("res://data/speakers.json")
	for id in ["bram", "sorrel", "wick", "cow"]:
		convs[id] = JsonData.load_dict("res://data/dialogue/%s.json" % id)


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []
	ScreenMetrics.override_touch = -1
	ScreenMetrics.override_fullscreen = -1
	ScreenMetrics.fullscreen_requests = 0
	for a in ["move_left", "move_right", "move_up", "move_down", "run", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)


# --- Whole conversations


func test_all_conversations_by_touch_on_a_phone() -> void:
	var app: Control = await _start(PHONE)
	var g: Control = app.game
	# Wick first, sharing the vole; then Sorrel's story; then Bram, eager.
	var wick := await _converse(app, "wick", [0, 1], true)
	check(wick.has("good_one") and wick.has("say_hi"), "phone: Wick's shared path (%s)" % [wick])
	var sorrel := await _converse(app, "sorrel", [], true)
	check_eq(sorrel, ["come", "river", "stones", "grandmother", "walk_first"] as Array[String], "phone: Sorrel's story")
	var bram := await _converse(app, "bram", [0], true)
	check(bram.has("bram_eager"), "phone: Bram eager")
	check_eq(GameState.get_flag("vole"), "shared", "phone: vole shared")
	check_eq(GameState.get_flag("bram_reply"), "eager", "phone: bram_reply")
	check_eq(GameState.bond("bram"), 1, "phone: bond bram")
	check_eq(GameState.bond("wick"), 1, "phone: bond wick (stream jab)")
	for id in ["bram", "sorrel", "wick"]:
		check_eq(GameState.get_flag("talked_" + id), true, "phone: talked_%s" % id)
	# The vole changes both cats' later lines; repeats are short.
	check_eq(await _converse(app, "sorrel", [], true), ["thanks"] as Array[String], "phone: Sorrel thanks Fern for the vole")
	check_eq(await _converse(app, "sorrel", [], true), ["dozing"] as Array[String], "phone: thanks only once")
	check_eq(await _converse(app, "wick", [], true), ["repeat_shared"] as Array[String], "phone: Wick asks if she liked it")
	check_eq(await _converse(app, "bram", [], true), ["repeat"] as Array[String], "phone: Bram's repeat line")
	check(g.touch.visible, "phone: joystick back after talking")
	_close(app)


func test_all_conversations_by_keyboard_on_desktop() -> void:
	var app: Control = await _start(DESKTOP)
	# Bram nervous (Down, then Interact), Sorrel, Wick keeps the vole.
	var bram := await _converse(app, "bram", [1], false)
	check(bram.has("bram_nervous") and not bram.has("bram_eager"), "desktop: Bram nervous (%s)" % [bram])
	await _converse(app, "sorrel", [], false)
	var wick := await _converse(app, "wick", [1, 0], false)
	check(wick.has("our_secret"), "desktop: Wick kept path (%s)" % [wick])
	check_eq(GameState.get_flag("vole"), "kept", "desktop: vole kept")
	check_eq(GameState.bond("wick"), 1, "desktop: bond wick (ate it)")
	check_eq(GameState.bond("bram"), 0, "desktop: no bond for nervous")
	check_eq(await _converse(app, "sorrel", [], false), ["empty_pile"] as Array[String], "desktop: Sorrel notices the empty pile")
	check_eq(await _converse(app, "wick", [], false), ["repeat_kept"] as Array[String], "desktop: Wick's secret")
	_close(app)


func test_the_cow_still_says_moo() -> void:
	var app: Control = await _start(DESKTOP)
	var seen := await _converse(app, "cow", [], false)
	check_eq(seen, ["moo"] as Array[String], "cow: one line")
	_close(app)


# --- Typewriter, Interact, arrow


func test_typewriter_interact_and_arrow() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var box: Control = g.dialogue
	await _open_talk(app, "bram", false)
	var first: String = convs["bram"]["nodes"]["there_you_are"]["text"]
	check(box.is_open, "box open")
	await tree.create_timer(0.25).timeout
	var partial: String = box.visible_text()
	check(partial.length() > 2 and partial.length() < first.length(), "typing out (%d of %d chars)" % [partial.length(), first.length()])
	check(first.begins_with(partial), "shows the start of the line")
	check_near(partial.length(), 0.25 * float(tuning["dialogue"]["cps"]), 6.0, "about cps characters per second")
	check(box.is_typing(), "still typing")
	_key(KEY_E)
	await tree.process_frame
	check_eq(box.visible_text(), first, "Interact finishes the line at once")
	check_eq(str(box.line["node"]), "there_you_are", "still on the first line")
	check(not box.is_typing() and not box.choices_shown(), "done: arrow shows")
	_key(KEY_SPACE)
	await tree.process_frame
	check_eq(str(box.line["node"]), "dawn_patrol", "pressing again advances")
	check(box.is_typing(), "next line types out")
	DialogueManager.stop()
	g._show({"type": "end"})
	_close(app)


func test_choices_with_keys_wrap_and_tap_on_touch() -> void:
	var app: Control = await _start(DESKTOP)
	var box: Control = app.game.dialogue
	await _open_talk(app, "bram", false)
	_key(KEY_E)  # finish
	await tree.process_frame
	_key(KEY_E)  # advance to the choice line
	await tree.process_frame
	check(not box.choices_shown(), "choices wait until the line has typed out")
	_key(KEY_E)
	await tree.process_frame
	check(box.choices_shown(), "choices shown")
	check_eq(box.selected, 0, "first choice selected")
	_key(KEY_UP)
	await tree.process_frame
	check_eq(box.selected, 1, "Up wraps to the last choice")
	_key(KEY_DOWN)
	await tree.process_frame
	check_eq(box.selected, 0, "Down moves back")
	# A gamepad pick works too.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	tree.root.push_input(pad)
	var pad_up := pad.duplicate()
	pad_up.pressed = false
	tree.root.push_input(pad_up)
	await tree.process_frame
	check_eq(box.selected, 1, "gamepad D-pad moves the choice")
	_close(app)


# --- Prompt, facing, locked movement


func test_only_the_nearest_npc_gets_the_paw_prompt() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var w = g.world
	var bram: Dictionary = w.npc_by_id("bram")
	var cow: Dictionary = w.npc_by_id("cow")
	cow["pos"] = bram["pos"] + Vector2(40, 0)
	cow["rect"] = World.footprint_rect(cow["pos"], cow["footprint"])
	w.solids.assign([bram["rect"], cow["rect"]])
	var between: float = (bram["rect"].end.x + cow["rect"].position.x) / 2.0
	w.player_vel = Vector2.ZERO
	w.player_pos = Vector2(between - 3.0, bram["rect"].end.y)
	await tree.process_frame
	await tree.process_frame
	var paw: Sprite2D = g.world_view.paw
	check(w.distance_to_rect(cow["rect"]) <= cow["talk_radius"], "both in range")
	check(paw.visible, "one paw prompt")
	check_near(paw.position.x + paw.texture.get_width() / 2.0, g.world_view.npc_head("bram").x, 1.0, "prompt over the nearer Bram")
	w.player_pos.x = between + 3.0
	await tree.process_frame
	await tree.process_frame
	check_near(paw.position.x + paw.texture.get_width() / 2.0, g.world_view.npc_head("cow").x, 1.0, "prompt moves to the nearer cow")
	_close(app)


func test_face_each_other_and_lock_movement() -> void:
	var app: Control = await _start(DESKTOP)
	var g: Control = app.game
	var w = g.world
	await _open_talk(app, "wick", false)
	var wick_node: Node2D = g.world_view.npc_nodes["wick"]
	var player: Sprite2D = g.world_view.player
	var wick: Dictionary = w.npc_by_id("wick")
	var fern_left: bool = w.player_pos.x < wick["pos"].x
	check_eq(player.flip_h, not fern_left, "Fern faces Wick")
	check_eq(wick_node.sprite.flip_h, fern_left, "Wick faces Fern")
	var pos: Vector2 = w.player_pos
	var wpos: Vector2 = wick["pos"]
	Input.action_press("move_left")
	await tree.create_timer(0.4).timeout
	Input.action_release("move_left")
	check_eq(w.player_pos, pos, "can't walk while talking")
	check_eq(wick["pos"], wpos, "Wick stops pacing to talk")
	# Both cats stay on screen above the box.
	await tree.create_timer(0.6).timeout
	var box_top: float = g.dialogue.box_rect.position.y
	for feet: Vector2 in [w.player_pos, wick["pos"]]:
		var ui: Vector2 = g.world_to_ui(feet)
		check(ui.y < box_top and ui.y > g.view_rect.position.y + 20.0, "cat at %s is visible above the box (y=%s, box top %s)" % [feet, ui.y, box_top])
	_close(app)


## Every NPC, at phone and desktop sizes (including the tallest view,
## view.max): when talking, both cats are on screen above the box.
func test_every_conversation_is_framed_above_the_box() -> void:
	var tall := ["desktop_tall", Vector2i(1280, 800), 1.0, [0.0, 0.0, 0.0, 0.0], false]
	for cfg in [PHONE, DESKTOP, tall]:
		var app: Control = await _start(cfg)
		var g: Control = app.game
		var w = g.world
		for id in ["bram", "sorrel", "wick", "cow"]:
			await _open_talk(app, id, cfg[4])
			check(g.dialogue.is_open, "%s: talking to %s" % [cfg[0], id])
			await tree.create_timer(0.8).timeout
			var box_top: float = g.dialogue.box_rect.position.y
			var npc: Dictionary = w.npc_by_id(id)
			for who in [["Fern", w.player_pos, g.world_view.player.position + Vector2(0, -20)], [id, npc["pos"], g.world_view.npc_head(id)]]:
				var feet: Vector2 = g.world_to_ui(who[1])
				var head: Vector2 = g.world_to_ui(who[2])
				check(feet.y < box_top - 2.0 and head.y > g.view_rect.position.y and head.y > app.metrics.safe_rect.position.y, "%s talking to %s: %s visible above the box (feet y=%s, head y=%s, box top %s)" % [cfg[0], id, who[0], feet.y, head.y, box_top])
			DialogueManager.stop()
			g._show({"type": "end"})
			await tree.process_frame
		_close(app)
		after_each()


# --- Phone layout


func test_phone_layout_hides_joystick_and_keeps_targets_big() -> void:
	for cfg in [PHONE, SMALL_PHONE]:
		var app: Control = await _start(cfg)
		var g: Control = app.game
		var m = app.metrics
		var box: Control = g.dialogue
		var name: String = cfg[0]
		check(g.touch.visible, "%s: joystick before talking" % name)
		await _open_talk(app, "wick", true)
		check(not g.touch.visible, "%s: joystick hidden while talking" % name)
		var safe: Rect2 = m.safe_rect
		check(safe.encloses(box.box_rect), "%s: box inside the safe area" % name)
		check(safe.encloses(box.plate_rect), "%s: name plate inside the safe area" % name)
		check_near(box.box_rect.size.y, roundf(m.ui_size.y * float(tuning["dialogue"]["box_height"])), 1.0, "%s: box about 40%% of the screen height" % name)
		var css: float = box.font_size * m.px_per_unit.y / m.dpr
		check(css >= 14.0, "%s: text at least 14 CSS px (%s)" % [name, css])
		var liga := TextServerManager.get_primary_interface().name_to_tag("liga")
		check(box.font is FontVariation and int(box.font.opentype_features.get(liga, 1)) == 0, "%s: ligatures off (Pixelify's fi reads as an A)" % name)
		# Tap through to the choices.
		await _tap_until_choices(app)
		check(box.choices_shown(), "%s: choices shown" % name)
		check(not box.show_selection, "%s: no keyboard highlight on touch" % name)
		for r: Rect2 in box.choice_rects:
			check(r.size.y * m.px_per_unit.y / m.dpr >= float(tuning["dialogue"]["min_choice_css"]) - 0.01, "%s: choice %s at least %s CSS px tall" % [name, r, tuning["dialogue"]["min_choice_css"]])
			check(safe.encloses(r), "%s: choice %s inside the safe area" % [name, r])
			check(not r.intersects(box.box_rect), "%s: choice clear of the box" % name)
			check(not r.intersects(app.hud.get_global_rect()), "%s: choice clear of the build label" % name)
		# A tap that misses every choice does nothing.
		var miss := Vector2(box.box_rect.position.x + 30, safe.position.y + 30)
		await _tap_at(app, miss)
		check(box.choices_shown(), "%s: a tap off the choices doesn't pick one" % name)
		# Tap the second choice.
		await _tap_at(app, box.choice_rects[1].get_center())
		check_eq(str(box.line.get("node", "")), "fern_worried", "%s: tapping a choice picks it" % name)
		check(box.on_right(), "%s: Fern's line on the right" % name)
		check(box.portrait_rect.position.x > box.box_rect.get_center().x, "%s: Fern's portrait on the right" % name)
		_close(app)
		after_each()


# --- Voice


func test_voice_blips_on_the_voice_bus_only_after_start() -> void:
	var app: Control = await _open(DESKTOP)
	check(app.game == null, "on the title screen")
	check(not _any_audio_player(tree.root), "no audio players before tap-to-start")
	await _tap(app, app.metrics.safe_rect.get_center())
	var g: Control = app.game
	var voice: Node = g.voice
	check(AudioServer.get_bus_index("Voice") >= 0, "Voice bus exists")
	for p in voice.get_children():
		check_eq((p as AudioStreamPlayer).bus, &"Voice", "player on the Voice bus")
	await _open_talk(app, "bram", false)
	var jitter := float(tuning["dialogue"]["pitch_jitter"])
	var pitch := float(speakers["bram"]["voice"]["pitch"])
	var pitches: Array[float] = []
	while g.dialogue.is_typing():
		var before: int = voice.blips_played
		await tree.process_frame
		if voice.blips_played > before:
			pitches.append(voice.last_pitch)
	var line: String = g.dialogue.visible_text()
	var visible := line.replace(" ", "").length()
	check_near(voice.blips_played, ceilf(visible / float(tuning["dialogue"]["blip_every"])), 1.0, "one blip every %s characters" % tuning["dialogue"]["blip_every"])
	for p in pitches:
		check(absf(p / pitch - 1.0) <= jitter + 0.0001, "pitch %s within +-%d%% of Bram's %s" % [p, jitter * 100.0, pitch])
	check(pitches.max() != pitches.min(), "pitches vary")
	var order := ["bram", "fern", "wick"]
	check(float(speakers["bram"]["voice"]["pitch"]) < float(speakers["fern"]["voice"]["pitch"]) and float(speakers["fern"]["voice"]["pitch"]) < float(speakers["wick"]["voice"]["pitch"]), "Bram low, Fern middle, Wick high (%s)" % [order])
	check(float(speakers["sorrel"]["voice"]["volume_db"]) < float(speakers["fern"]["voice"]["volume_db"]) and int(speakers["sorrel"]["voice"]["blip_ms"]) > int(speakers["fern"]["voice"]["blip_ms"]), "Sorrel soft and slow")
	_close(app)


func _any_audio_player(n: Node) -> bool:
	if n is AudioStreamPlayer:
		return true
	for c in n.get_children():
		if _any_audio_player(c):
			return true
	return false


# --- Pixels


func test_box_pixels_phone() -> void:
	await _box_pixels(PHONE)


func test_box_pixels_desktop() -> void:
	await _box_pixels(DESKTOP)


## Draws the box with a line, then with choices, and checks real pixels:
## paper inside the border, ink border, the speaker's colour in the portrait
## and name plate, text drawn in the text area and in each choice, nothing
## of the box drawn in the notch / gesture-bar insets.
func _box_pixels(cfg: Array) -> void:
	var name: String = cfg[0]
	var by_touch: bool = cfg[4]
	var app: Control = await _start(cfg)
	var g: Control = app.game
	var box: Control = g.dialogue
	await _open_talk(app, "bram", by_touch)
	await _press(app, by_touch)  # finish the first line
	if is_headless():
		check(box.is_open, "%s: box open (pixel checks need a display)" % name)
		_close(app)
		return
	var img := await _screen()
	_check_box_pixels(app, img, name + " line")
	var text_ink := _count_ink(img, app.metrics, box.text_rect)
	check(text_ink > 200, "%s line: text drawn in the text area (%d ink px)" % [name, text_ink])
	_check_text_height(img, app, name)
	_save(img, "dialogue_%s_line" % name)

	if by_touch:
		await _tap_until_choices(app)
	else:
		await _keys_until_choices(app)
	check(box.choices_shown(), "%s: choices shown" % name)
	img = await _screen()
	_check_box_pixels(app, img, name + " choices")
	for i in box.choice_rects.size():
		var r: Rect2 = box.choice_rects[i]
		var inside := _px(app.metrics, r.position + Vector2(5, r.size.y / 2.0))
		var want: Color = DialogueBox.SELECT if (box.show_selection and i == box.selected) else DialogueBox.PAPER
		_check_color(img, inside, want, "%s choice %d fill" % [name, i])
		_check_color(img, _px(app.metrics, r.position + Vector2(1, r.size.y / 2.0)), DialogueBox.INK, "%s choice %d border" % [name, i])
		check(_count_ink(img, app.metrics, r.grow(-DialogueBox.BORDER - 2)) > 40, "%s choice %d text drawn" % [name, i])
	_save(img, "dialogue_%s_choices" % name)
	_close(app)


func _check_box_pixels(app: Control, img: Image, name: String) -> void:
	var m = app.metrics
	var box: Control = app.game.dialogue
	var b: Rect2 = box.box_rect
	var col: Color = box.speaker_color()
	var portrait: Rect2 = box.portrait_rect
	_check_color(img, _px(m, b.position + Vector2(1.5, b.size.y / 2.0)), DialogueBox.INK, name + ": box border")
	_check_color(img, _px(m, b.position + Vector2(DialogueBox.BORDER + 3, b.size.y - DialogueBox.BORDER - 3)), DialogueBox.PAPER, name + ": paper inside the box")
	_check_color(img, _px(m, portrait.position + portrait.size * 0.15), col, name + ": portrait in the speaker's colour")
	_check_color(img, _px(m, box.plate_rect.position + Vector2(DialogueBox.BORDER + 3, box.plate_rect.size.y / 2.0)), col, name + ": name plate in the speaker's colour")
	check(not app.game.touch.visible, name + ": joystick hidden")
	# Nothing of the box in the insets below / beside the safe area.
	var safe_px: Rect2i = m.safe_rect_px()
	var bad := 0
	for y in range(safe_px.end.y + 1, img.get_height(), 2):
		for x in range(0, img.get_width(), 7):
			if _near(img.get_pixel(x, y), DialogueBox.PAPER):
				bad += 1
	for x in range(0, safe_px.position.x - 1, 2):
		for y in range(0, img.get_height(), 7):
			if _near(img.get_pixel(x, y), DialogueBox.PAPER):
				bad += 1
	check_eq(bad, 0, name + ": box pixels outside the safe area")


## Readable on a phone: the tallest glyphs are at least ~10 CSS px.
func _check_text_height(img: Image, app: Control, name: String) -> void:
	var m = app.metrics
	var r: Rect2 = app.game.dialogue.text_rect
	var p0 := _px(m, r.position)
	var p1 := _px(m, r.end)
	var first := -1
	var gap_after := -1
	for y in range(p0.y, p1.y):
		var ink := false
		for x in range(p0.x, p1.x, 1):
			if _is_ink(img.get_pixel(x, y)):
				ink = true
				break
		if ink and first < 0:
			first = y
		elif not ink and first >= 0:
			gap_after = y
			break
	var css: float = float(gap_after - first) / m.dpr
	check(css >= 10.0, "%s: first text row is %s CSS px tall (readable)" % [name, css])


func _count_ink(img: Image, m, r: Rect2) -> int:
	var p0 := _px(m, r.position)
	var p1 := _px(m, r.end)
	var n := 0
	for y in range(maxi(0, p0.y), mini(img.get_height(), p1.y), 2):
		for x in range(maxi(0, p0.x), mini(img.get_width(), p1.x), 2):
			if _is_ink(img.get_pixel(x, y)):
				n += 1
	return n


func _is_ink(c: Color) -> bool:
	return c.get_luminance() < 0.25


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03


func _check_color(img: Image, p: Vector2i, want: Color, what: String) -> void:
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		check(false, "%s: %s is off screen" % [what, p])
		return
	var c := img.get_pixelv(p)
	check(_near(c, want), "%s: pixel %s is %s, expected %s" % [what, p, c.to_html(false), want.to_html(false)])


func _px(m, ui: Vector2) -> Vector2i:
	return Vector2i((ui * m.px_per_unit).floor())


func _screen() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return tree.root.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	if shots_dir != "":
		var path := shots_dir.path_join("%s.png" % name)
		img.save_png(path)
		print("     shot: ", path)


# --- Driving the game


## Opens the app at a size and taps to start.
func _start(cfg: Array) -> Control:
	var app: Control = await _open(cfg)
	await _tap(app, app.metrics.safe_rect.get_center())
	check(app.game != null, "%s: game started" % cfg[0])
	return app


## Plays a whole conversation with `id`, picking choices by index from
## `picks`. Returns the node ids of every line shown, in order.
func _converse(app: Control, id: String, picks: Array, by_touch: bool) -> Array[String]:
	var g: Control = app.game
	var box: Control = g.dialogue
	var seen: Array[String] = []
	await _open_talk(app, id, by_touch)
	if not check(box.is_open, "%s: conversation with %s started" % [app.metrics.ui_size, id]):
		return seen
	var guard := 0
	while box.is_open and guard < 80:
		guard += 1
		var node := str(box.line["node"])
		if seen.is_empty() or seen[-1] != node:
			seen.append(node)
			_check_line(app, id)
		if box.is_typing():
			await _press(app, by_touch)
			check(not box.is_typing(), "%s: one press finishes the line" % node)
		elif box.choices_shown():
			var pick: int = picks.pop_front() if not picks.is_empty() else 0
			if by_touch:
				await _tap_at(app, box.choice_rects[pick].get_center())
			else:
				while box.selected != pick:
					_key(KEY_DOWN)
					await tree.process_frame
				await _press(app, false)
		else:
			await _press(app, by_touch)
	check(not box.is_open, "%s: conversation ended" % id)
	check(not g.world.is_talking(), "%s: movement unlocked after talking" % id)
	check(picks.is_empty(), "%s: every planned choice was offered" % id)
	return seen


## Checks the line on screen against its node in the dialogue file.
func _check_line(app: Control, conv: String) -> void:
	var box: Control = app.game.dialogue
	var node: Dictionary = convs[conv]["nodes"][str(box.line["node"])]
	var sp: Dictionary = speakers[node["speaker"]]
	check_eq(box.name_label.text, str(sp["name"]), "%s: name plate" % box.line["node"])
	check_eq(box.speaker_color(), Color(str(sp["color"])), "%s: portrait colour" % box.line["node"])
	check_eq(str(box.line["expression"]), str(node.get("expression", "neutral")), "%s: expression" % box.line["node"])
	check_eq(box.on_right(), node["speaker"] == "fern", "%s: Fern on the right, others on the left" % box.line["node"])
	check(app.metrics.safe_rect.encloses(box.box_rect), "%s: box inside the safe area" % box.line["node"])
	check(not app.game.touch.visible, "%s: joystick hidden" % box.line["node"])


## Puts Fern beside an NPC and talks: paw button on touch, E on keyboard.
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


## Interact: a tap anywhere (touch) or E (keyboard).
func _press(app: Control, by_touch: bool) -> void:
	if by_touch:
		await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))
	else:
		_key(KEY_E)
		await tree.process_frame


func _tap_until_choices(app: Control) -> void:
	var box: Control = app.game.dialogue
	for i in 20:
		if box.choices_shown() or not box.is_open:
			return
		await _tap_at(app, app.metrics.safe_rect.get_center() - Vector2(0, 40))


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


func _close(app: Control) -> void:
	DialogueManager.stop()
	tree.root.remove_child(app)
	app.free()


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

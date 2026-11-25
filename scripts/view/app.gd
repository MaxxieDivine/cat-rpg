extends Control
## Main scene. Owns ScreenMetrics, swaps the title screen for the game, shows
## the rotate-your-phone overlay in portrait and the build / fps label (the
## debug overlay: always on the title screen, so a phone can check the
## build; in the game only while Settings.debug_overlay is on, toggled by F3
## or three quick taps in the top-left corner). In the game the label also
## names the area and the spawn Fern arrived at and lists each mouse (spot,
## head up / down, alert %); debug buttons (keys H / T / M / N) set hunger /
## thirst to 5, put a mouse at the nearest prey spot or open the Name Editor.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const TitleScreen := preload("res://scripts/view/title.gd")
const GameScreen := preload("res://scripts/view/game.gd")
const RotateOverlay := preload("res://scripts/view/rotate_overlay.gd")
const FullscreenButton := preload("res://scripts/view/fullscreen_button.gd")
const VolumeButton := preload("res://scripts/view/volume_button.gd")
const BUILD_PATH := "res://data/build.json"

## Inspector hooks for trying values (0 = use Settings): camera zoom 1..3
## (see game.gd pick_zoom) and dialogue text scale 1 / 2.
@export var zoom_override := 0
@export var text_scale_override := 0

var metrics := ScreenMetrics.new()
var title: Control
var game: Control
var rotate: Control
var hud: Label
var fullscreen_button: Control
var volume_button: Control
## Debug overlay buttons: hunger -> 5, thirst -> 5.
var debug_buttons: Array[Button] = []
var build_text := ""
## Frame stats for the hud, refreshed twice a second.
var fps := 0
var fps_low := 0
## Average time all _process callbacks took per frame (ms), i.e. our own
## per-frame cost without rendering. If fps is low but this is small, the
## device is limited by rendering or the browser, not by game logic.
var logic_ms := 0.0

var _laying_out := false
## Corner buttons hidden while the Name Editor is open.
var _hidden_for_naming := false
## Times of the last corner taps (debug overlay toggle).
var _corner_taps: Array[float] = []
var _frames := 0
var _frame_time := 0.0
var _worst_dt := 0.0
var _logic_start := 0
var _logic_usec := 0
var _logic_frames := 0


## Runs before every other node's _process each frame.
class FrameStart extends Node:
	var app: Node
	func _process(_dt: float) -> void:
		app._logic_start = Time.get_ticks_usec()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var letterbox := ColorRect.new()
	letterbox.name = "Letterbox"
	letterbox.color = Color(str(JsonData.load_dict("res://data/palette.json").get("ui", {}).get("letterbox", "#264c33")))
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(letterbox)

	title = TitleScreen.new()
	title.name = "Title"
	title.start_requested.connect(start_game)
	add_child(title)

	rotate = RotateOverlay.new()
	rotate.name = "Rotate"
	add_child(rotate)

	hud = Label.new()
	hud.name = "Hud"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size", 11)
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hud.add_theme_constant_override("outline_size", 3)
	add_child(hud)
	fullscreen_button = FullscreenButton.new()
	add_child(fullscreen_button)
	volume_button = VolumeButton.new()
	add_child(volume_button)
	volume_button.configure(JsonData.load_dict("res://data/tuning.json").get("audio", {}).get("volume_steps", []))
	for which in ["hunger", "thirst", "mouse", "name"]:
		var b := Button.new()
		b.name = "Debug_" + which
		b.text = GameStrings.text("debug." + which)
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		b.add_theme_font_size_override("font_size", 13)
		if which == "mouse":
			b.pressed.connect(func() -> void:
				if game != null:
					game.debug_spawn_mouse())
		elif which == "name":
			b.pressed.connect(func() -> void:
				if game != null:
					game.open_name_editor())
		else:
			b.pressed.connect(func() -> void: debug_set_need(which))
		add_child(b)
		debug_buttons.append(b)
	Player.area_changed.connect(func(_a: String, _s: String) -> void: _update_hud())
	build_text = read_build_text()
	_update_hud()

	var start := FrameStart.new()
	start.app = self
	start.process_priority = -100000
	add_child(start)
	process_priority = 100000  # app._process runs last: measures the frame's logic

	if zoom_override > 0:
		Settings.camera_zoom = zoom_override
	if text_scale_override > 0:
		Settings.text_scale = text_scale_override
	Settings.changed.connect(relayout)
	get_window().size_changed.connect(relayout)
	relayout()


func start_game() -> void:
	if game != null:
		return
	game = GameScreen.new()
	game.name = "Game"
	add_child(game)
	game.naming_changed.connect(func(_open: bool) -> void:
		_place_buttons()
		_place_hud())
	move_child(game, title.get_index())  # below the overlays, hud and button
	title.queue_free()
	title = null
	relayout()


func relayout() -> void:
	if _laying_out:
		return
	_laying_out = true
	metrics.update(get_window())
	var portrait: bool = metrics.is_portrait()
	rotate.visible = portrait
	rotate.layout(metrics)
	if title != null:
		title.layout(metrics)
	if game != null:
		game.layout(metrics)
		game.set_paused(portrait)
	_place_hud()
	_place_buttons()
	_laying_out = false


## F3, or three taps within a second in the top-left corner, toggles the
## build / fps overlay.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		Settings.debug_overlay = not Settings.debug_overlay
		return
	if key != null and key.pressed and not key.echo and Settings.debug_overlay and game != null:
		if key.keycode == KEY_H and not game.naming():
			debug_set_need("hunger")
			return
		if key.keycode == KEY_T and not game.naming():
			debug_set_need("thirst")
			return
		if key.keycode == KEY_M and not game.naming():
			game.debug_spawn_mouse()
			return
		if key.keycode == KEY_N and not game.naming():
			game.open_name_editor()
			return
	var tap := event as InputEventScreenTouch
	if tap == null or not tap.pressed:
		return
	var corner := float(JsonData.load_dict("res://data/tuning.json").get("touch", {}).get("min_target", 48))
	var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * tap.position
	if p.x > metrics.safe_rect.position.x + corner or p.y > metrics.safe_rect.position.y + corner:
		_corner_taps.clear()
		return
	var now := Time.get_ticks_msec() / 1000.0
	_corner_taps.append(now)
	_corner_taps = _corner_taps.filter(func(t: float) -> bool: return now - t < 1.0)
	if _corner_taps.size() >= 3:
		_corner_taps.clear()
		Settings.debug_overlay = not Settings.debug_overlay


## Fullscreen button in the top-right corner; the volume button just left
## of it (or in the corner while the fullscreen one is hidden).
func _place_buttons() -> void:
	fullscreen_button.refresh()
	# In from the edge: rounded screen corners cut into the safe rect.
	var inset := float(JsonData.load_dict("res://data/tuning.json").get("ui", {}).get("button_inset", 12))
	fullscreen_button.place(metrics.safe_rect, inset)
	var x := fullscreen_button.position.x
	if fullscreen_button.visible:
		x -= volume_button.min_target
	volume_button.place(Vector2(x, fullscreen_button.position.y))
	# The Name Editor fills the screen: no corner buttons over its panel.
	# Only on open / close, so anything else that hides the volume button
	# (tests) keeps it hidden.
	var naming: bool = game != null and game.naming()
	if naming != _hidden_for_naming:
		_hidden_for_naming = naming
		volume_button.visible = not naming
	if naming:
		fullscreen_button.visible = false


## Debug: hunger or thirst to 5 (passing out follows soon after).
func debug_set_need(which: String) -> void:
	if game != null:
		game.debug_set_need(which, 5)


func read_build_text() -> String:
	var info := {}
	if FileAccess.file_exists(BUILD_PATH):
		info = JsonData.load_dict(BUILD_PATH)
	var sha := str(info.get("sha", ""))
	if sha.is_empty():
		return GameStrings.text("build.label", {"sha": GameStrings.text("build.dev"), "date": ""}).strip_edges()
	return GameStrings.text("build.label", {"sha": sha, "date": str(info.get("date", ""))})


func _process(dt: float) -> void:
	if _logic_start > 0:
		_logic_usec += Time.get_ticks_usec() - _logic_start
		_logic_frames += 1
	_frames += 1
	_frame_time += dt
	_worst_dt = maxf(_worst_dt, dt)
	if _frame_time >= 0.5:
		fps = roundi(_frames / _frame_time)
		fps_low = roundi(1.0 / maxf(_worst_dt, 0.001))
		logic_ms = _logic_usec / 1000.0 / maxi(1, _logic_frames)
		_logic_usec = 0
		_logic_frames = 0
		_frames = 0
		_frame_time = 0.0
		_worst_dt = 0.0
		_update_hud()
		_place_buttons()  # also catches leaving fullscreen with Esc / back


func _update_hud() -> void:
	var stats := GameStrings.text("hud.fps", {"fps": fps, "low": fps_low}) if fps > 0 else ""
	hud.text = build_text + ("   " + stats if stats != "" else "")
	if game != null and game.world != null:
		var where := GameStrings.text("hud.area", {"area": game.world.display_name, "spawn": Player.spawn()})
		hud.text += "   " + where
		if game.world.hunt != null:
			for m: Dictionary in game.world.hunt.mice:
				var spot: String = game.world.hunt.spots[m["spot"]]["id"]
				var st: String = {"feed": "down", "look": "UP", "flee": "fled"}.get(m["state"], m["state"])
				hud.text += "   " + GameStrings.text("hud.mouse", {"spot": spot, "state": st, "alert": roundi(float(m["alert"]) * 100.0)})
	_place_hud()
	if ScreenMetrics.is_web() and fps > 0:
		# Lets a browser test (or a curious tester's console) read frame stats.
		JavaScriptBridge.eval("window.catRpgStats = %s;" % JSON.stringify({
			"fps": fps, "low": fps_low, "build": build_text,
			"logic_ms": snappedf(logic_ms, 0.01),
			"fullscreen_button": fullscreen_button.visible,
			"fullscreen": ScreenMetrics.is_fullscreen(),
			"screen": "game" if game != null else "title",
			"view_scale": game.view_scale if game != null else 0,
			"touch_controls": game.touch.visible if game != null else false,
			"player": [game.world.player_pos.x, game.world.player_pos.y] if game != null else [],
			"dialogue": game.dialogue.visible_text() if game != null and game.dialogue.is_open else "",
			"speaker": str(game.dialogue.line.get("speaker", "")) if game != null and game.dialogue.is_open else "",
			"choices": game.dialogue.line.get("choices", []) if game != null and game.dialogue.choices_shown() else [],
			"voice_blips": game.voice.blips_played if game != null else 0,
			"flags": GameState.state.flags,
			"time_of_day": snappedf(game.day.t, 0.01) if game != null else 0.0,
			"phase": game.day.phase() if game != null else "afternoon",
			"music": game.sound.music_name if game != null and game.sound != null else "",
			"volume": volume_button.volume(),
			"background_pauses": AppFocus.pauses,
			"view_size": [game.view_size.x, game.view_size.y] if game != null else [],
			"bonds": GameState.state.bonds,
			"player_name": GameState.get_player_name(),
			"name_editor": game.name_editor.is_open if game != null else false,
			"name_shown": game.name_editor.shown_name() if game != null and game.name_editor.is_open else "",
			"area": Player.area(),
			"spawn": Player.spawn(),
			"hunger": Needs.hunger(),
			"thirst": Needs.thirst(),
			"travel": game.travel.phase if game != null else "",
			"collapses": Player.state.collapses,
			"goal": game.goal_label.text if game != null and game.goal_label.visible else "",
			"carried": Player.carried_item(),
			"crouching": game.world.crouching if game != null else false,
			"pile": int(game.world.pile.get("prey", -1)) if game != null and not game.world.pile.is_empty() else -1,
			"mice": game.world.hunt.mice.map(func(m): return {"id": m["id"], "state": m["state"], "alert": snappedf(m["alert"], 0.01), "pos": [m["pos"].x, m["pos"].y]}) if game != null and game.world.hunt != null else [],
		}), true)


func _place_hud() -> void:
	hud.visible = game == null or Settings.debug_overlay
	if metrics.ui_size == Vector2.ZERO:
		return
	var margin := 6.0
	hud.reset_size()
	hud.position = metrics.snap(metrics.safe_rect.position + Vector2(margin, margin * 0.5))
	# Debug buttons: just right of the centre at the top (the right half,
	# so a tap never grabs the joystick), clear of the needs bars and the
	# corner buttons, at least min_target tall.
	var show_debug := game != null and Settings.debug_overlay
	var tall := float(JsonData.load_dict("res://data/tuning.json").get("touch", {}).get("min_target", 48))
	var x := metrics.safe_rect.get_center().x + 8.0
	var w := tall * 2.0
	# Narrower buttons when four don't fit before the corner buttons.
	var room := metrics.safe_rect.end.x - 2.0 * tall - 24.0 - x
	if room < debug_buttons.size() * (w + 8.0):
		w = maxf(tall, room / debug_buttons.size() - 8.0)
	for b in debug_buttons:
		b.visible = show_debug and not (game.naming() if game != null else false)
		b.size = Vector2(w, tall)
		b.position = metrics.snap(Vector2(x, metrics.safe_rect.position.y + 12.0))
		x += w + 8.0

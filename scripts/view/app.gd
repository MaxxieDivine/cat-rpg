extends Control
## Main scene. Owns ScreenMetrics, swaps the title screen for the game, shows
## the rotate-your-phone overlay in portrait and the build / fps label.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const TitleScreen := preload("res://scripts/view/title.gd")
const GameScreen := preload("res://scripts/view/game.gd")
const RotateOverlay := preload("res://scripts/view/rotate_overlay.gd")
const FullscreenButton := preload("res://scripts/view/fullscreen_button.gd")
const BUILD_PATH := "res://data/build.json"

var metrics := ScreenMetrics.new()
var title: Control
var game: Control
var rotate: Control
var hud: Label
var fullscreen_button: Control
var build_text := ""
## Frame stats for the hud, refreshed twice a second.
var fps := 0
var fps_low := 0
## Average time all _process callbacks took per frame (ms), i.e. our own
## per-frame cost without rendering. If fps is low but this is small, the
## device is limited by rendering or the browser, not by game logic.
var logic_ms := 0.0

var _laying_out := false
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
	letterbox.color = Color("#2e4a33")
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
	build_text = read_build_text()
	_update_hud()

	var start := FrameStart.new()
	start.app = self
	start.process_priority = -100000
	add_child(start)
	process_priority = 100000  # app._process runs last: measures the frame's logic

	get_window().size_changed.connect(relayout)
	relayout()


func start_game() -> void:
	if game != null:
		return
	game = GameScreen.new()
	game.name = "Game"
	add_child(game)
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
	fullscreen_button.refresh()
	fullscreen_button.place(metrics.safe_rect, 4.0)
	_laying_out = false


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
		fullscreen_button.refresh()  # also catches leaving fullscreen with Esc / back


func _update_hud() -> void:
	var stats := GameStrings.text("hud.fps", {"fps": fps, "low": fps_low}) if fps > 0 else ""
	hud.text = build_text + ("   " + stats if stats != "" else "")
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
			"bonds": GameState.state.bonds,
		}), true)


func _place_hud() -> void:
	if metrics.ui_size == Vector2.ZERO:
		return
	var margin := 6.0
	hud.reset_size()
	hud.position = metrics.snap(metrics.safe_rect.position + Vector2(margin, margin * 0.5))

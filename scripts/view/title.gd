extends Control
## "Tap to start" title screen. Browsers block audio and fullscreen until the
## player taps or clicks, so the game starts here. A tap or click anywhere
## (or Enter / Space / E) requests fullscreen + landscape lock and starts the
## game. The corner fullscreen button lives in app.gd.

signal start_requested

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameInput := preload("res://scripts/view/game_input.gd")
const INK := Color(0.11, 0.094, 0.141)

var cat: Sprite2D
var cat_scale := 1
var title_label: Label
var start_label: Label
var controls_label: Label
## Shown where the browser can't go fullscreen (iPhone): how to get it anyway.
var home_label: Label
var metrics
var _t := 0.0
var _started := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameInput.ensure_actions()
	var bg := ColorRect.new()
	bg.color = Color("#6fb35a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	cat = Sprite2D.new()
	cat.texture = AssetCatalog.texture("cat.sheet")
	cat.hframes = 3
	cat.centered = false
	add_child(cat)

	title_label = _label(GameStrings.text("title.name"), 40, INK)
	var touch := ScreenMetrics.is_touch()
	start_label = _label(GameStrings.text("title.start_touch" if touch else "title.start_desktop"), 22, INK)
	controls_label = _label(GameStrings.text("title.controls_touch" if touch else "title.controls_desktop"), 13, Color(INK, 0.75))
	home_label = _label(GameStrings.text("title.add_to_home"), 13, Color(INK, 0.75))
	home_label.visible = ScreenMetrics.should_suggest_home_screen()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func layout(m) -> void:
	metrics = m
	var safe: Rect2 = m.safe_rect
	var safe_px: Rect2i = m.safe_rect_px()
	var frame := Vector2(24, 24)
	# Cat about a third of the safe height, whole device pixels.
	cat_scale = maxi(1, floori(safe_px.size.y * 0.3 / frame.y))
	cat.scale = Vector2(cat_scale, cat_scale) / m.px_per_unit
	var cat_ui := frame * cat.scale
	var block_h := cat_ui.y + 52.0 + 34.0 + 24.0 + (22.0 if home_label.visible else 0.0)
	var top := safe.position.y + maxf(8.0, (safe.size.y - block_h) / 2.0)
	var cat_px: Vector2 = m.ui_to_px(Vector2(safe.get_center().x - cat_ui.x / 2.0, top)).floor()
	cat.position = m.px_to_ui(cat_px)
	var y := cat.position.y + cat_ui.y + 4.0
	for l: Label in [title_label, start_label, controls_label, home_label]:
		l.size = Vector2(safe.size.x, 0)
		l.reset_size()
		l.size.x = safe.size.x
		l.position = Vector2(safe.position.x, y).round()
		y += l.get_combined_minimum_size().y + 6.0


func _process(dt: float) -> void:
	_t += dt
	start_label.modulate.a = 0.55 + 0.45 * absf(sin(_t * 2.5))
	cat.frame = 0 if fmod(_t, 3.0) < 2.4 else 1 + int(_t * 6.0) % 2


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_start_from_input()


func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		_start_from_input()


## Called from inside an input handler: the only moment browsers allow
## fullscreen and orientation lock.
func _start_from_input() -> void:
	if _started:
		return
	ScreenMetrics.request_fullscreen()
	_start()


func _start() -> void:
	if _started:
		return
	_started = true
	start_requested.emit()


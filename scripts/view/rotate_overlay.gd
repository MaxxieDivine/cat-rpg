extends Control
## Covers everything in portrait: the game is landscape only.

const GameStrings := preload("res://scripts/core/game_strings.gd")
const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")

var label: Label
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # swallow taps while shown
	label = Label.new()
	label.text = GameStrings.text("rotate.touch" if ScreenMetrics.is_touch() else "rotate.desktop")
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	visible = false


func layout(m) -> void:
	var safe: Rect2 = m.safe_rect
	label.size = Vector2(safe.size.x, 0)
	label.reset_size()
	label.size.x = safe.size.x
	label.position = Vector2(safe.position.x, safe.get_center().y + 60).round()
	queue_redraw()


func _process(dt: float) -> void:
	if visible:
		_t += dt
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.09))
	# A phone that tips over to landscape, then pauses.
	var c := size / 2.0 - Vector2(0, 20)
	var phase := fmod(_t, 2.4)
	var angle := clampf((phase - 0.6) / 0.8, 0.0, 1.0) * PI / 2.0
	draw_set_transform(c, -angle, Vector2.ONE)
	var r := Rect2(-24, -42, 48, 84)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	draw_circle(Vector2(0, 33), 3, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

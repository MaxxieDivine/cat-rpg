extends Control
## A speech bubble drawn at UI resolution (crisp text) with a tail pointing
## down at `anchor` (UI units). show_text() shows it for `seconds`.

const INK := Color(0.11, 0.094, 0.141)

var font_size := 18
var anchor := Vector2.ZERO
var gap := 6.0
var _text := ""
var _hide_at := -1.0
var _style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_style.bg_color = Color.WHITE
	_style.border_color = INK
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(8)
	_style.content_margin_left = 10
	_style.content_margin_right = 10
	_style.content_margin_top = 4
	_style.content_margin_bottom = 6


func text() -> String:
	return _text


func show_text(t: String, seconds: float) -> void:
	_text = t
	visible = true
	_hide_at = Time.get_ticks_msec() / 1000.0 + seconds if seconds > 0.0 else -1.0
	_relayout()


func hide_bubble() -> void:
	visible = false
	_hide_at = -1.0


## Point the tail at `p` (UI units), keeping the bubble inside `bounds`.
func point_at(p: Vector2, bounds: Rect2) -> void:
	anchor = p
	_relayout(bounds)


func _process(_dt: float) -> void:
	if _hide_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _hide_at:
		hide_bubble()


var _bounds := Rect2(-1e6, -1e6, 2e6, 2e6)


func _relayout(bounds: Rect2 = _bounds) -> void:
	_bounds = bounds
	var font := get_theme_default_font()
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Vector2(text_size.x + _style.content_margin_left + _style.content_margin_right,
		font.get_height(font_size) + _style.content_margin_top + _style.content_margin_bottom)
	size = box.ceil()
	var pos := Vector2(anchor.x - size.x / 2.0, anchor.y - gap - size.y)
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y))
	position = pos.round()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Tail, clamped under the box.
	var tip := anchor - position
	var tx := clampf(tip.x, 10.0, size.x - 10.0)
	var tail := PackedVector2Array([Vector2(tx - 6, size.y - 2), Vector2(tx + 6, size.y - 2), Vector2(tx, size.y + gap - 1)])
	draw_colored_polygon(tail, INK)
	draw_style_box(_style, r)
	var inner := PackedVector2Array([Vector2(tx - 3.5, size.y - 2), Vector2(tx + 3.5, size.y - 2), Vector2(tx, size.y + gap - 4)])
	draw_colored_polygon(inner, Color.WHITE)
	var font := get_theme_default_font()
	var baseline := _style.content_margin_top + font.get_ascent(font_size)
	draw_string(font, Vector2(_style.content_margin_left, baseline), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)

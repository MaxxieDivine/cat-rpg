extends Control
## Small corner button that enters fullscreen. Hidden while already fullscreen
## (or launched from the home screen), and where fullscreen can't work.
## The icon is small; the touch target is still min_target CSS px.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

## Touch target size in UI units (about CSS px).
var min_target := 48.0
var _down := false


func _init() -> void:
	name = "FullscreenButton"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(min_target, min_target)
	size = custom_minimum_size


func _ready() -> void:
	tooltip_text = GameStrings.text("ui.fullscreen")


## Shows or hides the button for the current fullscreen state.
func refresh() -> void:
	visible = ScreenMetrics.can_fullscreen() and not ScreenMetrics.is_fullscreen()


## Puts the button in the top-right corner of `safe` with `margin`.
func place(safe: Rect2, margin: float) -> void:
	size = Vector2(min_target, min_target)
	position = Vector2(safe.end.x - margin - size.x, safe.position.y + margin).round()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_down = mb.pressed
	queue_redraw()
	if mb.pressed:
		# Inside the click/tap handler, as browsers require.
		ScreenMetrics.request_fullscreen()
		refresh.call_deferred()


func _draw() -> void:
	var c := size / 2.0
	var r := 15.0
	draw_circle(c, r, Color(0, 0, 0, 0.45 if _down else 0.3))
	# Four corner brackets.
	var ink := Color(1, 1, 1, 0.9)
	var h := 6.0
	var l := 4.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx * h, sy * h)
			draw_line(corner, corner - Vector2(sx * l, 0), ink, 2.0)
			draw_line(corner, corner - Vector2(0, sy * l), ink, 2.0)

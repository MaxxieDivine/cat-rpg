extends Control
## Small corner button next to the fullscreen one: each tap / click steps
## the master volume through tuning.json "audio.volume_steps" (loud, half,
## muted, then loud again). The icon is a speaker with 2, 1 or 0 waves (a
## cross when muted). The touch target is still min_target CSS px.

const GameStrings := preload("res://scripts/core/game_strings.gd")

## Touch target size in UI units (about CSS px).
var min_target := 48.0
var steps: Array = [1.0, 0.5, 0.0]
## Index into steps.
var step := 0
var _down := false


func _init() -> void:
	name = "VolumeButton"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(min_target, min_target)
	size = custom_minimum_size


func _ready() -> void:
	tooltip_text = GameStrings.text("ui.volume")
	apply()


func configure(volume_steps: Array) -> void:
	if not volume_steps.is_empty():
		steps = volume_steps
	step = clampi(step, 0, steps.size() - 1)
	apply()


func volume() -> float:
	return float(steps[step])


func muted() -> bool:
	return volume() <= 0.0


## Sets the Master bus for the current step.
func apply() -> void:
	var v := volume()
	AudioServer.set_bus_mute(0, v <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	queue_redraw()


func cycle() -> void:
	step = (step + 1) % steps.size()
	apply()


## Puts the button at `pos` (top-left, UI units).
func place(pos: Vector2) -> void:
	size = Vector2(min_target, min_target)
	position = pos.round()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_down = mb.pressed
	if mb.pressed:
		cycle()
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, 15.0, Color(0, 0, 0, 0.45 if _down else 0.3))
	var ink := Color(1, 1, 1, 0.9)
	var o := c + Vector2(-5, 0)
	# Speaker: a box and a cone.
	draw_rect(Rect2(o + Vector2(-4, -3), Vector2(3, 6)), ink)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-1, -3), o + Vector2(4, -7), o + Vector2(4, 7), o + Vector2(-1, 3)]), ink)
	if muted():
		draw_line(o + Vector2(7, -4), o + Vector2(13, 4), ink, 2.0)
		draw_line(o + Vector2(7, 4), o + Vector2(13, -4), ink, 2.0)
		return
	var waves := 2 if volume() > 0.75 else 1
	for i in waves:
		var r := 6.0 + i * 4.0
		draw_arc(o + Vector2(3, 0), r, -0.8, 0.8, 10, ink, 2.0, true)

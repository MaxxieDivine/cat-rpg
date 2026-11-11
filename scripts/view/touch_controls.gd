extends Control
## On-screen controls for touch devices: a joystick for the left thumb and an
## interact (paw) button for the right. This is the only script that reads
## touch events. Mouse events are ignored here, so the browser's emulated
## mouse click for a touch never counts twice.
##
## The joystick base jumps to wherever the left thumb lands (anywhere in the
## left half), so the player doesn't have to find it. Pushing past
## `stick_trot` of the radius trots.

signal interact_pressed

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")

## Wanted direction, length 0..1 (deadzone already removed).
var stick_vector := Vector2.ZERO
## True while the stick is pushed far enough to trot.
var trot := false
## True when there is something to interact with (button lights up).
var highlight := false:
	set(v):
		if v != highlight:
			highlight = v
			queue_redraw()

var stick_radius := 56.0
var knob_radius := 24.0
var deadzone := 0.15
var trot_at := 0.85
var button_radius := 38.0
var edge_margin := 28.0
var min_target := 48.0

var stick_rest := Vector2.ZERO
var stick_base := Vector2.ZERO
var stick_knob := Vector2.ZERO
var button_center := Vector2.ZERO
var _stick_finger := -1
var _button_finger := -1
var _safe := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func configure(t: Dictionary) -> void:
	stick_radius = float(t.get("stick_radius", stick_radius))
	knob_radius = float(t.get("knob_radius", knob_radius))
	deadzone = float(t.get("stick_deadzone", deadzone))
	trot_at = float(t.get("stick_trot", trot_at))
	button_radius = float(t.get("button_radius", button_radius))
	edge_margin = float(t.get("edge_margin", edge_margin))
	min_target = float(t.get("min_target", min_target))


func layout(m) -> void:
	_safe = m.safe_rect
	stick_rest = Vector2(_safe.position.x + edge_margin + stick_radius, _safe.end.y - edge_margin - stick_radius)
	button_center = Vector2(_safe.end.x - edge_margin - button_radius, _safe.end.y - edge_margin - button_radius)
	if _stick_finger == -1:
		stick_base = stick_rest
		stick_knob = stick_rest
	queue_redraw()


## Bounding rect of the interact button (UI units).
func button_rect() -> Rect2:
	return Rect2(button_center - Vector2.ONE * button_radius, Vector2.ONE * button_radius * 2.0)


func stick_rect() -> Rect2:
	return Rect2(stick_base - Vector2.ONE * stick_radius, Vector2.ONE * stick_radius * 2.0)


## Releases everything (when hidden or paused).
func reset() -> void:
	_stick_finger = -1
	_button_finger = -1
	stick_vector = Vector2.ZERO
	trot = false
	stick_base = stick_rest
	stick_knob = stick_rest
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p := _local(event.position)
		if event.pressed:
			if _button_finger == -1 and _hits_button(p):
				_button_finger = event.index
				interact_pressed.emit()
				queue_redraw()
			elif _stick_finger == -1 and p.x < size.x * 0.5:
				_stick_finger = event.index
				stick_base = _clamp_base(p)
				_move_knob(p)
		else:
			if event.index == _stick_finger:
				_stick_finger = -1
				stick_vector = Vector2.ZERO
				trot = false
				stick_base = stick_rest
				stick_knob = stick_rest
				queue_redraw()
			if event.index == _button_finger:
				_button_finger = -1
				queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_finger:
		_move_knob(_local(event.position))


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _hits_button(p: Vector2) -> bool:
	var reach := maxf(button_radius, min_target / 2.0) + 10.0
	return p.distance_to(button_center) <= reach


## Keeps the whole stick on screen and clear of the edges.
func _clamp_base(p: Vector2) -> Vector2:
	var lo := _safe.position + Vector2.ONE * (edge_margin * 0.5 + stick_radius)
	var hi := _safe.end - Vector2.ONE * (edge_margin * 0.5 + stick_radius)
	return Vector2(clampf(p.x, lo.x, maxf(lo.x, hi.x)), clampf(p.y, lo.y, maxf(lo.y, hi.y)))


func _move_knob(p: Vector2) -> void:
	var off := p - stick_base
	var mag := minf(off.length() / stick_radius, 1.0)
	stick_knob = stick_base + off.limit_length(stick_radius)
	if mag < deadzone:
		stick_vector = Vector2.ZERO
	else:
		stick_vector = off.normalized() * ((mag - deadzone) / (1.0 - deadzone))
	trot = mag >= trot_at
	queue_redraw()


func _draw() -> void:
	# Joystick
	draw_circle(stick_base, stick_radius, Color(1, 1, 1, 0.14))
	draw_arc(stick_base, stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0, true)
	if trot:
		draw_arc(stick_base, stick_radius * trot_at, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.5, true)
	draw_circle(stick_knob, knob_radius, Color(1, 1, 1, 0.55 if _stick_finger != -1 else 0.4))
	# Interact button with a paw print
	var pressed := _button_finger != -1
	var fill := Color(1, 0.86, 0.45, 0.85) if highlight else Color(1, 1, 1, 0.3)
	if pressed:
		fill = fill.darkened(0.25)
	draw_circle(button_center, button_radius, fill)
	draw_arc(button_center, button_radius, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0, true)
	var ink := Color(0.11, 0.094, 0.141, 0.85 if highlight else 0.55)
	var s := button_radius / 38.0
	var c := button_center + Vector2(0, 5) * s
	draw_circle(c + Vector2(0, 4) * s, 10 * s, ink)
	for toe in [Vector2(-13, -8), Vector2(-5, -16), Vector2(5, -16), Vector2(13, -8)]:
		draw_circle(c + toe * s, 4.5 * s, ink)

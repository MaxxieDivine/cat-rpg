extends Control
## On-screen controls for touch devices: a joystick for the left thumb and an
## interact (paw) button for the right. This is the only script that reads
## touch events. Mouse events are ignored here, so the browser's emulated
## mouse click for a touch never counts twice.
##
## The joystick base jumps to wherever the left thumb lands (anywhere in the
## left half), so the player doesn't have to find it. Pushing past
## `stick_trot` of the radius trots.
##
## Hunting (`hunt_buttons`, in an area with mice): a big Crouch button left
## of the paw toggles `crouch_on`; a Pounce button above the paw is dimmed
## until `can_pounce`. While Fern carries prey (`carrying`) that slot is an
## Eat button instead (shown in every area).

signal interact_pressed
signal pounce_pressed
signal eat_pressed
signal crouch_toggled(on: bool)

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

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
var crouch_radius := 34.0
var pounce_radius := 32.0
var button_gap := 14.0
## Crouch / Pounce shown (an area with mice).
var hunt_buttons := false:
	set(v):
		if v != hunt_buttons:
			hunt_buttons = v
			if not v:
				crouch_on = false
			queue_redraw()
## The Crouch toggle is on.
var crouch_on := false:
	set(v):
		if v != crouch_on:
			crouch_on = v
			queue_redraw()
## A mouse is in pounce range (the Pounce button lights up).
var can_pounce := false:
	set(v):
		if v != can_pounce:
			can_pounce = v
			queue_redraw()
## Fern carries prey: the Pounce slot becomes Eat.
var carrying := false:
	set(v):
		if v != carrying:
			carrying = v
			queue_redraw()
var crouch_center := Vector2.ZERO
var pounce_center := Vector2.ZERO
## Which finger holds which extra button ("crouch", "pounce", "eat").
var _held: Dictionary = {}

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
	crouch_radius = maxf(float(t.get("crouch_radius", crouch_radius)), min_target / 2.0)
	pounce_radius = maxf(float(t.get("pounce_radius", pounce_radius)), min_target / 2.0)
	button_gap = float(t.get("button_gap", button_gap))


func layout(m) -> void:
	_safe = m.safe_rect
	stick_rest = Vector2(_safe.position.x + edge_margin + stick_radius, _safe.end.y - edge_margin - stick_radius)
	button_center = Vector2(_safe.end.x - edge_margin - button_radius, _safe.end.y - edge_margin - button_radius)
	crouch_center = button_center - Vector2(button_radius + button_gap + crouch_radius, 0)
	pounce_center = button_center - Vector2(0, button_radius + button_gap + pounce_radius)
	if _stick_finger == -1:
		stick_base = stick_rest
		stick_knob = stick_rest
	queue_redraw()


## Bounding rect of the interact button (UI units).
func button_rect() -> Rect2:
	return Rect2(button_center - Vector2.ONE * button_radius, Vector2.ONE * button_radius * 2.0)


func crouch_rect() -> Rect2:
	return Rect2(crouch_center - Vector2.ONE * crouch_radius, Vector2.ONE * crouch_radius * 2.0)


## The Pounce / Eat slot.
func pounce_rect() -> Rect2:
	return Rect2(pounce_center - Vector2.ONE * pounce_radius, Vector2.ONE * pounce_radius * 2.0)


## Pounce shown (in an area with mice, carrying nothing).
func pounce_shown() -> bool:
	return hunt_buttons and not carrying


func eat_shown() -> bool:
	return carrying


func stick_rect() -> Rect2:
	return Rect2(stick_base - Vector2.ONE * stick_radius, Vector2.ONE * stick_radius * 2.0)


## Releases everything (when hidden or paused).
func reset() -> void:
	_stick_finger = -1
	_button_finger = -1
	_held.clear()
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
			var extra := _extra_at(p)
			if extra != "" and not _held.values().has(extra):
				_held[event.index] = extra
				match extra:
					"crouch":
						crouch_on = not crouch_on
						crouch_toggled.emit(crouch_on)
					"pounce":
						pounce_pressed.emit()
					"eat":
						eat_pressed.emit()
				queue_redraw()
			elif _button_finger == -1 and _hits_button(p):
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
			if _held.has(event.index):
				_held.erase(event.index)
				queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_finger:
		_move_knob(_local(event.position))


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


## Which extra button a touch at `p` lands on ("" for none). A little slack
## round each, but never into the paw button.
func _extra_at(p: Vector2) -> String:
	if _hits_button_core(p):
		return ""
	if hunt_buttons and p.distance_to(crouch_center) <= crouch_radius + 8.0:
		return "crouch"
	if p.distance_to(pounce_center) <= pounce_radius + 8.0:
		if eat_shown():
			return "eat"
		if pounce_shown():
			return "pounce"
	return ""


func _hits_button_core(p: Vector2) -> bool:
	return p.distance_to(button_center) <= button_radius


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
	if hunt_buttons:
		_draw_button(crouch_center, crouch_radius, GameStrings.text("ui.crouch"), crouch_on, _held.values().has("crouch"), true)
	if eat_shown():
		_draw_button(pounce_center, pounce_radius, GameStrings.text("ui.eat"), true, _held.values().has("eat"), false)
	elif pounce_shown():
		_draw_button(pounce_center, pounce_radius, GameStrings.text("ui.pounce"), can_pounce, _held.values().has("pounce"), false, not can_pounce)


## A round labelled button: lit (warm yellow) when on / usable, dimmed
## (faint) when it can't be used yet.
func _draw_button(ctr: Vector2, r: float, label: String, lit: bool, pressed: bool, toggle: bool, dim: bool = false) -> void:
	var fill := Color(1, 0.86, 0.45, 0.85) if lit else Color(1, 1, 1, 0.3)
	if dim:
		fill = Color(1, 1, 1, 0.14)
	if pressed:
		fill = fill.darkened(0.25)
	draw_circle(ctr, r, fill)
	draw_arc(ctr, r, 0, TAU, 48, Color(1, 1, 1, 0.3 if dim else 0.6), 2.0, true)
	if toggle and lit:
		draw_arc(ctr, r - 5.0, 0, TAU, 48, Color(0.11, 0.094, 0.141, 0.5), 2.0, true)
	var font := get_theme_default_font()
	var size := 13
	var ink := Color(0.11, 0.094, 0.141, 0.9 if lit else (0.35 if dim else 0.6))
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, ctr + Vector2(-w / 2.0, size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

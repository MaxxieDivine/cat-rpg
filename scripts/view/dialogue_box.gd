extends Control
## The dialogue box: bottom of the screen, about 40% of its height (tuning
## "dialogue.box_height"), inside the safe area. A name plate and a plain
## coloured square portrait (with a tiny face for the expression) sit on the
## speaker's side: Fern on the right, everyone else on the left. Text types
## out (scripts/core/typewriter.gd) with voice blips; a blinking arrow shows
## when the line is done. Choices appear as rows above the box, on Fern's
## side, each at least `min_choice_css` CSS px tall.
##
## Input: game.gd forwards Interact (finish the line, then advance / pick)
## and up/down (move the choice). Taps and clicks are read here: a tap
## anywhere advances; with choices up, tapping a row picks it. Touch comes as
## InputEventScreenTouch; mouse clicks only count when they are real (not the
## browser's emulated mouse for a touch), so a tap never counts twice.
## The box only shows lines; DialogueManager runs the conversation.

signal advance_requested
signal choice_made(index: int)

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const Typewriter := preload("res://scripts/core/typewriter.gd")
const INK := Color(0.11, 0.094, 0.141)
const PAPER := Color("#f6eedb")
const SELECT := Color("#ffd873")
const BORDER := 3.0

var t: Dictionary = {}
var speakers: Dictionary = {}
## voice.gd node, or null (no sound).
var voice: Node
var typewriter := Typewriter.new()
## The line on screen (a DialogueManager "line" event).
var line: Dictionary = {}
var is_open := false
var selected := 0
## Highlight the selected choice (keyboard / gamepad players). Touch
## players just tap.
var show_selection := true
var metrics
var font: Font
var font_size := 18

## Layout, UI units.
var box_rect := Rect2()
var portrait_rect := Rect2()
var plate_rect := Rect2()
var text_rect := Rect2()
var choice_rects: Array[Rect2] = []
var choice_row_h := 44.0

var text_label: Label
var name_label: Label
var choice_labels: Array[Label] = []

var _pad := 12.0
var _plate_h := 24.0
var _blink := 0.0
var _opened_frame := -1
var _pressed_choice := -1
var _box_style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box_style.bg_color = PAPER
	_box_style.border_color = INK
	_box_style.set_border_width_all(int(BORDER))
	_box_style.set_corner_radius_all(6)


func configure(tuning: Dictionary, speaker_data: Dictionary, voice_node: Node) -> void:
	t = tuning
	speakers = speaker_data
	voice = voice_node
	typewriter.configure(t)
	var base := AssetCatalog.font("font.dialogue")
	if base == null:
		base = get_theme_default_font()
	# No ligatures: Pixelify Sans' "fi" ligature reads as an "A" ("Arst").
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
	font = fv
	text_label = _label("Text")
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrap the whole line up front so words don't jump lines while typing.
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label = _label("Name")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for i in 3:
		var l := _label("Choice%d" % i)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choice_labels.append(l)


func _label(n: String) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", INK)
	add_child(l)
	return l


func layout(m) -> void:
	metrics = m
	var safe: Rect2 = m.safe_rect
	var margin := float(t.get("margin", 8))
	_pad = float(t.get("padding", 12))
	var box_h := roundf(m.ui_size.y * float(t.get("box_height", 0.4)))
	font_size = clampi(roundi(box_h * float(t.get("font_size_of_box", 0.13))), int(t.get("font_size_min", 14)), int(t.get("font_size_max", 28)))
	_plate_h = roundf(font_size * 1.5)
	box_h = minf(box_h, safe.size.y - margin * 2.0 - _plate_h)
	box_rect = Rect2(Vector2(safe.position.x + margin, safe.end.y - margin - box_h).round(),
		Vector2(safe.size.x - margin * 2.0, box_h).round())
	# 44 CSS px in UI units.
	var min_row := float(t.get("min_choice_css", 44)) * float(m.dpr) / float(m.px_per_unit.y)
	choice_row_h = ceilf(maxf(min_row, font_size * 1.8))
	for l: Label in [text_label, name_label] + choice_labels:
		l.add_theme_font_size_override("font_size", font_size)
	_relayout()


## Shows a line (a "line" event) and starts typing it.
func show_line(ev: Dictionary) -> void:
	line = ev
	is_open = true
	visible = true
	selected = 0
	_pressed_choice = -1
	_blink = 0.0
	_opened_frame = Engine.get_process_frames()
	typewriter.start(str(ev.get("text", "")))
	text_label.text = typewriter.text
	text_label.visible_characters = 0
	var sp := speaker()
	name_label.text = str(sp.get("name", ev.get("speaker", "")))
	var col := speaker_color()
	name_label.add_theme_color_override("font_color", _ink_on(col))
	_relayout()


func close() -> void:
	is_open = false
	visible = false
	line = {}
	_pressed_choice = -1


func speaker() -> Dictionary:
	return speakers.get(str(line.get("speaker", "")), {})


func speaker_color() -> Color:
	return Color(str(speaker().get("color", "#808080")))


func on_right() -> bool:
	return str(speaker().get("side", "left")) == "right"


func is_typing() -> bool:
	return is_open and not typewriter.is_done()


## True when choices are on screen (they wait until the line has typed out).
func choices_shown() -> bool:
	return is_open and not is_typing() and not (line.get("choices", []) as Array).is_empty()


## The text shown so far.
func visible_text() -> String:
	return typewriter.text.substr(0, typewriter.shown)


## Interact: finish the line, else pick the selected choice, else advance.
func press() -> void:
	if not is_open:
		return
	if is_typing():
		typewriter.finish()
		_sync_text()
	elif choices_shown():
		choice_made.emit(selected)
	else:
		advance_requested.emit()


func move_selection(delta: int) -> void:
	if not choices_shown():
		return
	var n: int = line["choices"].size()
	selected = posmod(selected + delta, n)
	show_selection = true
	queue_redraw()


func _process(dt: float) -> void:
	if not is_open:
		return
	var was_typing := is_typing()
	var blips: int = typewriter.step(dt)
	if voice != null:
		for i in blips:
			voice.blip(speaker().get("voice", {}))
	_sync_text()
	_blink += dt
	if was_typing or choices_shown() or not is_typing():
		queue_redraw()


func _sync_text() -> void:
	text_label.visible_characters = typewriter.shown
	var shown := choices_shown()
	var texts: Array = line.get("choices", [])
	for i in choice_labels.size():
		var l := choice_labels[i]
		l.visible = shown and i < texts.size()
		if l.visible:
			l.text = str(texts[i])


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var touch := event as InputEventScreenTouch
	var mb := event as InputEventMouseButton
	var down := false
	var up := false
	var pos := Vector2.ZERO
	if touch != null:
		down = touch.pressed
		up = not touch.pressed
		pos = touch.position
	elif mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != InputEvent.DEVICE_ID_EMULATION:
		down = mb.pressed
		up = not mb.pressed
		pos = mb.position
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and choices_shown():
		var hover := _choice_at(_local(event.position))
		if hover >= 0 and hover != selected:
			selected = hover
			queue_redraw()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	if Engine.get_process_frames() == _opened_frame:
		return  # the tap that opened the box
	var p := _local(pos)
	if down:
		if choices_shown():
			_pressed_choice = _choice_at(p)
			if _pressed_choice >= 0:
				selected = _pressed_choice
				queue_redraw()
		else:
			press()
	elif up and _pressed_choice >= 0:
		var i := _pressed_choice
		_pressed_choice = -1
		if _choice_at(p) == i and choices_shown():
			choice_made.emit(i)


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if i < (line.get("choices", []) as Array).size() and choice_rects[i].has_point(p):
			return i
	return -1


func _relayout() -> void:
	if metrics == null:
		return
	var right := on_right()
	var b := box_rect
	var side := clampf(b.size.y - _pad * 2.0, 0.0, float(t.get("portrait_max", 180)))
	portrait_rect = Rect2(Vector2(b.end.x - _pad - side if right else b.position.x + _pad, b.position.y + _pad), Vector2(side, side))
	var tx0 := b.position.x + _pad if right else portrait_rect.end.x + _pad
	var tx1 := portrait_rect.position.x - _pad if right else b.end.x - _pad
	text_rect = Rect2(tx0, b.position.y + _pad, maxf(0.0, tx1 - tx0), maxf(0.0, b.size.y - _pad * 2.0))
	text_label.position = text_rect.position
	text_label.size = text_rect.size

	var name_w := font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var plate_w := ceilf(name_w + _pad * 2.0)
	var plate_x := b.end.x - _pad - plate_w if right else b.position.x + _pad
	plate_rect = Rect2(plate_x, b.position.y - _plate_h + BORDER, plate_w, _plate_h)
	name_label.position = plate_rect.position
	name_label.size = plate_rect.size

	# Choices: rows stacked upwards from the box, right-aligned (Fern's side).
	var texts: Array = line.get("choices", [])
	choice_rects = []
	var gap := float(t.get("choice_gap", 6))
	var widest := 0.0
	for c in texts:
		widest = maxf(widest, font.get_string_size(str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var marker := font_size * 1.2
	var w := clampf(ceilf(widest + marker + _pad * 2.0), b.size.x * 0.35, b.size.x * 0.75)
	var bottom := b.position.y - gap
	if right:
		bottom = plate_rect.position.y - gap
	var top_limit: float = metrics.safe_rect.position.y + float(t.get("top_reserved", 56))
	var n := texts.size()
	var total := n * choice_row_h + maxf(0.0, n - 1) * gap
	if bottom - total < top_limit:
		bottom = minf(top_limit + total, b.end.y - _pad)
	for i in n:
		var y := bottom - (n - i) * choice_row_h - (n - 1 - i) * gap
		choice_rects.append(Rect2(Vector2(b.end.x - w, y).round(), Vector2(w, choice_row_h).round()))
	for i in choice_labels.size():
		if i < choice_rects.size():
			var r := choice_rects[i]
			choice_labels[i].position = r.position + Vector2(_pad + marker, 0)
			choice_labels[i].size = Vector2(r.size.x - _pad * 2.0 - marker, r.size.y)
	_sync_text()
	queue_redraw()


func _draw() -> void:
	if not is_open:
		return
	var col := speaker_color()
	# Name plate (behind the box's top border), box, portrait.
	var plate := StyleBoxFlat.new()
	plate.bg_color = col
	plate.border_color = INK
	plate.set_border_width_all(int(BORDER))
	plate.corner_radius_top_left = 6
	plate.corner_radius_top_right = 6
	draw_style_box(plate, plate_rect)
	draw_style_box(_box_style, box_rect)
	draw_rect(portrait_rect, col)
	draw_rect(portrait_rect, INK, false, BORDER)
	_draw_face(portrait_rect, str(line.get("expression", "neutral")), _ink_on(col))
	# "Line done" arrow, blinking.
	if not is_typing() and not choices_shown() and fmod(_blink, float(t.get("arrow_blink", 0.5)) * 2.0) < float(t.get("arrow_blink", 0.5)):
		var s := maxf(6.0, font_size * 0.4)
		var tip := Vector2(text_rect.end.x - s, text_rect.end.y - s * 0.4)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-s, -s), tip + Vector2(s, -s), tip]), INK)
	# Choice rows.
	if choices_shown():
		for i in choice_rects.size():
			var r := choice_rects[i]
			var on := show_selection and i == selected
			var st := StyleBoxFlat.new()
			st.bg_color = SELECT if on else PAPER
			st.border_color = INK
			st.set_border_width_all(int(BORDER))
			st.set_corner_radius_all(6)
			draw_style_box(st, r)
			if on:
				var s := font_size * 0.35
				var c := Vector2(r.position.x + _pad + s, r.get_center().y)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, 0), c + Vector2(-s, s)]), INK)


## A tiny placeholder face, so expressions are visible before real portraits.
func _draw_face(r: Rect2, expression: String, ink: Color) -> void:
	var s := r.size.x
	var w := maxf(2.0, roundf(s * 0.05))
	var le := r.position + Vector2(s * 0.32, s * 0.45)
	var re := r.position + Vector2(s * 0.68, s * 0.45)
	var mouth := r.position + Vector2(s * 0.5, s * 0.7)
	var e := s * 0.07
	match expression:
		"happy":
			for c in [le, re]:
				draw_polyline(PackedVector2Array([c + Vector2(-e, e * 0.5), c + Vector2(0, -e * 0.5), c + Vector2(e, e * 0.5)]), ink, w)
			draw_polyline(PackedVector2Array([mouth + Vector2(-e * 2, -e * 0.5), mouth + Vector2(0, e * 0.8), mouth + Vector2(e * 2, -e * 0.5)]), ink, w)
		"sad":
			for c in [le, re]:
				draw_rect(Rect2(c - Vector2(w, w) * 0.75, Vector2(w, w) * 1.5), ink)
			draw_line(le + Vector2(-e * 1.4, -e * 0.8), le + Vector2(e * 0.8, -e * 1.8), ink, w)
			draw_line(re + Vector2(e * 1.4, -e * 0.8), re + Vector2(-e * 0.8, -e * 1.8), ink, w)
			draw_polyline(PackedVector2Array([mouth + Vector2(-e * 2, e * 0.6), mouth + Vector2(0, -e * 0.6), mouth + Vector2(e * 2, e * 0.6)]), ink, w)
		"annoyed":
			for c in [le, re]:
				draw_line(c + Vector2(-e, 0), c + Vector2(e, 0), ink, w)
			draw_line(le + Vector2(-e * 1.4, -e * 1.8), le + Vector2(e * 1.2, -e * 0.9), ink, w)
			draw_line(re + Vector2(e * 1.4, -e * 1.8), re + Vector2(-e * 1.2, -e * 0.9), ink, w)
			draw_line(mouth + Vector2(-e * 1.4, 0), mouth + Vector2(e * 1.4, 0), ink, w)
		_:
			for c in [le, re]:
				draw_rect(Rect2(c - Vector2(w, w) * 0.75, Vector2(w, w) * 1.5), ink)
			draw_line(mouth + Vector2(-e * 1.6, 0), mouth + Vector2(e * 1.6, 0), ink, w)


## Dark ink on light colours, light ink on dark ones.
static func _ink_on(c: Color) -> Color:
	return INK if c.get_luminance() > 0.45 else PAPER

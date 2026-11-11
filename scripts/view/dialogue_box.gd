extends Control
## The dialogue box, drawn at the world's pixel scale: everything (box,
## text, portrait, choices) is laid out in world pixels inside its own
## transparent SubViewport the size of the world view, which is shown at the
## same whole-number scale k as the world. So one font pixel is one world
## pixel is k x k device pixels, and nothing is ever blurry.
##
## Layout (tuning.json "dialogue", in world px): a box along the bottom of
## the safe area, `lines` lines of `font_px` Pixelify Sans tall (never more
## than `max_height` of the screen), a `portrait_px` square portrait (a plain
## colour with a tiny pixel face for the expression) and a name plate on the
## speaker's side: Fern on the right, everyone else on the left. Text types
## out (scripts/core/typewriter.gd) with voice blips; a blinking arrow shows
## when the line is done. Choices are a compact stack just above the box on
## the right, each only as wide as its text, with a cursor on the selected
## one; on touch screens they are `touch_choice_css` CSS px tall for thumbs.
## The box slides and fades in and out over `anim_s` seconds.
##
## Input: game.gd forwards Interact (finish the line, then advance / pick)
## and up/down (move the choice). Taps and clicks are read here: a tap
## anywhere advances; with choices up, tapping a row picks it. Touch comes as
## InputEventScreenTouch; mouse clicks only count when they are real (not the
## browser's emulated mouse for a touch), so a tap never counts twice.
## The box only shows lines; DialogueManager runs the conversation.
## The rects below are in UI units (for input, tests and the camera); the
## _bp_* ones are the same in box pixels (= world pixels).

signal advance_requested
signal choice_made(index: int)
## "open", "move", "confirm", "advance": for UI sounds.
signal ui_event(kind: String)

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const Typewriter := preload("res://scripts/core/typewriter.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const PALETTE_PATH := "res://data/palette.json"
static var INK := Color("#1c1824")
static var PAPER := Color("#f6eedb")
static var SELECT := Color("#ffd873")
## Border width in box pixels.
const BORDER := 1

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
## Touch layout: taller choice rows.
var touch_rows := false
var metrics
var font: Font
var font_size := 12

## Layout, UI units.
var box_rect := Rect2()
var portrait_rect := Rect2()
var plate_rect := Rect2()
var text_rect := Rect2()
var choice_rects: Array[Rect2] = []
## UI units per box pixel (k / px_per_unit).
var unit := 1.0
## Device pixels per box pixel (the world's k).
var k := 1

var viewport: SubViewport
var canvas: Node2D
var view: Sprite2D
var text_label: Label
var name_label: Label
var choice_labels: Array[Label] = []

## Layout, box pixels.
var _bp_box := Rect2i()
var _bp_portrait := Rect2i()
var _bp_plate := Rect2i()
var _bp_text := Rect2i()
var _bp_choices: Array[Rect2i] = []
var _bp_safe := Rect2i()
var _view_rect := Rect2()
var _blink := 0.0
var _opened_frame := -1
var _pressed_choice := -1
## 0 = hidden, 1 = fully shown; eases towards `is_open`.
var _anim := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func configure(tuning: Dictionary, speaker_data: Dictionary, voice_node: Node) -> void:
	t = tuning
	speakers = speaker_data
	voice = voice_node
	typewriter.configure(t)
	var ui: Dictionary = JsonData.load_dict(PALETTE_PATH).get("ui", {})
	INK = Color(str(ui.get("ink", INK.to_html())))
	PAPER = Color(str(ui.get("paper", PAPER.to_html())))
	SELECT = Color(str(ui.get("select", SELECT.to_html())))
	font_size = int(t.get("font_px", 12))
	var base := AssetCatalog.font("font.dialogue")
	if base == null:
		base = get_theme_default_font()
	if base is FontFile:
		# Pixel-exact: no smoothing, rasterised at its own size (the box's
		# SubViewport is scaled up by k afterwards).
		var ff := base as FontFile
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.oversampling = 1.0
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	# No ligatures: Pixelify Sans' "fi" ligature reads as an "A" ("Arst").
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
	font = fv

	viewport = SubViewport.new()
	viewport.name = "BoxViewport"
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	canvas = Node2D.new()
	canvas.name = "Canvas"
	canvas.draw.connect(_draw_box)
	viewport.add_child(canvas)
	view = Sprite2D.new()
	view.name = "View"
	view.centered = false
	view.texture = viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)

	text_label = _label("Text")
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrap the whole line up front so words don't jump lines while typing.
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.add_theme_constant_override("line_spacing", int(t.get("line_px", 13)) - _font_height())
	name_label = _label("Name")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 3:
		var l := _label("Choice%d" % i)
		choice_labels.append(l)


func _label(n: String) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", INK)
	viewport.add_child(l)
	return l


func _font_height() -> int:
	return int(font.get_height(font_size))


## Lays the box out over the world view: `view_rect` (UI units) shows
## `view_size` world pixels at `scale` device pixels each.
func layout(m, view_rect: Rect2 = Rect2(), view_size: Vector2i = Vector2i.ZERO, scale: int = 0) -> void:
	metrics = m
	if scale <= 0:
		# No world view (tests of the box alone): box pixels = 2 device px.
		scale = 2
		view_size = Vector2i((Vector2(m.px_size) / scale).ceil())
		view_rect = Rect2(Vector2.ZERO, m.px_to_ui(Vector2(view_size) * scale))
	k = scale
	_view_rect = view_rect
	unit = float(k) / float(m.px_per_unit.y)
	viewport.size = view_size
	view.position = view_rect.position
	view.scale = Vector2(k, k) / m.px_per_unit
	# Safe area in box pixels, shrunk to whole pixels.
	var s0: Vector2 = ((m.safe_rect.position - view_rect.position) / unit).ceil()
	var s1: Vector2 = ((m.safe_rect.end - view_rect.position) / unit).floor()
	s0 = s0.max(Vector2.ZERO)
	s1 = s1.min(Vector2(view_size))
	_bp_safe = Rect2i(Vector2i(s0), Vector2i(s1 - s0))
	_relayout()


## Box pixels -> UI units.
func _ui(r: Rect2i) -> Rect2:
	return Rect2(_view_rect.position + Vector2(r.position) * unit, Vector2(r.size) * unit)


## Shows a line (a "line" event) and starts typing it.
func show_line(ev: Dictionary) -> void:
	var was_open := is_open
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
	name_label.add_theme_color_override("font_color", _ink_on(speaker_color()))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not was_open:
		ui_event.emit("open")
	_relayout()


func close() -> void:
	is_open = false
	_pressed_choice = -1


## True while the open / close slide is still running.
func animating() -> bool:
	return _anim != (1.0 if is_open else 0.0)


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
		ui_event.emit("confirm")
		choice_made.emit(selected)
	else:
		ui_event.emit("advance")
		advance_requested.emit()


func move_selection(delta: int) -> void:
	if not choices_shown():
		return
	var n: int = line["choices"].size()
	selected = posmod(selected + delta, n)
	show_selection = true
	ui_event.emit("move")
	canvas.queue_redraw()


func _process(dt: float) -> void:
	var target := 1.0 if is_open else 0.0
	if _anim != target:
		var step := dt / maxf(0.001, float(t.get("anim_s", 0.15)))
		_anim = move_toward(_anim, target, step)
		_place_view()
		if _anim == 0.0 and not is_open:
			visible = false
			line = {}
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
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
		canvas.queue_redraw()


## Slide (whole box pixels, so k x k device pixels) and fade.
func _place_view() -> void:
	var e := ease(_anim, 0.5)
	var slide := roundf((1.0 - e) * float(t.get("anim_slide_px", 6)))
	view.position = _view_rect.position + Vector2(0, slide * unit)
	view.modulate.a = e


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
			ui_event.emit("move")
			canvas.queue_redraw()
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
				canvas.queue_redraw()
		else:
			press()
	elif up and _pressed_choice >= 0:
		var i := _pressed_choice
		_pressed_choice = -1
		if _choice_at(p) == i and choices_shown():
			ui_event.emit("confirm")
			choice_made.emit(i)


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if i < (line.get("choices", []) as Array).size() and choice_rects[i].has_point(p):
			return i
	return -1


## Height of a label holding `lines` lines (box pixels).
func text_height() -> int:
	var lines := int(t.get("lines", 3))
	return lines * _font_height() + (lines - 1) * (int(t.get("line_px", 13)) - _font_height())


## Height of the box for `lines` lines of text (box pixels). The font's
## blank rows above the capitals and below the descenders ("text_trim_px")
## may overlap the padding.
func box_height() -> int:
	var inner := maxi(text_height() - int(t.get("text_trim_px", 4)), int(t.get("portrait_px", 32)))
	return inner + int(t.get("padding_px", 4)) * 2 + BORDER * 2


func _relayout() -> void:
	if metrics == null:
		return
	var right := on_right()
	var margin := int(t.get("margin_px", 4))
	var pad := int(t.get("padding_px", 4))
	var safe := _bp_safe
	var h := box_height()
	var w := safe.size.x - margin * 2
	var bottom_margin := int(t.get("bottom_margin_px", margin))
	_bp_box = Rect2i(safe.position.x + margin, safe.end.y - bottom_margin - h, w, h)
	var b := _bp_box
	var side := int(t.get("portrait_px", 32))
	var inner_y := b.position.y + BORDER + pad
	_bp_portrait = Rect2i(b.end.x - BORDER - pad - side if right else b.position.x + BORDER + pad, inner_y, side, side)
	var tx0 := b.position.x + BORDER + pad if right else _bp_portrait.end.x + pad
	var tx1 := _bp_portrait.position.x - pad if right else b.end.x - BORDER - pad
	var trim_top := int(t.get("text_trim_px", 4)) * 3 / 4
	_bp_text = Rect2i(tx0, inner_y - trim_top, maxi(0, tx1 - tx0), text_height())
	text_label.position = _bp_text.position
	text_label.size = _bp_text.size

	var fh := _font_height()
	var name_w := int(font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var plate_h := int(t.get("plate_px", 12))
	var plate_w := name_w + pad * 2 + BORDER * 2
	var plate_x := b.end.x - pad - plate_w if right else b.position.x + pad
	_bp_plate = Rect2i(plate_x, b.position.y - plate_h + BORDER, plate_w, plate_h)
	# Capitals start ~3 px below the label's top (Pixelify's ascent).
	name_label.position = Vector2(_bp_plate.position.x + BORDER, _bp_plate.position.y + BORDER + 1 - (fh - int(t.get("text_trim_px", 4)) - 9) / 2 - 3)
	name_label.size = Vector2(_bp_plate.size.x - BORDER * 2, fh)

	# Choices: rows only as wide as their text, stacked up from the box's
	# top right, above the name plate when that is on the right too.
	var texts: Array = line.get("choices", [])
	var cpad := int(t.get("choice_pad_px", 4))
	var gap := int(t.get("choice_gap_px", 2))
	var cursor := 6
	var row_h := fh - 2 + BORDER * 2
	if touch_rows:
		var css := clampf(float(t.get("touch_choice_css", 38)), float(t.get("min_choice_css", 36)), float(t.get("max_choice_css", 40)))
		row_h = maxi(row_h, ceili(css * float(metrics.dpr) / float(k)))
	var bottom := (_bp_plate.position.y if right else b.position.y) - gap
	var top_limit := safe.position.y + int(t.get("top_reserved_px", 20))
	var n := texts.size()
	var total := n * row_h + maxi(0, n - 1) * gap
	if bottom - total < top_limit:
		bottom = top_limit + total
	_bp_choices = []
	for i in n:
		var tw := int(font.get_string_size(str(texts[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		# +2: Labels draw a pixel or two wider than get_string_size says.
		var cw := mini(tw + 2 + cpad * 2 + cursor + BORDER * 2, w)
		var y := bottom - (n - i) * row_h - (n - 1 - i) * gap
		_bp_choices.append(Rect2i(b.end.x - cw, y, cw, row_h))
	for i in choice_labels.size():
		if i < _bp_choices.size():
			var r := _bp_choices[i]
			choice_labels[i].position = Vector2(r.position.x + BORDER + cpad + cursor, r.position.y + (row_h - fh) / 2 + 1)
			choice_labels[i].size = Vector2(r.size.x - BORDER * 2 - cpad * 2 - cursor + 2, fh)

	box_rect = _ui(_bp_box)
	portrait_rect = _ui(_bp_portrait)
	plate_rect = _ui(_bp_plate)
	text_rect = _ui(_bp_text)
	choice_rects = []
	for r in _bp_choices:
		choice_rects.append(_ui(r))
	_place_view()
	_sync_text()
	canvas.queue_redraw()


func _draw_box() -> void:
	if line.is_empty():
		return
	var col := speaker_color()
	_panel(_bp_plate, col)
	_panel(_bp_box, PAPER)
	# Square plate corners into the box: the plate sits on its top border.
	canvas.draw_rect(Rect2(_bp_plate.position.x + BORDER, _bp_box.position.y, _bp_plate.size.x - BORDER * 2, BORDER), col)
	canvas.draw_rect(Rect2(_bp_portrait), col)
	canvas.draw_rect(Rect2(_bp_portrait).grow(-0.5), INK, false, 1.0)
	_draw_face(_bp_portrait, str(line.get("expression", "neutral")), _ink_on(col))
	# "Line done" arrow, blinking.
	var blink := float(t.get("arrow_blink", 0.5))
	if is_open and not is_typing() and not choices_shown() and fmod(_blink, blink * 2.0) < blink:
		var tip := Vector2i(_bp_box.end.x - BORDER - 4, _bp_box.end.y - BORDER - 3)
		for row in 3:
			canvas.draw_rect(Rect2(tip.x - 2 + row, tip.y - 3 + row, 5 - row * 2, 1), INK)
	if choices_shown():
		for i in _bp_choices.size():
			var r := _bp_choices[i]
			var on := show_selection and i == selected
			_panel(r, SELECT if on else PAPER)
			if on:
				# A small "▶" cursor.
				var cx := r.position.x + BORDER + int(t.get("choice_pad_px", 4)) - 1
				var cy := r.position.y + r.size.y / 2
				for col_i in 3:
					canvas.draw_rect(Rect2(cx + col_i, cy - 2 + col_i, 1, 5 - col_i * 2), INK)


## A filled rect with a 1 px ink border and clipped corners.
func _panel(r: Rect2i, fill: Color) -> void:
	canvas.draw_rect(Rect2(r.grow(-BORDER)), fill)
	canvas.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, BORDER), INK)
	canvas.draw_rect(Rect2(r.position.x + 1, r.end.y - BORDER, r.size.x - 2, BORDER), INK)
	canvas.draw_rect(Rect2(r.position.x, r.position.y + 1, BORDER, r.size.y - 2), INK)
	canvas.draw_rect(Rect2(r.end.x - BORDER, r.position.y + 1, BORDER, r.size.y - 2), INK)


## A tiny placeholder face in whole pixels, so expressions read before real
## portraits exist.
func _draw_face(r: Rect2i, expression: String, ink: Color) -> void:
	var o := Vector2(r.position)
	var s := r.size.x / 32.0
	var px := func(x: float, y: float, w: float = 1, h: float = 1) -> void:
		canvas.draw_rect(Rect2((o + Vector2(x, y) * s).round(), (Vector2(w, h) * s).round().max(Vector2.ONE)), ink)
	match expression:
		"happy":
			for ex in [9, 20]:
				px.call(ex, 14); px.call(ex + 1, 13, 1, 1); px.call(ex + 2, 14)
			px.call(12, 21); px.call(13, 22, 6, 1); px.call(19, 21)
		"sad":
			for ex in [10, 20]:
				px.call(ex, 14, 2, 2)
			px.call(8, 12, 3, 1); px.call(21, 12, 3, 1)
			px.call(12, 23); px.call(13, 22, 6, 1); px.call(19, 23)
		"annoyed":
			for ex in [9, 20]:
				px.call(ex, 15, 3, 1)
			px.call(9, 12, 2, 1); px.call(11, 13, 1, 1); px.call(21, 12, 2, 1); px.call(20, 13, 1, 1)
			px.call(13, 22, 6, 1)
		_:
			for ex in [10, 20]:
				px.call(ex, 14, 2, 2)
			px.call(13, 22, 6, 1)


## Dark ink on light colours, light ink on dark ones.
static func _ink_on(c: Color) -> Color:
	return INK if c.get_luminance() > 0.45 else PAPER

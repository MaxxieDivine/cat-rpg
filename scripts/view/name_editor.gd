extends Control
## The Name Editor: pick the player's name from a prefix wheel and a suffix
## wheel. Drawn like the dialogue box, in whole "editor pixels" inside its
## own transparent SubViewport, shown at a whole-number scale k (device
## pixels per editor pixel; pick_scale(): the largest at which the panel
## fits `max_fill` of the safe area), over a dimmed screen. One font pixel
## is one editor pixel; the name and the current words are Pixelify Sans at
## 12 px drawn twice as big, so they stay crisp.
##
## Panel (top to bottom): the player's portrait (Fern's idle sprite) and the
## full name, large; the prefix category tabs (icons: Plants, Weather,
## Animals, Colors, Earth and Water, All) with a red "That name is taken"
## note beside them when the name can't be used; the two wheels (each shows
## the selected word large with its neighbours small and faded above and
## below, slot-machine style, and big up / down arrows); then a lock under
## each wheel (Random leaves a locked wheel alone), Random (dice), Cancel
## and Confirm (dimmed while the name is blocked). On touch screens every
## button and tab is at least `min_target_css` CSS px tall (about 1 cm).
##
## Input (the editor takes everything while open; the world is paused):
##   touch / mouse: tap arrows, tabs, locks and buttons; swipe a wheel up or
##     down (`swipe_px` per word); the mouse wheel scrolls the wheel under it.
##   keyboard: Left / Right pick the wheel, Up / Down scroll it, Tab /
##     PageUp / PageDown change the tab, L locks, R randomizes, Enter
##     confirms, Esc cancels.
##   gamepad: d-pad or left stick like the arrows, South confirms, East
##     cancels, West randomizes, North locks, the shoulders change the tab.
## The focused wheel has a yellow outline and a cursor, so keyboard and
## gamepad players always know where they are.
##
## The choices live in scripts/core/name_picker.gd (headless); Confirm
## calls GameState.set_player_name(), Cancel changes nothing. `closed`
## fires once the editor has finished closing (after the Confirm sparkle).

signal closed(confirmed: bool)
## "open", "tick" (a wheel moved), "move" (tab / lock), "confirm", "cancel",
## "nope" (Confirm while blocked): for UI sounds.
signal ui_event(kind: String)

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const NamePicker := preload("res://scripts/core/name_picker.gd")
const Names := preload("res://scripts/core/names.gd")
const PALETTE_PATH := "res://data/palette.json"
const SPEAKERS_PATH := "res://data/speakers.json"
const CATS_PATH := "res://data/cats.json"
const BORDER := 1
## Layout, editor pixels.
const PANEL_PAD := 7
const COL_GAP := 8
const HEADER_H := 34
const PORTRAIT_W := 48
const TAB := 20
const TAB_GAP := 2
const WHEEL_H := 62
const ARROW_W := 22
const BUTTON_H := 22
const ROW_GAP := 4
const COL_W := 136
## Vertical distance between words on a wheel.
const WORD_STEP := 17

static var INK := Color("#1c1824")
static var PAPER := Color("#f6eedb")
static var PAPER_DARK := Color("#e2d6bb")
static var SELECT := Color("#ffd873")
static var BLOCKED := Color("#b83a3a")
static var DIM := Color(0.11, 0.09, 0.14, 0.69)

## Category icons, 9x9 character grids ('#' = ink).
const ICONS := {
	"Plants": [
		"....##...",
		"...####..",
		"..##.###.",
		".##.####.",
		".#.#####.",
		".######..",
		"..####...",
		".#.......",
		"#........"],
	"Weather": [
		"...###...",
		"..#####..",
		".########",
		"#########",
		".#######.",
		".........",
		"..#..#...",
		".#..#..#.",
		"#..#..#.."],
	"Animals": [
		".##...##.",
		".##...##.",
		".........",
		"#..###..#",
		"#.#####.#",
		"..#####..",
		".#######.",
		".#######.",
		"..##.##.."],
	"Colors": [
		"..#####..",
		".#.....#.",
		"#.##.##.#",
		"#.##.##.#",
		"#.......#",
		"#.##..#.#",
		"#.##.#.#.",
		".#...#...",
		"..###...."],
	"Earth and Water": [
		".........",
		"..##.....",
		".#..#..#.",
		"#....##.#",
		".........",
		"..##.....",
		".#..#..#.",
		"#....##.#",
		"........."],
	"All": [
		"....#....",
		"....#....",
		"..#.#.#..",
		"...###...",
		"#########",
		"...###...",
		"..#.#.#..",
		"....#....",
		"....#...."],
}
const DICE := [
	"#########",
	"#.......#",
	"#.##..#.#",
	"#.##....#",
	"#...#...#",
	"#....##.#",
	"#.#..##.#",
	"#.......#",
	"#########"]
const LOCK_SHUT := [
	"..#####..",
	".#.....#.",
	".#.....#.",
	"#########",
	"#########",
	"####.####",
	"####.####",
	"#########",
	"#########"]
const LOCK_OPEN := [
	"..#####..",
	".#.....#.",
	".#.......",
	"#########",
	"#.......#",
	"#...#...#",
	"#...#...#",
	"#.......#",
	"#########"]

var t: Dictionary = {}
var picker := NamePicker.new()
var is_open := false
## Opened from a conversation (the name-giver) or the debug overlay.
var from_dialogue := false
var metrics
var font: Font
var font_size := 12
## Device pixels per editor pixel.
var k := 1
## UI units per editor pixel.
var unit := 1.0
## Touch screen: show presses, no hover.
var touch_mode := false
var rng := RandomNumberGenerator.new()

var viewport: SubViewport
var canvas: Node2D
var view: Sprite2D

## Layout, UI units (input, tests).
var panel_rect := Rect2()
var wheel_rects: Array[Rect2] = []
var up_rects: Array[Rect2] = []
var down_rects: Array[Rect2] = []
var lock_rects: Array[Rect2] = []
var tab_rects: Array[Rect2] = []
var random_rect := Rect2()
var cancel_rect := Rect2()
var confirm_rect := Rect2()
var name_rect := Rect2()

## Layout, editor pixels.
var _bp_panel := Rect2i()
var _bp_portrait := Rect2i()
var _bp_name := Rect2i()
var _bp_note := Rect2i()
var _bp_tabs: Array[Rect2i] = []
var _bp_wheels: Array[Rect2i] = []
var _bp_up: Array[Rect2i] = []
var _bp_down: Array[Rect2i] = []
var _bp_locks: Array[Rect2i] = []
var _bp_random := Rect2i()
var _bp_cancel := Rect2i()
var _bp_confirm := Rect2i()
var _view_rect := Rect2()
var _view_size := Vector2i.ZERO

## 0 = hidden, 1 = shown.
var _anim := 0.0
## Per wheel: words still sliding into place (in rows, eases to 0).
var _slide: Array[float] = [0.0, 0.0]
var _bounce := 0.0
var _sparkles: Array[Dictionary] = []
var _closing := false
var _confirmed := false
var _opened_frame := -1
## Touch / mouse press: {"id", "target", "start", "wheel", "acc", "moved"}.
var _press: Dictionary = {}
var _stick_held := Vector2i.ZERO
var _portrait_tex: Texture2D
var _portrait_frames := 1
var _portrait_frame := 0.0
var _portrait_fps := 7.0
var _portrait_used := Rect2i(0, 0, 50, 50)
var _player_color := Color("#e8964a")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rng.randomize()


func configure(tuning: Dictionary) -> void:
	t = tuning
	var ui: Dictionary = JsonData.load_dict(PALETTE_PATH).get("ui", {})
	INK = Color(str(ui.get("ink", INK.to_html())))
	PAPER = Color(str(ui.get("paper", PAPER.to_html())))
	PAPER_DARK = Color(str(ui.get("paper_dark", PAPER_DARK.to_html())))
	SELECT = Color(str(ui.get("select", SELECT.to_html())))
	BLOCKED = Color(str(ui.get("blocked", BLOCKED.to_html())))
	DIM = Color(str(ui.get("dim", DIM.to_html())))
	var base := AssetCatalog.font("font.dialogue")
	if base == null:
		base = get_theme_default_font()
	if base is FontFile:
		var ff := base as FontFile
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.oversampling = 1.0
		ff.hinting = TextServer.HINTING_NONE
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	# No ligatures: Pixelify Sans' "fi" ligature reads as an "A".
	var fv := FontVariation.new()
	fv.base_font = base
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
	font = fv
	# The player's portrait: the idle sheet, cropped to the cat.
	var names = picker.names
	var speakers := JsonData.load_dict(SPEAKERS_PATH)
	var pid: String = names.player_speaker()
	_player_color = Color(str(speakers.get(pid, {}).get("color", "#e8964a")))
	_portrait_tex = AssetCatalog.texture("cat.%s.idle" % pid)
	var cat: Dictionary = JsonData.load_dict(CATS_PATH)
	var fpx := int(cat.get("frame_px", 50))
	if _portrait_tex != null and _portrait_tex.get_width() >= fpx:
		_portrait_frames = maxi(1, _portrait_tex.get_width() / fpx)
		var img := _portrait_tex.get_image()  # once, here: get_image() copies
		if img != null:
			_portrait_used = img.get_region(Rect2i(0, 0, fpx, mini(fpx, img.get_height()))).get_used_rect()
	_portrait_fps = float(t.get("portrait_fps", 7))

	viewport = SubViewport.new()
	viewport.name = "EditorViewport"
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
	canvas.draw.connect(_draw_editor)
	viewport.add_child(canvas)
	view = Sprite2D.new()
	view.name = "View"
	view.centered = false
	view.texture = viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)


## The panel's size in editor pixels.
static func panel_size() -> Vector2i:
	var w := PANEL_PAD * 2 + COL_W * 2 + COL_GAP
	var h := PANEL_PAD * 2 + HEADER_H + ROW_GAP + TAB + 3 + WHEEL_H + ROW_GAP + BUTTON_H
	return Vector2i(w, h)


## Device pixels per editor pixel: the largest whole number at which the
## panel fits `max_fill` of the safe area (`safe_px`, device pixels).
func pick_scale(safe_px: Vector2) -> int:
	var fill := float(t.get("max_fill", 0.96))
	var ps := Vector2(panel_size())
	return maxi(1, mini(floori(safe_px.x * fill / ps.x), floori(safe_px.y * fill / ps.y)))


## Lays the editor out over the screen (`scale` 0 = pick_scale()).
func layout(m, scale: int = 0) -> void:
	metrics = m
	if scale <= 0:
		scale = pick_scale(Vector2(m.safe_rect_px().size))
	k = scale
	_view_size = Vector2i((Vector2(m.px_size) / k).ceil())
	_view_rect = Rect2(Vector2.ZERO, m.px_to_ui(Vector2(_view_size) * k))
	unit = float(k) / float(m.px_per_unit.y)
	viewport.size = _view_size
	view.scale = Vector2(k, k) / m.px_per_unit
	var s0: Vector2 = ((m.safe_rect.position - _view_rect.position) / unit).ceil()
	var s1: Vector2 = ((m.safe_rect.end - _view_rect.position) / unit).floor()
	var safe := Rect2i(Vector2i(s0.max(Vector2.ZERO)), Vector2i(s1.min(Vector2(_view_size)) - s0.max(Vector2.ZERO)))
	var ps := panel_size()
	_bp_panel = Rect2i(safe.position + (safe.size - ps) / 2, ps)
	_relayout()


func _relayout() -> void:
	var x0 := _bp_panel.position.x + PANEL_PAD
	var y := _bp_panel.position.y + PANEL_PAD
	var rx := x0 + COL_W + COL_GAP
	_bp_portrait = Rect2i(x0, y, PORTRAIT_W, HEADER_H)
	_bp_name = Rect2i(x0 + PORTRAIT_W + 8, y, COL_W * 2 + COL_GAP - PORTRAIT_W - 8, HEADER_H)
	y += HEADER_H + ROW_GAP
	_bp_tabs = []
	for i in picker.tabs().size():
		_bp_tabs.append(Rect2i(x0 + i * (TAB + TAB_GAP), y, TAB, TAB))
	_bp_note = Rect2i(rx, y, COL_W, TAB)
	y += TAB + 3
	_bp_wheels = [Rect2i(x0, y, COL_W, WHEEL_H), Rect2i(rx, y, COL_W, WHEEL_H)]
	_bp_up = []
	_bp_down = []
	for w in _bp_wheels:
		var ah := (WHEEL_H - 8) / 2
		_bp_up.append(Rect2i(w.end.x - ARROW_W - 3, w.position.y + 3, ARROW_W, ah))
		_bp_down.append(Rect2i(w.end.x - ARROW_W - 3, w.end.y - 3 - ah, ARROW_W, ah))
	y += WHEEL_H + ROW_GAP
	_bp_locks = [Rect2i(x0, y, BUTTON_H, BUTTON_H), Rect2i(rx, y, BUTTON_H, BUTTON_H)]
	_bp_random = Rect2i(x0 + BUTTON_H + 3, y, COL_W - BUTTON_H - 3, BUTTON_H)
	var cancel_w := _text_w(GameStrings.text("names.cancel")) + 12
	_bp_cancel = Rect2i(rx + BUTTON_H + 3, y, cancel_w, BUTTON_H)
	_bp_confirm = Rect2i(_bp_cancel.end.x + 3, y, rx + COL_W - _bp_cancel.end.x - 3, BUTTON_H)

	panel_rect = _ui(_bp_panel)
	name_rect = _ui(_bp_name)
	wheel_rects = []
	up_rects = []
	down_rects = []
	lock_rects = []
	for i in 2:
		wheel_rects.append(_ui(_bp_wheels[i]))
		up_rects.append(_ui(_bp_up[i]))
		down_rects.append(_ui(_bp_down[i]))
		lock_rects.append(_ui(_bp_locks[i]))
	tab_rects = []
	for r in _bp_tabs:
		tab_rects.append(_ui(r))
	random_rect = _ui(_bp_random)
	cancel_rect = _ui(_bp_cancel)
	confirm_rect = _ui(_bp_confirm)
	_place_view()
	canvas.queue_redraw()


## Editor pixels -> UI units.
func _ui(r: Rect2i) -> Rect2:
	return Rect2(_view_rect.position + Vector2(r.position) * unit, Vector2(r.size) * unit)


func _text_w(s: String) -> int:
	return int(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)


# --- Opening and closing


## Opens on the player's current name.
func open(dialogue: bool = false) -> void:
	from_dialogue = dialogue
	picker.open(GameState.state.prefix_id, GameState.state.suffix_id)
	is_open = true
	_closing = false
	_confirmed = false
	visible = true
	_press = {}
	_sparkles = []
	_slide = [0.0, 0.0]
	_opened_frame = Engine.get_process_frames()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui_event.emit("open")
	_relayout()


## Saves the shown name (if allowed), sparkles, then closes.
func confirm() -> bool:
	if not is_open or _closing:
		return false
	if not picker.can_confirm():
		ui_event.emit("nope")
		_bounce = 1.0
		return false
	GameState.set_player_name(picker.prefix_id(), picker.suffix_id())
	ui_event.emit("confirm")
	_confirmed = true
	_closing = true
	_start_sparkles()
	return true


## Closes without changing the name.
func cancel() -> void:
	if not is_open or _closing:
		return
	ui_event.emit("cancel")
	_confirmed = false
	_finish_close()


func _finish_close() -> void:
	is_open = false
	_closing = false
	_press = {}
	closed.emit(_confirmed)


## True while the open / close fade is still running.
func animating() -> bool:
	return _anim != (1.0 if is_open else 0.0)


# --- Commands (input calls these; tests too)


func scroll(wheel: int, delta: int) -> void:
	if not is_open or _closing or delta == 0:
		return
	picker.focus = wheel
	picker.move(wheel, delta)
	_slide[wheel] = clampf(_slide[wheel] + float(signi(delta)), -1.5, 1.5)
	_bounce = 1.0
	ui_event.emit("tick")
	canvas.queue_redraw()


func set_focus(wheel: int) -> void:
	if picker.focus != wheel:
		picker.focus = wheel
		ui_event.emit("move")
		canvas.queue_redraw()


func set_category(i: int) -> void:
	if not is_open or _closing:
		return
	var before := picker.prefix_id()
	picker.set_category(i)
	picker.focus = NamePicker.PREFIX
	if picker.prefix_id() != before:
		_bounce = 1.0
	ui_event.emit("move")
	canvas.queue_redraw()


func toggle_lock(wheel: int) -> void:
	if not is_open or _closing:
		return
	picker.toggle_lock(wheel)
	ui_event.emit("move")
	canvas.queue_redraw()


func randomize_name() -> void:
	if not is_open or _closing:
		return
	var before := [picker.prefix_id(), picker.suffix_id()]
	if picker.roll(rng):
		for w in 2:
			if [picker.prefix_id(), picker.suffix_id()][w] != before[w]:
				_slide[w] = 1.0
		_bounce = 1.0
	ui_event.emit("tick")
	canvas.queue_redraw()


func shown_name() -> String:
	return picker.full_name()


## The note under the tabs: "" while the name can be used.
func note() -> String:
	match picker.status():
		Names.TAKEN:
			return GameStrings.text("names.taken")
		Names.TRIPLE:
			return GameStrings.text("names.triple")
	return ""


# --- Frame


func _process(dt: float) -> void:
	var target := 1.0 if is_open else 0.0
	if _anim != target:
		_anim = move_toward(_anim, target, dt / maxf(0.001, float(t.get("anim_s", 0.15))))
		_place_view()
		if _anim == 0.0 and not is_open:
			visible = false
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
	if not visible:
		return
	var ease_rate := dt / maxf(0.001, float(t.get("scroll_s", 0.12)))
	for w in 2:
		_slide[w] = move_toward(_slide[w], 0.0, ease_rate * maxf(1.0, absf(_slide[w])))
	_bounce = move_toward(_bounce, 0.0, dt / maxf(0.001, float(t.get("bounce_s", 0.18))))
	_portrait_frame = fmod(_portrait_frame + dt * _portrait_fps, float(_portrait_frames))
	if not _sparkles.is_empty():
		for s in _sparkles:
			s["age"] = float(s["age"]) + dt
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * dt
		_sparkles = _sparkles.filter(func(s: Dictionary) -> bool: return float(s["age"]) < float(s["life"]))
	if _closing and _sparkles.is_empty():
		_finish_close()
	canvas.queue_redraw()


func _place_view() -> void:
	var e := ease(_anim, 0.5)
	var slide := roundf((1.0 - e) * float(t.get("anim_slide_px", 6)))
	view.position = _view_rect.position + Vector2(0, slide * unit)
	view.modulate.a = e


func _start_sparkles() -> void:
	var n := int(t.get("sparkles", 14))
	var life := float(t.get("sparkle_s", 0.55))
	var c := Vector2(_bp_name.position.x + _name_width() / 2.0, _bp_name.get_center().y)
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
		var sp := rng.randf_range(40.0, 90.0)
		_sparkles.append({
			"pos": c + Vector2(cos(a) * _name_width() * 0.45, sin(a) * 8.0),
			"vel": Vector2(cos(a), sin(a) * 0.6) * sp,
			"age": 0.0,
			"life": life * rng.randf_range(0.7, 1.0),
		})


# --- Input


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey:
		if _key(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad(event)
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if touch != null:
		touch_mode = true
		_pointer(touch.index, touch.pressed, touch.position)
	elif drag != null:
		_drag(drag.index, drag.position)
	elif mb != null and mb.device != InputEvent.DEVICE_ID_EMULATION:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var w := _wheel_at(_local(mb.position))
				if w >= 0:
					scroll(w, -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			touch_mode = false
			_pointer(-1, mb.pressed, mb.position)
		else:
			return
	elif mm != null and mm.device != InputEvent.DEVICE_ID_EMULATION:
		if not _press.is_empty() and int(_press["id"]) == -1:
			_drag(-1, mm.position)
		return
	else:
		return
	get_viewport().set_input_as_handled()


## Keyboard. True if the key was used.
func _key(ev: InputEventKey) -> bool:
	if not ev.pressed:
		return false
	var code := ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	if ev.echo and not [KEY_UP, KEY_DOWN, KEY_W, KEY_S].has(code):
		return true
	if _closing or Engine.get_process_frames() == _opened_frame:
		return code != KEY_F3
	match code:
		KEY_LEFT, KEY_A:
			set_focus(NamePicker.PREFIX)
		KEY_RIGHT, KEY_D:
			set_focus(NamePicker.SUFFIX)
		KEY_UP, KEY_W:
			scroll(picker.focus, -1)
		KEY_DOWN, KEY_S:
			scroll(picker.focus, 1)
		KEY_TAB:
			set_category(picker.category + (-1 if ev.shift_pressed else 1))
		KEY_PAGEUP:
			set_category(picker.category - 1)
		KEY_PAGEDOWN:
			set_category(picker.category + 1)
		KEY_R:
			randomize_name()
		KEY_L:
			toggle_lock(picker.focus)
		KEY_ENTER, KEY_KP_ENTER:
			confirm()
		KEY_ESCAPE:
			cancel()
		KEY_F3:
			return false  # the debug overlay toggle still works
		_:
			pass
	return true


func _pad(ev: InputEvent) -> void:
	if _closing:
		return
	var jb := ev as InputEventJoypadButton
	if jb != null:
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_DPAD_LEFT:
				set_focus(NamePicker.PREFIX)
			JOY_BUTTON_DPAD_RIGHT:
				set_focus(NamePicker.SUFFIX)
			JOY_BUTTON_DPAD_UP:
				scroll(picker.focus, -1)
			JOY_BUTTON_DPAD_DOWN:
				scroll(picker.focus, 1)
			JOY_BUTTON_A:
				if Engine.get_process_frames() != _opened_frame:
					confirm()
			JOY_BUTTON_B:
				cancel()
			JOY_BUTTON_X:
				randomize_name()
			JOY_BUTTON_Y:
				toggle_lock(picker.focus)
			JOY_BUTTON_LEFT_SHOULDER:
				set_category(picker.category - 1)
			JOY_BUTTON_RIGHT_SHOULDER:
				set_category(picker.category + 1)
		return
	var jm := ev as InputEventJoypadMotion
	if jm == null:
		return
	# The left stick counts once per push, like the d-pad.
	if jm.axis == JOY_AXIS_LEFT_X:
		if absf(jm.axis_value) > 0.6 and _stick_held.x == 0:
			_stick_held.x = 1
			set_focus(NamePicker.SUFFIX if jm.axis_value > 0.0 else NamePicker.PREFIX)
		elif absf(jm.axis_value) < 0.3:
			_stick_held.x = 0
	elif jm.axis == JOY_AXIS_LEFT_Y:
		if absf(jm.axis_value) > 0.6 and _stick_held.y == 0:
			_stick_held.y = 1
			scroll(picker.focus, 1 if jm.axis_value > 0.0 else -1)
		elif absf(jm.axis_value) < 0.3:
			_stick_held.y = 0


func _local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


## What a press at `p` (UI units) hits: "up0", "down1", "lock0", "tab3",
## "wheel1", "random", "cancel", "confirm", "panel" or "".
func target_at(p: Vector2) -> String:
	for i in 2:
		if up_rects[i].has_point(p):
			return "up%d" % i
		if down_rects[i].has_point(p):
			return "down%d" % i
		if lock_rects[i].has_point(p):
			return "lock%d" % i
	for i in tab_rects.size():
		if tab_rects[i].has_point(p):
			return "tab%d" % i
	if random_rect.has_point(p):
		return "random"
	if cancel_rect.has_point(p):
		return "cancel"
	if confirm_rect.has_point(p):
		return "confirm"
	var w := _wheel_at(p)
	if w >= 0:
		return "wheel%d" % w
	return "panel" if panel_rect.has_point(p) else ""


func _wheel_at(p: Vector2) -> int:
	for i in wheel_rects.size():
		if wheel_rects[i].has_point(p):
			return i
	return -1


func _pointer(id: int, pressed: bool, pos: Vector2) -> void:
	if _closing or Engine.get_process_frames() == _opened_frame:
		return
	var p := _local(pos)
	if pressed:
		var target := target_at(p)
		_press = {"id": id, "target": target, "start": p, "acc": 0.0, "moved": false}
		if target.begins_with("up"):
			scroll(int(target.right(1)), -1)
		elif target.begins_with("down"):
			scroll(int(target.right(1)), 1)
		elif target.begins_with("wheel"):
			set_focus(int(target.right(1)))
		canvas.queue_redraw()
		return
	if _press.is_empty() or int(_press["id"]) != id:
		return
	var target: String = _press["target"]
	var moved: bool = _press["moved"]
	_press = {}
	canvas.queue_redraw()
	if target_at(p) != target:
		return
	if target.begins_with("lock"):
		toggle_lock(int(target.right(1)))
	elif target.begins_with("tab"):
		set_category(int(target.substr(3)))
	elif target == "random":
		randomize_name()
	elif target == "cancel":
		cancel()
	elif target == "confirm":
		confirm()
	elif target.begins_with("wheel") and not moved:
		# A tap on a neighbour word steps to it.
		var w := int(target.right(1))
		var r := wheel_rects[w]
		var third := r.size.y / 3.0
		if p.y < r.position.y + third:
			scroll(w, -1)
		elif p.y > r.end.y - third:
			scroll(w, 1)


## Swiping a wheel: one word per `swipe_px` editor pixels; up = next word.
func _drag(id: int, pos: Vector2) -> void:
	if _press.is_empty() or int(_press["id"]) != id or not str(_press["target"]).begins_with("wheel"):
		return
	var w := int(str(_press["target"]).right(1))
	var p := _local(pos)
	var step := float(t.get("swipe_px", 14)) * unit
	var dy: float = (_press["start"] as Vector2).y - p.y
	_press["acc"] = dy
	var steps := int(dy / step)
	if steps != 0:
		_press["moved"] = true
		scroll(w, steps)
		_press["start"] = (_press["start"] as Vector2) - Vector2(0, steps * step)


# --- Drawing (editor pixels)


func _draw_editor() -> void:
	if _view_size == Vector2i.ZERO:
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(_view_size)), DIM)
	# A double frame: ink, paper, ink, like the dialogue box but heavier.
	_panel(_bp_panel, PAPER)
	_outline(_bp_panel.grow(-2), PAPER_DARK)
	_draw_header()
	_draw_tabs()
	for w in 2:
		_draw_wheel(w)
	_draw_buttons()
	for s in _sparkles:
		var a := 1.0 - float(s["age"]) / float(s["life"])
		var p := (s["pos"] as Vector2).round()
		var c := SELECT if int(p.x) % 2 == 0 else Color.WHITE
		c.a = a
		canvas.draw_rect(Rect2(p, Vector2.ONE), c)
		if a > 0.4:
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				canvas.draw_rect(Rect2(p + d, Vector2.ONE), c)


func _draw_header() -> void:
	var r := _bp_portrait
	_panel(r, _player_color)
	if _portrait_tex != null:
		var fpx := 50
		var used := _portrait_used
		var src := Rect2(int(_portrait_frame) * fpx + used.position.x, used.position.y, used.size.x, used.size.y)
		var sc := 2 if used.size.x * 2 <= r.size.x - 4 and used.size.y * 2 <= r.size.y - 4 else 1
		var sz := Vector2(used.size) * sc
		var at := Vector2(r.position) + ((Vector2(r.size) - sz) / 2.0).floor()
		canvas.draw_texture_rect_region(_portrait_tex, Rect2(at, sz), src)
	var full := shown_name()
	var blocked := not picker.can_confirm()
	var col := BLOCKED if blocked else INK
	var big := _name_width() <= _bp_name.size.x
	var lift := -2 if _bounce > 0.55 else (-1 if _bounce > 0.2 else 0)
	var cy := _bp_name.get_center().y + lift
	_text(full, Vector2(_bp_name.position.x, cy), col, big)


func _name_width() -> int:
	var w := _text_w(shown_name())
	return w * 2 if w * 2 <= _bp_name.size.x else w


## Text with its capitals centred vertically on `center_y` (2x if `big`).
func _text(s: String, at: Vector2, col: Color, big: bool, align_center_w: int = -1) -> void:
	var sc := 2 if big else 1
	# Pixelify's capitals are ~9 px tall and end on the baseline.
	var x := at.x
	if align_center_w >= 0:
		x = at.x + floorf((align_center_w - _text_w(s) * sc) / 2.0)
	var baseline := roundf(at.y + 4.5 * sc)
	canvas.draw_set_transform(Vector2(x, baseline), 0.0, Vector2(sc, sc))
	canvas.draw_string(font, Vector2(0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	canvas.draw_set_transform(Vector2.ZERO)


func _draw_tabs() -> void:
	var tabs := picker.tabs()
	for i in _bp_tabs.size():
		var r := _bp_tabs[i]
		var on := i == picker.category
		var pressed := _is_pressed("tab%d" % i)
		_panel(r, SELECT if on else (PAPER_DARK if pressed else PAPER))
		_icon(ICONS.get(tabs[i], ICONS["All"]), r, INK)
	var n := note()
	if n != "":
		_text(n, Vector2(_bp_note.end.x - _text_w(n), _bp_note.get_center().y), BLOCKED, false)
	else:
		# The tab's name while the name is fine.
		var label := picker.category_name()
		_text(label, Vector2(_bp_note.end.x - _text_w(label), _bp_note.get_center().y), Color(INK, 0.45), false)


func _draw_wheel(w: int) -> void:
	var r := _bp_wheels[w]
	var focused := w == picker.focus
	_panel(r, PAPER)
	if focused:
		_outline(r.grow(1), SELECT)
		_outline(r.grow(2), INK)
	var text_x := r.position.x + 9
	var text_w := _bp_up[w].position.x - text_x - 2
	# Caption, top left.
	var cap := GameStrings.text("names.prefix" if w == 0 else "names.suffix")
	_text(cap, Vector2(r.position.x + 4, r.position.y + 5), Color(INK, 0.4), false)
	var mid := float(r.position.y) + 35.0
	for o in range(-2, 3):
		var v := float(o) + _slide[w]
		if absf(v) > 1.25:
			continue
		var s := picker.word_text(w, o)
		var big := absf(v) < 0.5 and _text_w(s) * 2 <= text_w
		var a := clampf(1.0 - absf(v) * 0.55, 0.0, 1.0)
		var col := INK
		if o == 0 and not picker.can_confirm():
			col = BLOCKED
		col.a = a if absf(v) >= 0.5 else 1.0
		var cy := roundf(mid + v * WORD_STEP)
		_text(s, Vector2(text_x, cy), col, big, text_w)
	if focused:
		# A "▶" cursor left of the selected word.
		var cy := int(mid)
		for c in 3:
			canvas.draw_rect(Rect2(r.position.x + 3 + c, cy - 2 + c, 1, 5 - c * 2), INK)
	for i in 2:
		var ar := _bp_up[w] if i == 0 else _bp_down[w]
		var pressed := _is_pressed(("up%d" if i == 0 else "down%d") % w)
		_panel(ar, PAPER_DARK if pressed else (SELECT if focused else PAPER))
		_arrow(ar, i == 0)
	if picker.locked[w]:
		# A small padlock in the wheel's corner, too.
		_icon(LOCK_SHUT, Rect2i(r.position.x + r.size.x - ARROW_W - 15, r.position.y + 3, 9, 9), Color(INK, 0.6))


func _draw_buttons() -> void:
	for w in 2:
		var r := _bp_locks[w]
		var on: bool = picker.locked[w]
		_panel(r, SELECT if on else (PAPER_DARK if _is_pressed("lock%d" % w) else PAPER))
		_icon(LOCK_SHUT if on else LOCK_OPEN, r, INK)
	_button(_bp_random, GameStrings.text("names.random"), "random", true, DICE)
	_button(_bp_cancel, GameStrings.text("names.cancel"), "cancel", true)
	_button(_bp_confirm, GameStrings.text("names.confirm"), "confirm", picker.can_confirm())


func _button(r: Rect2i, label: String, id: String, enabled: bool, icon: Array = []) -> void:
	var fill := PAPER_DARK if _is_pressed(id) else (SELECT if id == "confirm" and enabled else PAPER)
	_panel(r, fill)
	var col := INK if enabled else Color(INK, 0.35)
	var tw := _text_w(label)
	var x := r.position.x + (r.size.x - tw) / 2
	if not icon.is_empty():
		var total := 9 + 4 + tw
		var ix := r.position.x + (r.size.x - total) / 2
		_icon(icon, Rect2i(ix, r.position.y, 9, r.size.y), col)
		x = ix + 13
	_text(label, Vector2(x, r.get_center().y), col, false)


func _is_pressed(id: String) -> bool:
	return not _press.is_empty() and str(_press["target"]) == id


## A 9x9 icon from a character grid, centred in `r`.
func _icon(grid: Array, r: Rect2i, col: Color) -> void:
	var h := grid.size()
	var w := str(grid[0]).length()
	var o := r.position + (r.size - Vector2i(w, h)) / 2
	for y in h:
		var row := str(grid[y])
		for x in w:
			if row[x] == "#":
				canvas.draw_rect(Rect2(o.x + x, o.y + y, 1, 1), col)


## A filled triangle, 7 px wide, pointing up or down.
func _arrow(r: Rect2i, up: bool) -> void:
	var c := r.get_center()
	for row in 4:
		var w := 1 + row * 2
		var y := c.y - 2 + (row if up else 3 - row)
		canvas.draw_rect(Rect2(c.x - row, y, w, 1), INK)


## A filled rect with a 1 px ink border and clipped corners (the dialogue
## box's frame).
func _panel(r: Rect2i, fill: Color) -> void:
	canvas.draw_rect(Rect2(r.grow(-BORDER)), fill)
	_outline(r, INK)


func _outline(r: Rect2i, col: Color) -> void:
	canvas.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, BORDER), col)
	canvas.draw_rect(Rect2(r.position.x + 1, r.end.y - BORDER, r.size.x - 2, BORDER), col)
	canvas.draw_rect(Rect2(r.position.x, r.position.y + 1, BORDER, r.size.y - 2), col)
	canvas.draw_rect(Rect2(r.end.x - BORDER, r.position.y + 1, BORDER, r.size.y - 2), col)

extends Control
## Scene select (dev tool): a dimmed screen with one button per preset
## (data/scene_select.json, scripts/core/scene_presets.gd) and Close. Taps
## and clicks press buttons; keys / gamepad move the focus (arrows, d-pad)
## and press (Enter, Space, South); Esc / East closes. app.gd opens it from
## the title screen, F1 or the "Scenes" debug button while the debug overlay
## is on, and calls game.jump_to() with the pick.

signal picked(id: String)
signal closed

const ScenePresets := preload("res://scripts/core/scene_presets.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")

## Rows are at least this tall (UI units ~ CSS px): thumb-sized.
const ROW := 48.0
const GAP := 8.0

var presets := ScenePresets.new()
var is_open := false
var buttons: Array[Button] = []
var close_button: Button
var title_label: Label
var _dim: ColorRect
var _font: Font


func _ready() -> void:
	name = "SceneSelect"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var base_font := AssetCatalog.font("font.dialogue")
	if base_font != null:
		var fv := FontVariation.new()
		fv.base_font = base_font
		fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
		_font = fv
	_dim = ColorRect.new()
	_dim.color = Color(0.07, 0.06, 0.1, 0.88)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	title_label = Label.new()
	title_label.text = GameStrings.text("scene_select.title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(title_label, 22)
	add_child(title_label)
	for id in presets.ids():
		var p: Dictionary = presets.resolved(id)
		var b := _button(str(p.get("label", id)))
		b.name = "Preset_" + id
		b.pressed.connect(func() -> void: _pick(id))
		buttons.append(b)
	close_button = _button(GameStrings.text("scene_select.close"))
	close_button.name = "Close"
	close_button.pressed.connect(close)


func _style(c: Control, size: int) -> void:
	if _font != null:
		c.add_theme_font_override("font", _font)
	c.add_theme_font_size_override("font_size", size)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	_style(b, 18)
	add_child(b)
	return b


func open() -> void:
	is_open = true
	visible = true
	if not buttons.is_empty():
		buttons[0].grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f != null and is_ancestor_of(f):
		f.release_focus()
	closed.emit()


func _pick(id: String) -> void:
	is_open = false
	visible = false
	picked.emit(id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
	# Nothing behind the menu sees keys while it is up.
	get_viewport().set_input_as_handled()


## Lays the buttons out in the safe area: a column, or more columns when
## they don't fit its height.
func layout(m) -> void:
	var safe: Rect2 = m.safe_rect
	var all: Array[Button] = buttons.duplicate()
	all.append(close_button)
	var top := safe.position.y + 12.0
	title_label.position = Vector2(safe.position.x, top)
	title_label.size = Vector2(safe.size.x, 28.0)
	top += 36.0
	var rows := maxi(1, int((safe.end.y - 12.0 - top + GAP) / (ROW + GAP)))
	var cols := ceili(float(all.size()) / float(rows))
	var w := minf(320.0, (safe.size.x - 32.0 - GAP * (cols - 1)) / cols)
	var x0 := safe.get_center().x - (w * cols + GAP * (cols - 1)) / 2.0
	for i in all.size():
		var c := i / rows
		var r := i % rows
		all[i].position = m.snap(Vector2(x0 + c * (w + GAP), top + r * (ROW + GAP)))
		all[i].size = Vector2(w, ROW)

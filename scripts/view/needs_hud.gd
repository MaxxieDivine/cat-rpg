extends Control
## Hunger and thirst bars (Needs autoload) in the top-left corner of the
## safe area: a prey icon and a water-drop icon, each beside a bar. Drawn in
## "hud pixels" of a whole number of device pixels (about
## tuning.json needs_hud.hud_px_css CSS px each), so icons stay crisp and
## the bars are readable on a phone in landscape. A bar under needs.low
## pulses gently. Ignores input. Built and laid out by game.gd.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var hunger := 0
var thirst := 0
var max_value := 100
var low := 25
## Device pixels per hud pixel.
var px := 2
var hud_px_css := 2.0
var bar_px := Vector2i(40, 6)
var icon_gap := 2
var row_gap := 3
var pulse_hz := 1.4
## Each row's bar in UI units (tests).
var bar_rects: Array[Rect2] = []
## The whole hud in UI units.
var hud_rect := Rect2()
var icons: Array[Texture2D] = []
var colors: Array[Color] = []
var back := Color("#3a3444")
var ink := Color("#1c1824")
var pulse_color := Color("#fff4d0")

var _metrics
var _origin_px := Vector2.ZERO
var _t := 0.0


func _init() -> void:
	name = "NeedsHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(tuning: Dictionary) -> void:
	var t: Dictionary = tuning.get("needs_hud", {})
	var n: Dictionary = tuning.get("needs", {})
	hud_px_css = float(t.get("hud_px_css", hud_px_css))
	var b: Array = t.get("bar_px", [40, 6])
	bar_px = Vector2i(int(b[0]), int(b[1]))
	icon_gap = int(t.get("icon_gap_px", icon_gap))
	row_gap = int(t.get("row_gap_px", row_gap))
	pulse_hz = float(t.get("pulse_hz", pulse_hz))
	max_value = int(n.get("max", max_value))
	low = int(n.get("low", low))
	var ui: Dictionary = JsonData.load_dict("res://data/palette.json").get("ui", {})
	back = Color(str(ui.get("bar_back", "#3a3444")))
	ink = Color(str(ui.get("ink", "#1c1824")))
	pulse_color = Color(str(ui.get("bar_pulse", "#fff4d0")))
	colors = [Color(str(ui.get("hunger", "#e39a4a"))), Color(str(ui.get("thirst", "#5c97c4")))]
	icons = [AssetCatalog.texture("ui.icon_prey"), AssetCatalog.texture("ui.icon_drop")]


## `top_left` is in UI units (inside the safe area).
func layout(m, top_left: Vector2) -> void:
	_metrics = m
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	px = maxi(1, roundi(hud_px_css * m.dpr))
	_origin_px = m.ui_to_px(top_left).round()
	bar_rects.clear()
	var row_h := _row_h()
	for i in 2:
		bar_rects.append(_ui(_bar_px(i)))
	var size_px := Vector2(_icon_w() + icon_gap + bar_px.x, row_h * 2 + row_gap) * px
	hud_rect = Rect2(m.px_to_ui(_origin_px), m.px_to_ui(size_px))
	queue_redraw()


func set_values(h: int, t: int) -> void:
	if h == hunger and t == thirst:
		return
	hunger = h
	thirst = t
	queue_redraw()


func is_low(i: int) -> bool:
	return (hunger if i == 0 else thirst) < low


func _process(dt: float) -> void:
	if is_low(0) or is_low(1):
		_t += dt
		queue_redraw()
	else:
		_t = 0.0


func _icon_w() -> int:
	var w := 0
	for tex in icons:
		w = maxi(w, tex.get_width())
	return w


func _row_h() -> int:
	var h := bar_px.y
	for tex in icons:
		h = maxi(h, tex.get_height())
	return h


## A row's bar in device px.
func _bar_px(i: int) -> Rect2:
	var row_h := _row_h()
	var y := i * (row_h + row_gap) + (row_h - bar_px.y) / 2
	return Rect2(_origin_px + Vector2(_icon_w() + icon_gap, y) * px, Vector2(bar_px) * px)


func _ui(r: Rect2) -> Rect2:
	if _metrics == null:
		return r
	return Rect2(_metrics.px_to_ui(r.position), _metrics.px_to_ui(r.size))


## How much of a bar is filled, 0..1.
func fill(i: int) -> float:
	return clampf(float(hunger if i == 0 else thirst) / float(maxi(1, max_value)), 0.0, 1.0)


func _draw() -> void:
	if _metrics == null:
		return
	var row_h := _row_h()
	for i in 2:
		var tex := icons[i]
		var y := i * (row_h + row_gap)
		var ip := _origin_px + Vector2((_icon_w() - tex.get_width()) / 2, y + (row_h - tex.get_height()) / 2) * px
		draw_texture_rect(tex, _ui(Rect2(ip, tex.get_size() * px)), false)
		var bar := _bar_px(i)
		draw_rect(_ui(bar), ink)
		var inner := bar.grow(-px)
		draw_rect(_ui(inner), back)
		var w := roundf(inner.size.x / px * fill(i)) * px
		if w > 0.0:
			var col := colors[i]
			if is_low(i):
				# A gentle pulse towards a pale flash.
				var k := 0.5 + 0.5 * sin(_t * TAU * pulse_hz)
				col = col.lerp(pulse_color, 0.55 * k)
			draw_rect(_ui(Rect2(inner.position, Vector2(w, inner.size.y))), col)
			# A one-pixel highlight along the top of the fill.
			draw_rect(_ui(Rect2(inner.position, Vector2(w, px))), col.lightened(0.25))

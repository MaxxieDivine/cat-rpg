extends RefCounted
## One place for device-pixel ratio, UI scale and safe-area insets.
##
## UI is laid out in "UI units". update() sets the window's content scale so
## that 1 UI unit is about 1 CSS px (1 / devicePixelRatio device pixels), which
## keeps 48-unit touch targets at 48 CSS px on phones. Pixel art is positioned
## in whole *device* pixels with px_to_ui()/snap() so it stays crisp.
## preload() this script; no class_name.

## Test hooks: when > 0 / non-empty they replace detection.
static var override_dpr := 0.0
## [top, right, bottom, left] in CSS px.
static var override_insets_css: Array = []

const _JS_INSETS := """(function () {
	var d = document.createElement('div');
	d.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;' +
		'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);';
	document.body.appendChild(d);
	var s = getComputedStyle(d);
	var r = [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].map(function (v) { return parseFloat(v) || 0; });
	d.remove();
	return r.join(',');
})()"""

## Window size in device pixels.
var px_size := Vector2i.ZERO
## Device pixels per CSS px (devicePixelRatio on web, screen scale on desktop).
var dpr := 1.0
## Device pixels per UI unit, read back from the window after applying.
var px_per_unit := Vector2.ONE
## Visible area in UI units.
var ui_size := Vector2.ZERO
## Area free of notches / gesture bars, in UI units.
var safe_rect := Rect2()


## Re-reads the screen and applies the content scale to `window`.
## Returns true when anything changed.
func update(window: Window) -> bool:
	var new_px := window.size
	var new_dpr := _detect_dpr(window)
	var target_size := new_px
	if window.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if window.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if window.content_scale_size != target_size:
		window.content_scale_size = target_size
	if not is_equal_approx(window.content_scale_factor, new_dpr):
		window.content_scale_factor = new_dpr

	var xf := window.get_final_transform()
	var new_ppu := Vector2(xf.x.x, xf.y.y)
	if new_ppu.x <= 0.0 or new_ppu.y <= 0.0:
		new_ppu = Vector2(new_dpr, new_dpr)
	var new_ui := window.get_visible_rect().size
	var css := _detect_insets_css(window, new_dpr)
	# CSS px -> device px -> UI units
	var top: float = css[0] * new_dpr / new_ppu.y
	var right: float = css[1] * new_dpr / new_ppu.x
	var bottom: float = css[2] * new_dpr / new_ppu.y
	var left: float = css[3] * new_dpr / new_ppu.x
	var new_safe := Rect2(left, top, maxf(0.0, new_ui.x - left - right), maxf(0.0, new_ui.y - top - bottom))

	var changed := new_px != px_size or new_dpr != dpr or new_ppu != px_per_unit \
		or new_ui != ui_size or new_safe != safe_rect
	px_size = new_px
	dpr = new_dpr
	px_per_unit = new_ppu
	ui_size = new_ui
	safe_rect = new_safe
	return changed


## Safe area in device pixels, shrunk inward to whole pixels.
func safe_rect_px() -> Rect2i:
	var p := (safe_rect.position * px_per_unit).ceil()
	var e := (safe_rect.end * px_per_unit).floor()
	return Rect2i(Vector2i(p), Vector2i(e - p))


func px_to_ui(px: Vector2) -> Vector2:
	return px / px_per_unit


func ui_to_px(ui: Vector2) -> Vector2:
	return ui * px_per_unit


## Rounds a UI-unit position to the nearest whole device pixel.
func snap(ui: Vector2) -> Vector2:
	return px_to_ui(ui_to_px(ui).round())


static func is_web() -> bool:
	return OS.has_feature("web")


static func _detect_dpr(window: Window) -> float:
	if override_dpr > 0.0:
		return override_dpr
	var v := 0.0
	if is_web():
		v = float(str(JavaScriptBridge.eval("window.devicePixelRatio || 1", true)))
	else:
		v = DisplayServer.screen_get_scale(window.current_screen)
	return v if v > 0.0 else 1.0


## Returns [top, right, bottom, left] in CSS px.
static func _detect_insets_css(window: Window, p_dpr: float) -> Array:
	if override_insets_css.size() == 4:
		return override_insets_css
	if is_web():
		var raw := str(JavaScriptBridge.eval(_JS_INSETS, true))
		var parts := raw.split(",")
		if parts.size() == 4:
			return [parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float()]
		return [0.0, 0.0, 0.0, 0.0]
	if OS.has_feature("mobile"):
		# Native mobile: safe area is reported in screen pixels.
		var screen := DisplayServer.screen_get_size(window.current_screen)
		var safe := DisplayServer.get_display_safe_area()
		var s := maxf(p_dpr, 0.0001)
		return [safe.position.y / s, (screen.x - safe.end.x) / s, (screen.y - safe.end.y) / s, safe.position.x / s]
	return [0.0, 0.0, 0.0, 0.0]

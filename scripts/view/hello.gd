extends Control
## Hello Cow: a crisp, integer-scaled cow that says "Moo!" when tapped.
## Layout is in UI units (about 1 CSS px); the cow itself is placed in whole
## device pixels via ScreenMetrics so every art pixel is a whole number of
## device pixels.

signal cow_tapped

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

const COW_KEY := "cow.idle"
const BUILD_PATH := "res://data/build.json"
const TUNING_PATH := "res://data/tuning.json"

@onready var cow: Sprite2D = $Cow
@onready var tap_target: Control = $TapTarget
@onready var bubble: PanelContainer = $Bubble
@onready var bubble_text: Label = $Bubble/Text
@onready var bubble_tail: Polygon2D = $BubbleTail
@onready var build_label: Label = $BuildLabel

var metrics := ScreenMetrics.new()
## Device pixels per art pixel (whole number).
var cow_scale := 1
## True while the cow is in its "up" bob frame.
var bob_up := false

var _tuning: Dictionary = {}
var _cow_rest_px := Vector2.ZERO
var _bubble_timer: Timer
var _bob_timer: Timer
var _laying_out := false


func _ready() -> void:
	_tuning = JsonData.load_dict(TUNING_PATH).get("hello", {})
	cow.texture = AssetCatalog.texture(COW_KEY)
	bubble_text.text = GameStrings.text("hello.moo")
	build_label.text = build_text()

	_bubble_timer = _make_timer(_on_bubble_timeout)
	_bob_timer = _make_timer(_on_bob_timeout)
	tap_target.gui_input.connect(_on_tap_target_input)
	get_window().size_changed.connect(relayout)
	relayout()


func tuning(key: String, default: float) -> float:
	return float(_tuning.get(key, default))


func is_bubble_visible() -> bool:
	return bubble.visible


## Re-reads screen metrics and places everything. Called on every resize.
func relayout() -> void:
	if _laying_out:
		return
	_laying_out = true
	metrics.update(get_window())
	_layout_cow()
	_layout_bubble()
	_layout_build_label()
	_laying_out = false


## The cow's on-screen rect in UI units (including any bob offset).
func cow_rect() -> Rect2:
	var tex_size := Vector2(cow.texture.get_size())
	return Rect2(cow.position, tex_size * cow.scale)


func build_text() -> String:
	var info := {}
	if FileAccess.file_exists(BUILD_PATH):
		info = JsonData.load_dict(BUILD_PATH)
	var sha := str(info.get("sha", ""))
	if sha.is_empty():
		return GameStrings.text("build.label", {"sha": GameStrings.text("build.dev"), "date": ""}).strip_edges()
	return GameStrings.text("build.label", {"sha": sha, "date": str(info.get("date", ""))})


func _layout_cow() -> void:
	var safe_px := metrics.safe_rect_px()
	var art := Vector2(cow.texture.get_size())
	var short_side := float(mini(safe_px.size.x, safe_px.size.y))
	var target := short_side * tuning("cow_screen_fraction", 0.333)
	cow_scale = maxi(1, floori(target / maxf(art.x, art.y)))
	# Never exceed the safe area if it is tiny.
	while cow_scale > 1 and (art.x * cow_scale > safe_px.size.x or art.y * cow_scale > safe_px.size.y):
		cow_scale -= 1
	var cow_px := art * cow_scale
	_cow_rest_px = (Vector2(safe_px.position) + (Vector2(safe_px.size) - cow_px) / 2.0).floor()
	cow.scale = Vector2(cow_scale, cow_scale) / metrics.px_per_unit
	_place_cow()

	# Tap target: the cow's rest rect, grown to at least min_tap_target UI units.
	var rest := Rect2(metrics.px_to_ui(_cow_rest_px), metrics.px_to_ui(cow_px))
	var min_size := tuning("min_tap_target", 48.0)
	var size_ui := rest.size.max(Vector2(min_size, min_size))
	tap_target.position = rest.get_center() - size_ui / 2.0
	tap_target.size = size_ui


func _place_cow() -> void:
	var px := _cow_rest_px
	if bob_up:
		px.y -= cow_scale  # one art pixel up
	cow.position = metrics.px_to_ui(px)


func _layout_bubble() -> void:
	bubble.reset_size()
	var size_ui := bubble.get_combined_minimum_size()
	bubble.size = size_ui
	var rest_top_ui := metrics.px_to_ui(_cow_rest_px).y
	var center_x := metrics.px_to_ui(_cow_rest_px).x + cow.texture.get_size().x * cow.scale.x / 2.0
	var gap := tuning("bubble_gap", 14.0)
	var pos := Vector2(center_x - size_ui.x / 2.0, rest_top_ui - gap - size_ui.y)
	var safe := metrics.safe_rect
	pos.x = clampf(pos.x, safe.position.x, maxf(safe.position.x, safe.end.x - size_ui.x))
	pos.y = maxf(pos.y, safe.position.y)
	bubble.position = metrics.snap(pos)
	# Little tail pointing at the cow.
	var tip := Vector2(center_x, bubble.position.y + size_ui.y + gap * 0.8)
	var base_y := bubble.position.y + size_ui.y - 3.0
	bubble_tail.polygon = PackedVector2Array([
		metrics.snap(Vector2(center_x - 9, base_y)),
		metrics.snap(Vector2(center_x + 9, base_y)),
		metrics.snap(tip),
	])
	bubble_tail.visible = bubble.visible


func _layout_build_label() -> void:
	var margin := tuning("corner_margin", 8.0)
	build_label.reset_size()
	var size_ui := build_label.get_combined_minimum_size()
	var safe := metrics.safe_rect
	build_label.position = metrics.snap(Vector2(safe.position.x + margin, safe.end.y - margin - size_ui.y))


func _on_tap_target_input(event: InputEvent) -> void:
	# Touch arrives as emulated mouse events (emulate_mouse_from_touch), so one
	# handler covers both and a tap is never counted twice.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		tap_target.accept_event()
		_on_cow_tapped()


func _on_cow_tapped() -> void:
	bubble.visible = true
	bubble_tail.visible = true
	_bubble_timer.start(tuning("bubble_seconds", 1.5))
	bob_up = true
	_place_cow()
	_bob_timer.start(tuning("bob_seconds", 0.12))
	cow_tapped.emit()


func _on_bubble_timeout() -> void:
	bubble.visible = false
	bubble_tail.visible = false


func _on_bob_timeout() -> void:
	bob_up = false
	_place_cow()


func _make_timer(callback: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(callback)
	add_child(t)
	return t

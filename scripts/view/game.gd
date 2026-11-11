extends Control
## The game screen. The world renders into a small SubViewport (cheap on
## phones) shown at a whole-number scale k in device pixels. k is the largest
## scale at which the 480x270 base view fits the screen; the view then
## *expands* to fill the rest of the screen at that k (stretch aspect
## "expand"), up to view.max in tuning.json, so wider screens see more
## meadow. A Camera2D follows the cat, limited to the world's edges.
## Text, bubbles and touch controls are drawn at full resolution on top, in
## UI units (about 1 CSS px).

const World := preload("res://scripts/core/world.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameInput := preload("res://scripts/view/game_input.gd")
const WorldView := preload("res://scripts/view/world_view.gd")
const TouchControls := preload("res://scripts/view/touch_controls.gd")
const SpeechBubble := preload("res://scripts/view/speech_bubble.gd")

var world
var tuning: Dictionary = {}
var metrics
## Device pixels per world pixel (whole number).
var view_scale := 1
## Where the world is drawn, in UI units.
var view_rect := Rect2()
## World pixels the camera shows (SubViewport size).
var view_size := Vector2i(480, 270)
## The part of the world on screen (world pixels).
var camera_rect := Rect2()
var paused := false
## "touch" or "keys": the last kind of input used. Touch controls hide while
## the player uses a keyboard or gamepad.
var last_input := ""

var viewport: SubViewport
var world_view: Node2D
var camera: Camera2D
var view: Sprite2D
var touch: Control
var bubble: Control
var prompt: Control
var _bubble_npc := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameInput.ensure_actions()
	tuning = JsonData.load_dict("res://data/tuning.json")
	world = World.new()

	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = view_size
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world_view = WorldView.new()
	world_view.name = "WorldView"
	viewport.add_child(world_view)
	world_view.setup(world, tuning)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.size.x)
	camera.limit_bottom = int(world.size.y)
	viewport.add_child(camera)
	camera.make_current()

	# A Sprite2D, not a TextureRect: Controls are snapped to whole UI units
	# (gui/common/snap_controls_to_pixels), which is a fraction of a device
	# pixel off at DPR 2 or 3. Sprites go exactly where we put them.
	view = Sprite2D.new()
	view.name = "View"
	view.texture = viewport.get_texture()
	view.centered = false
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)

	prompt = SpeechBubble.new()
	prompt.name = "Prompt"
	prompt.font_size = 14
	add_child(prompt)
	bubble = SpeechBubble.new()
	bubble.name = "Bubble"
	add_child(bubble)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.configure(tuning.get("touch", {}))
	touch.interact_pressed.connect(_on_touch_interact)
	touch.visible = ScreenMetrics.is_touch()
	add_child(touch)


func layout(m) -> void:
	metrics = m
	var gap := float(tuning.get("ui", {}).get("bubble_gap", 6))
	bubble.gap = gap
	prompt.gap = gap
	var v: Dictionary = tuning.get("view", {})
	var base := _vec(v.get("base", [480, 270]))
	var max_view := _vec(v.get("max", [640, 400]))
	var screen_px := Vector2(m.px_size)
	view_scale = ScreenMetrics.integer_fit(base, screen_px)
	# Expand: fill the whole screen at this scale (ceil, so no gap at the
	# edges), but never more than max_view (then letterbox, centred).
	var want := (screen_px / view_scale).ceil().min(max_view)
	view_size = Vector2i(want)
	viewport.size = view_size
	var size_px := Vector2(view_size) * view_scale
	var pos_px := ((screen_px - size_px) / 2.0).floor()
	view_rect = Rect2(m.px_to_ui(pos_px), m.px_to_ui(size_px))
	view.position = view_rect.position
	view.scale = Vector2(view_scale, view_scale) / m.px_per_unit
	_update_camera()
	touch.layout(m)
	_place_overlays()


func set_paused(p: bool) -> void:
	paused = p
	if p:
		touch.reset()


## World pixels -> UI units.
func world_to_ui(p: Vector2) -> Vector2:
	return view_rect.position + (p - camera_rect.position) * view_rect.size / Vector2(view_size)


func _update_camera() -> void:
	camera_rect = world.camera_rect(Vector2(view_size))
	camera.position = camera_rect.position


static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


func _process(dt: float) -> void:
	if paused or metrics == null:
		return
	var inp := GameInput.read(touch)
	if touch.stick_vector != Vector2.ZERO:
		_set_last_input("touch")
	for ev in world.step(dt, inp["move"], inp["run"]):
		if ev["type"] == "focus" and ev["id"] != _bubble_npc:
			bubble.hide_bubble()
	world_view.sync()
	_update_camera()
	_place_overlays()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_set_last_input("touch")
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_set_last_input("keys")


func _unhandled_input(event: InputEvent) -> void:
	if paused:
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		interact()
		get_viewport().set_input_as_handled()


func _on_touch_interact() -> void:
	if not paused:
		interact()


## Talks to whoever is in range (if anyone).
func interact() -> void:
	for ev in world.interact():
		if ev["type"] == "say":
			_bubble_npc = ev["id"]
			bubble.show_text(GameStrings.text(ev["text_key"]), float(tuning.get("game", {}).get("bubble_seconds", 1.5)))
	world_view.sync()
	_place_overlays()


func _set_last_input(kind: String) -> void:
	if kind == last_input:
		return
	last_input = kind
	var show := kind == "touch" or (kind == "" and ScreenMetrics.is_touch())
	if touch.visible != show:
		touch.visible = show
		touch.reset()
	_place_overlays()


func _place_overlays() -> void:
	if metrics == null:
		return
	var bounds: Rect2 = metrics.safe_rect
	var focus: String = world.focus_id
	touch.highlight = focus != ""
	if bubble.visible and _bubble_npc != "":
		bubble.point_at(world_to_ui(world_view.npc_head(_bubble_npc)), bounds)
	# Prompt: a small "E" over whoever you can talk to (keyboard players only;
	# on touch the paw button lights up instead).
	var show_prompt := focus != "" and not bubble.visible and not touch.visible
	if show_prompt:
		if not prompt.visible:
			prompt.show_text(GameStrings.text("hint.interact_desktop"), 0.0)
		prompt.point_at(world_to_ui(world_view.npc_head(focus)), bounds)
	elif prompt.visible:
		prompt.hide_bubble()

extends Control
## The game screen. The world renders into a small SubViewport (cheap on
## phones) shown at a whole-number scale k in device pixels. k is the largest
## scale at which the 480x270 base view fits the screen; the view then
## *expands* to fill the rest of the screen at that k (stretch aspect
## "expand"), so wider screens see more meadow and the world always reaches
## every edge (no letterbox up to view.max, which no real screen reaches).
## A Camera2D follows the cat, limited to the meadow plus its forest border;
## past that the forest is drawn further out, so it never shows flat colour.
## Text, the dialogue box and touch controls are drawn at full resolution on
## top, in UI units (about 1 CSS px).
##
## Talking: Interact next to an NPC starts its conversation (DialogueManager
## autoload); the box shows it, movement is locked, the joystick hides and
## the camera eases so both cats sit above the box.
##
## Time of day (scripts/core/day_cycle.gd): after the last of the three
## conversations, afternoon turns to dusk and night; the world view, the
## music and the ambience follow it. Sound (sound.gd) is created here, after
## tap-to-start, like the voice.

const World := preload("res://scripts/core/world.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const GameInput := preload("res://scripts/view/game_input.gd")
const WorldView := preload("res://scripts/view/world_view.gd")
const TouchControls := preload("res://scripts/view/touch_controls.gd")
const DialogueBox := preload("res://scripts/view/dialogue_box.gd")
const Voice := preload("res://scripts/view/voice.gd")
const Sound := preload("res://scripts/view/sound.gd")
const DayCycle := preload("res://scripts/core/day_cycle.gd")

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
var dialogue: Control
var voice: Node
var sound: Node
var day
## Distance walked when the last footstep played (world px).
var _step_at := 0.0
## Where the camera centres (world px) while easing to / from a conversation.
var _cam_center := Vector2.INF
var _cam_easing := false
var _stick_y_held := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameInput.ensure_actions()
	tuning = JsonData.load_dict("res://data/tuning.json")
	world = World.new()
	day = DayCycle.new(tuning.get("time_of_day", {}))
	# A new game: fresh flags and bonds, nothing mid-conversation.
	GameState.reset()
	DialogueManager.stop()

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
	world_view.setup(world, tuning, day)
	world_view.rustled.connect(_on_rustle)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	var lim: Rect2 = world.camera_bounds()
	camera.limit_left = int(lim.position.x)
	camera.limit_top = int(lim.position.y)
	camera.limit_right = int(lim.end.x)
	camera.limit_bottom = int(lim.end.y)
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

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.configure(tuning.get("touch", {}))
	touch.interact_pressed.connect(_on_touch_interact)
	touch.visible = ScreenMetrics.is_touch()
	add_child(touch)

	# Created here, after tap-to-start: no sound can play before it.
	voice = Voice.new()
	voice.jitter = float(tuning.get("dialogue", {}).get("pitch_jitter", 0.05))
	add_child(voice)
	sound = Sound.new()
	add_child(sound)
	sound.configure(tuning.get("audio", {}))
	sound.play_music("day")
	# After the touch controls: it gets taps first and swallows them.
	dialogue = DialogueBox.new()
	dialogue.name = "Dialogue"
	dialogue.configure(tuning.get("dialogue", {}), JsonData.load_dict("res://data/speakers.json"), voice)
	dialogue.advance_requested.connect(_on_advance)
	dialogue.choice_made.connect(_on_choice)
	dialogue.ui_event.connect(func(kind: String) -> void: sound.play(kind))
	add_child(dialogue)


func layout(m) -> void:
	metrics = m
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
	touch.layout(m)
	dialogue.touch_rows = ScreenMetrics.is_touch()
	dialogue.layout(m, view_rect, view_size, view_scale)
	_update_camera(0.0)
	_place_overlays()


func set_paused(p: bool) -> void:
	paused = p
	if p:
		touch.reset()


## World pixels -> UI units.
func world_to_ui(p: Vector2) -> Vector2:
	return view_rect.position + (p - camera_rect.position) * view_rect.size / Vector2(view_size)


func is_talking() -> bool:
	return dialogue.is_open


## Follows the cat. While talking, eases so the middle of the two cats sits
## in the middle of the world left visible above the dialogue box, then
## eases back afterwards.
func _update_camera(dt: float) -> void:
	var follow: Rect2 = world.camera_rect(Vector2(view_size))
	var target := follow.get_center()
	if world.is_talking():
		target = _talk_center()
		_cam_easing = true
	if _cam_easing and _cam_center != Vector2.INF:
		var k := 1.0 - exp(-float(tuning.get("dialogue", {}).get("camera_ease", 10)) * dt)
		_cam_center = _cam_center.lerp(target, k) if dt > 0.0 else target
		if not world.is_talking() and _cam_center.distance_to(target) < 0.5:
			_cam_easing = false
	else:
		_cam_center = target
	camera_rect = world.camera_rect(Vector2(view_size), _cam_center) if _cam_easing else follow
	camera.position = camera_rect.position


func _talk_center() -> Vector2:
	var npc: Dictionary = world.npc_by_id(world.talk_id)
	var feet: Vector2 = (world.player_pos + npc["pos"]) / 2.0
	var mid := feet - Vector2(0, 10)
	# World y of the box's top edge, if the camera were at the top (offset
	# within the view is all that matters).
	var box_top_view: float = (dialogue.box_rect.position.y - view_rect.position.y) * float(view_size.y) / view_rect.size.y
	var free_mid := clampf(box_top_view, 0.0, float(view_size.y)) / 2.0
	# A little lift, so heads clear the name plate and choices sit beside them.
	var lift := float(tuning.get("dialogue", {}).get("camera_lift_px", 6))
	return mid + Vector2(0, float(view_size.y) / 2.0 - free_mid + lift)


static func _vec(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


func _process(dt: float) -> void:
	if paused or metrics == null:
		return
	var inp := GameInput.read(touch)
	if touch.stick_vector != Vector2.ZERO:
		_set_last_input("touch")
	world.step(dt, inp["move"], inp["run"])
	day.step(dt, GameState.state.flags, is_talking())
	_update_camera(dt)
	world_view.camera_rect = camera_rect
	world_view.sync(dt)
	_update_sound()
	_place_overlays()


## Footsteps every few px walked (grass or path), ambience for the time of
## day and the pond.
func _update_sound() -> void:
	if sound == null:
		return
	var every := float(tuning.get("audio", {}).get("footstep_px", 14))
	if world.distance - _step_at >= every:
		_step_at = world.distance
		if world.speed() >= world_view.idle_speed:
			sound.footstep(world.surface())
	sound.set_time(day.day_amount(), day.night_amount())
	var r := float(world.pond.get("lap_radius", 40)) if not world.pond.is_empty() else 1.0
	sound.set_pond_near(1.0 - clampf(world.pond_distance() / r, 0.0, 1.0))


func _on_rustle(_kind: String) -> void:
	if sound != null:
		sound.play("rustle")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_set_last_input("touch")
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_set_last_input("keys")


func _unhandled_input(event: InputEvent) -> void:
	if paused:
		return
	if is_talking():
		_dialogue_input(event)
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		interact()
		get_viewport().set_input_as_handled()


## Keyboard / gamepad while the box is open: Interact finishes or advances,
## up/down pick a choice (the left stick counts once per push).
func _dialogue_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_Y:
			if absf(event.axis_value) > 0.6 and not _stick_y_held:
				_stick_y_held = true
				dialogue.move_selection(1 if event.axis_value > 0.0 else -1)
			elif absf(event.axis_value) < 0.3:
				_stick_y_held = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		dialogue.press()
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		dialogue.move_selection(-1)
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		dialogue.move_selection(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_touch_interact() -> void:
	if not paused:
		interact()


## Talks to whoever is in range (if anyone).
func interact() -> void:
	if is_talking():
		return
	for ev in world.interact():
		if ev["type"] == "talk":
			_show(DialogueManager.start(ev["dialogue"]))
	world_view.sync()
	_place_overlays()


func _on_advance() -> void:
	_show(DialogueManager.advance())


func _on_choice(index: int) -> void:
	_show(DialogueManager.choose(index))


func _show(ev: Dictionary) -> void:
	if ev["type"] == "line":
		dialogue.show_selection = last_input != "touch" and not touch.visible
		var rows: bool = last_input == "touch" or (last_input == "" and ScreenMetrics.is_touch())
		if dialogue.touch_rows != rows:
			dialogue.touch_rows = rows
		dialogue.show_line(ev)
	else:
		dialogue.close()
		world.end_talk()
	_update_touch_visibility()
	_place_overlays()


func _set_last_input(kind: String) -> void:
	if kind == last_input:
		return
	last_input = kind
	_update_touch_visibility()
	_place_overlays()


## Touch controls: on touch devices (or after touch input), hidden while a
## keyboard is used and while a conversation is open (a tap advances then).
func _update_touch_visibility() -> void:
	var show := last_input == "touch" or (last_input == "" and ScreenMetrics.is_touch())
	if is_talking():
		show = false
	if touch.visible != show:
		touch.visible = show
		touch.reset()


func _place_overlays() -> void:
	if metrics == null:
		return
	# The paw button lights up when someone is in range (the world view
	# shows the paw-print prompt over them).
	touch.highlight = world.focus_id != "" and not world.is_talking()

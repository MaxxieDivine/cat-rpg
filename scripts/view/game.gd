extends Control
## The game screen. The world renders into a small SubViewport (cheap on
## phones) shown at a whole-number scale k in device pixels: the camera zoom.
## Auto zoom (Settings.camera_zoom 0) picks the k at which the screen shows
## about `view.target_rows` world pixels top to bottom (within `view.rows`,
## 135..180); zoom 1 / 2 / 3 is that many times the largest scale at which
## the whole 480x270 base view fits (1 = the Milestone 3 view). The view
## then *expands* to fill the screen at that k (stretch aspect "expand"), so
## wider screens see more meadow and the world always reaches every edge.
## A Camera2D follows the cat with smoothing, in whole world pixels, limited
## to the meadow plus its forest border; past that the forest is drawn
## further out, so it never shows flat colour.
## Text, the dialogue box (its own pixel scale, see dialogue_box.gd) and
## touch controls are drawn on top, outside the world's SubViewport, so the
## camera zoom never changes them.
##
## Talking: Interact next to an NPC starts its conversation (DialogueManager
## autoload); the box shows it, movement is locked, the joystick hides and
## the camera eases so both cats sit above the box.
##
## Needs (Needs autoload, scripts/core/needs.gd): hunger and thirst tick
## down while the game runs (not on the title, not while paused) and show as
## two bars top-left (needs_hud.gd). Interact at the fresh-catch pile eats,
## at the pond's edge drinks; the nearest thing in range (cat, pile or pond)
## gets the paw prompt. "The pile is empty." and similar short lines show
## over Fern for needs_hud.message_s (`message`).
##
## Areas (data/areas.json, scripts/core/areas.gd): the game starts in the
## camp. Walking into an exit fades to black (travel.gd, tuning.json
## travel.fade_s), builds the other area's World and WorldView in the same
## SubViewport (load_area()), puts Fern at the exit's spawn and fades back
## in. Camera limits are set per area. Hunger, thirst (Needs), the area,
## spawn and what Fern carries (Player) are autoloads, so they carry over;
## flags, bonds and the time of day too.
##
## Passing out: when hunger or thirst reaches 0 (and no conversation, meal
## or fade is running), control locks, Fern sinks down, the screen fades to
## black, Player.collapse_message shows until a tap / key or a moment
## passes, she wakes at Player.recovery_area / recovery_spawn (her den in
## camp) with Needs restore values and nothing carried, and stretches before
## control comes back. travel.gd runs the sequence; it can't start twice.
##
## Hunting (Milestone 1.2): Crouch (held C / Ctrl / a shoulder button, or
## the touch toggle) stalks; Pounce (Space / E / South, or the touch button)
## leaps at a mouse in range, otherwise those keys interact as before.
## Carrying a mouse, interact at the pile delivers it, at Sorrel gives it,
## with nothing in focus eats it (the touch Eat button too). Squeaks get
## quieter with distance (hunt.hear_px). The World gets the Hunting
## autoload's tuning and the Player autoload's state on every area load.
##
## Naming: after the name-giver's own lines (data/names/naming.json
## "giver", Sorrel) the naming conversation follows; "Can I have a new
## name?" reaches an await node, the box closes and the Name Editor
## (name_editor.gd) opens over the paused world (no movement, no needs
## drain, no time of day). Confirm or Cancel resumes the conversation, whose
## reply uses the (new) {player_name}. The debug overlay opens the editor
## anywhere (open_name_editor()).
##
## Patrols (Patrols autoload, scripts/core/patrol.gd): talking to the
## deputy (data/patrols.json "deputy") rolls a patrol before the
## conversation starts (prepare_offer()); its choices set the flag `patrol`,
## acted on when it ends (after_talk()). Accepted, the mates walk to the
## camp entrance (world.json marker PatrolMeet) and wait; leaving through
## the entrance sets the patrol out, and from then on the mates follow Fern
## into every outdoor area (load_area() adds them behind her). Prey
## delivered to the pile counts for a hunting patrol; when the patrol is
## done the mates walk home. The goal shows under the needs bars.
##
## Story (Story autoload, scripts/core/story.gd, data/story.json): once
## enough border patrols are marked, Wick goes missing (load_area() leaves
## him out of every area) and the deputy's report tells the rogue news;
## then the story's goal shows when no patrol runs, and the deputy offers
## no patrols.
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
const NeedsHud := preload("res://scripts/view/needs_hud.gd")
const GameStrings := preload("res://scripts/core/game_strings.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const Areas := preload("res://scripts/core/areas.gd")
const Travel := preload("res://scripts/core/travel.gd")
const NameEditor := preload("res://scripts/view/name_editor.gd")

## The Name Editor opened or closed (app.gd hides the corner buttons under it).
signal naming_changed(open: bool)

var world
var areas
## Fades between areas and the passing-out sequence (scripts/core/travel.gd).
var travel
var tuning: Dictionary = {}
var metrics
## Device pixels per world pixel (whole number).
var view_scale := 1
## Inspector / remote-debugger hook: 0 = use Settings.camera_zoom, else that
## zoom (1..3, or any larger whole number to try).
@export var zoom_override := 0:
	set(v):
		zoom_override = maxi(0, v)
		if metrics != null:
			layout(metrics)
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
var name_editor: Control
var voice: Node
var sound: Node
var day
var needs_hud: Control
## A short line over Fern ("The pile is empty."), and seconds left.
var message: Label
## A place's name over its paw prompt (a den's doorway: "Apprentices' den").
var prompt_label: Label
## The patrol's goal under the needs bars ("Scent marks: 1 / 4").
var goal_label: Label
## The NPC Fern is talking to (the deputy's conversation ends a patrol
## offer or report).
var _talk_npc := ""
var _message_t := 0.0
## Distance walked when the last footstep played (world px).
var _step_at := 0.0
## Who spoke the last line shown (a new speaker meows).
var _speaker := ""
## Where the camera centres (world px) while easing to / from a conversation.
var _cam_center := Vector2.INF
var _cam_easing := false
var _stick_y_held := false
## Black over everything while travelling, and the line shown on it after
## passing out (plus a "tap to continue" hint).
var fade: ColorRect
var fade_message: Label
var fade_hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameInput.ensure_actions()
	tuning = JsonData.load_dict("res://data/tuning.json")
	areas = Areas.new()
	travel = Travel.new(tuning)
	day = DayCycle.new(tuning.get("time_of_day", {}))
	# A new game: fresh flags and bonds, nothing mid-conversation.
	GameState.reset()
	DialogueManager.stop()
	Needs.reset()
	Player.reset(areas.start_area(), "start")
	Patrols.reset()
	Story.reset()

	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = view_size
	viewport.disable_3d = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	camera.make_current()
	load_area(areas.start_area(), "start")

	# A Sprite2D, not a TextureRect: Controls are snapped to whole UI units
	# (gui/common/snap_controls_to_pixels), which is a fraction of a device
	# pixel off at DPR 2 or 3. Sprites go exactly where we put them.
	view = Sprite2D.new()
	view.name = "View"
	view.texture = viewport.get_texture()
	view.centered = false
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)

	needs_hud = NeedsHud.new()
	needs_hud.configure(tuning)
	needs_hud.set_values(Needs.hunger(), Needs.thirst())
	Needs.needs_changed.connect(needs_hud.set_values)
	add_child(needs_hud)
	message = Label.new()
	message.name = "Message"
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var base_font := AssetCatalog.font("font.dialogue")
	if base_font != null:
		# Pixelify's "fi" ligature reads as an "A": off, as in the box.
		var fv := FontVariation.new()
		fv.base_font = base_font
		fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
		message.add_theme_font_override("font", fv)
	message.add_theme_color_override("font_color", Color(str(JsonData.load_dict("res://data/palette.json").get("ui", {}).get("paper", "#f6eedb"))))
	message.add_theme_color_override("font_outline_color", Color(0.11, 0.09, 0.14, 0.9))
	message.add_theme_constant_override("outline_size", 6)
	message.add_theme_font_size_override("font_size", int(tuning.get("needs_hud", {}).get("message_font", 18)))
	message.visible = false
	add_child(message)
	prompt_label = message.duplicate()
	prompt_label.name = "PromptLabel"
	prompt_label.add_theme_font_size_override("font_size", int(tuning.get("needs_hud", {}).get("label_font", 16)))
	add_child(prompt_label)
	goal_label = message.duplicate()
	goal_label.name = "PatrolGoal"
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	goal_label.add_theme_font_size_override("font_size", int(tuning.get("needs_hud", {}).get("goal_font", 16)))
	goal_label.add_theme_constant_override("outline_size", 5)
	add_child(goal_label)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.configure(tuning.get("touch", {}))
	touch.interact_pressed.connect(_on_touch_interact)
	touch.pounce_pressed.connect(func() -> void:
		if not paused and not travel.busy():
			pounce())
	touch.eat_pressed.connect(func() -> void:
		if not paused and not travel.busy():
			eat_carried())
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
	GameState.name_changed.connect(_on_name_changed)
	GameState.rank_changed.connect(_on_name_changed)
	DialogueManager.awaiting.connect(_on_awaiting)
	# Over the box: while open it takes every key, button and tap first.
	name_editor = NameEditor.new()
	name_editor.name = "NameEditor"
	name_editor.configure(tuning.get("name_editor", {}))
	name_editor.closed.connect(_on_name_editor_closed)
	name_editor.ui_event.connect(func(kind: String) -> void: sound.play(kind))
	add_child(name_editor)

	# Over everything on the game screen: the fade to black.
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.visible = false
	add_child(fade)
	fade_message = _pixel_label("FadeMessage", int(tuning.get("collapse", {}).get("message_font", 20)))
	fade_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fade.add_child(fade_message)
	fade_hint = _pixel_label("FadeHint", int(tuning.get("needs_hud", {}).get("message_font", 18)) - 4)
	fade_hint.modulate = Color(1, 1, 1, 0.7)
	fade.add_child(fade_hint)


## A centred Pixelify label in the paper colour (the "fi" ligature off, as
## in the dialogue box).
func _pixel_label(n: String, size: int) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var base_font := AssetCatalog.font("font.dialogue")
	if base_font != null:
		var fv := FontVariation.new()
		fv.base_font = base_font
		fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
		l.add_theme_font_override("font", fv)
	l.add_theme_color_override("font_color", Color(str(JsonData.load_dict("res://data/palette.json").get("ui", {}).get("paper", "#f6eedb"))))
	l.add_theme_font_size_override("font_size", size)
	return l


## The patrol in a freshly loaded area: mates waiting at the camp entrance
## (gathering), or following Fern (out, in any outdoor area).
func _patrol_into(w) -> void:
	var cfg: Dictionary = Patrols.config()
	w.follow_gap = float(cfg.get("follow_gap", w.follow_gap))
	w.follow_speed = float(cfg.get("follow_speed", w.follow_speed))
	w.home_speed = float(cfg.get("home_speed", w.home_speed))
	if not Patrols.is_active():
		return
	_update_scent(w)
	var mates: Array = Patrols.mates()
	if Patrols.phase() == "gather":
		if w.id == str(cfg.get("camp", "camp")):
			for i in mates.size():
				w.place_npc(mates[i], meet_point(w, i), 1)
		return
	if w.is_indoors():
		return
	for i in mates.size():
		var id: String = mates[i]
		if w.npc_by_id(id).is_empty():
			w.add_follower(id, {"footprint": Vector2(16, 5)})
		else:
			w.follow(mates.slice(0, i + 1))
			var npc: Dictionary = w.npc_by_id(id)
			npc["pos"] = w._behind(i + 1)
			npc["rect"] = w.footprint_rect(npc["pos"], npc["footprint"])
	w.follow(mates)


## Tells the world which of its scent spots the patrol wants (marked or not).
func _update_scent(w) -> void:
	var wanted := {}
	for m: Dictionary in Patrols.patrol.active.get("marks", []):
		if m["area"] == w.id:
			wanted[m["id"]] = Patrols.patrol.is_marked(m["area"], m["id"])
	w.set_scent_wanted(wanted)


## Where patrol mate number `i` waits at the camp entrance (the PatrolMeet
## marker, then a step back and to the side for each).
func meet_point(w, i: int) -> Vector2:
	var cfg: Dictionary = Patrols.config()
	var at: Vector2 = w.markers.get(str(cfg.get("meet", "PatrolMeet")), w.player_pos)
	var gap := float(cfg.get("meet_gap", 18))
	return at + Vector2(-gap * i, 14.0 * (i % 2))


## Patrol events: speech lines, mates walking to the entrance or home.
func _handle_patrol(events: Array[Dictionary]) -> void:
	for ev in events:
		match ev["type"]:
			"patrol_start":
				say(GameStrings.text("patrol.started"))
				for i in (ev["mates"] as Array).size():
					world.send_npc(ev["mates"][i], meet_point(world, i))
			"patrol_out":
				say(GameStrings.text("patrol.out"))
			"patrol_mark":
				say(GameStrings.text("patrol.marked"))
				_update_scent(world)
			"patrol_report":
				# Enough border patrols: Wick goes missing; the deputy
				# tells the news at the report (data/story.json).
				Story.border_marked(Patrols.mates())
				say(GameState.format_text(GameStrings.text("patrol.all_marked")))
				if sound != null:
					sound.play("confirm")
			"patrol_done":
				say(GameStrings.text("patrol.done"))
				if sound != null:
					sound.play("confirm")
				for id in ev["mates"]:
					if world.npc_by_id(id).get("visitor", false):
						continue
					world.send_home(id)
				world.stop_following()
				world.set_scent_wanted({})
	_place_overlays()


## Builds area `id` (data/areas.json) in the world SubViewport with Fern at
## spawn `spawn_name` (its "start" if there is no such spawn), replacing the
## area shown now. Camera limits follow the area. Needs, Player, flags and
## the time of day are untouched.
func load_area(id: String, spawn_name: String) -> bool:
	var w = areas.load_world(id, tuning)
	if w == null:
		return false
	if not w.spawns.has(spawn_name):
		push_warning("game: area '%s' has no spawn '%s'; using start" % [id, spawn_name])
		spawn_name = "start"
	w.hunt_tuning = Hunting.tuning
	w.player_state = Player.state
	w.place_at_spawn(spawn_name)
	# Story beats: a missing cat is in no area (Story autoload).
	for npc: Dictionary in w.npcs.duplicate():
		if Story.absent(npc["id"]):
			w.remove_npc(npc["id"])
	_patrol_into(w)
	if world_view != null:
		viewport.remove_child(world_view)
		world_view.queue_free()
	world = w
	world_view = WorldView.new()
	world_view.name = "WorldView"
	viewport.add_child(world_view)
	viewport.move_child(world_view, 0)
	world_view.setup(world, tuning, day)
	world_view.rustled.connect(_on_rustle)
	var lim: Rect2 = world.camera_bounds()
	camera.limit_left = int(lim.position.x)
	camera.limit_top = int(lim.position.y)
	camera.limit_right = int(lim.end.x)
	camera.limit_bottom = int(lim.end.y)
	_step_at = world.distance
	_cam_center = Vector2.INF
	_cam_easing = false
	Player.arrive(id, spawn_name)
	if metrics != null:
		_update_camera(0.0)
		world_view.camera_rect = camera_rect
		world_view.sync()
	return true


func layout(m) -> void:
	metrics = m
	var v: Dictionary = tuning.get("view", {})
	var base := _vec(v.get("base", [480, 270]))
	var max_view := _vec(v.get("max", [640, 400]))
	var screen_px := Vector2(m.px_size)
	view_scale = pick_zoom(v, screen_px, zoom_override if zoom_override > 0 else Settings.camera_zoom)
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
	var fit := ScreenMetrics.integer_fit(base, screen_px)
	var safe_px: Rect2i = m.safe_rect_px()
	dialogue.layout(m, dialogue.pick_scale(screen_px, float(safe_px.size.x), screen_px.y - float(safe_px.end.y), fit, Settings.text_scale))
	name_editor.layout(m)
	# The needs bars: top-left, in from the corner like the buttons, below
	# the build / fps label while that is on.
	var inset := float(tuning.get("ui", {}).get("button_inset", 12))
	var top: Vector2 = m.safe_rect.position + Vector2(inset, inset * 0.5)
	if Settings.debug_overlay:
		top.y += 16.0
	needs_hud.layout(m, top)
	_layout_fade(m)
	_cam_center = Vector2.INF
	_update_camera(0.0)
	_place_overlays()


func set_paused(p: bool) -> void:
	paused = p
	if p:
		touch.reset()


## Device pixels per world pixel for `screen_px` (tuning.json "view").
## `zoom` 0 = auto: the whole number k whose view height (screen / k) lies in
## `rows` and is closest to `target_rows` (if none does, the nearest k).
## `zoom` n > 0 = n times the largest k at which `base` fits the screen.
static func pick_zoom(v: Dictionary, screen_px: Vector2, zoom: int) -> int:
	var base := _vec(v.get("base", [480, 270]))
	if zoom > 0:
		return ScreenMetrics.integer_fit(base, screen_px) * zoom
	var target := float(v.get("target_rows", 160))
	var rows := _vec(v.get("rows", [135, 180]))
	var best := maxi(1, roundi(screen_px.y / target))
	var best_d := INF
	for k in range(1, int(screen_px.y / maxf(1.0, rows.x)) + 1):
		var h := screen_px.y / k
		if h >= rows.x and h <= rows.y and absf(h - target) < best_d:
			best_d = absf(h - target)
			best = k
	return best


## World pixels -> UI units.
func world_to_ui(p: Vector2) -> Vector2:
	return view_rect.position + (p - camera_rect.position) * view_rect.size / Vector2(view_size)


func is_talking() -> bool:
	return dialogue.is_open


## Follows the cat with smoothing (`view.camera_follow`). While talking,
## eases (`dialogue.camera_ease`) so the middle of the two cats sits in the
## middle of the world left visible above the dialogue box, then eases back.
## The camera sits on whole world pixels, and while it trails a walking cat
## its offset from her is rounded (not its position), so she never jitters
## by a pixel against the screen while the meadow scrolls under her.
func _update_camera(dt: float) -> void:
	var vs := Vector2(view_size)
	var target: Vector2 = world.camera_rect(vs).get_center()
	var rate := float(tuning.get("view", {}).get("camera_follow", 8))
	if world.is_talking():
		target = _talk_center()
		_cam_easing = true
	if _cam_easing:
		rate = float(tuning.get("dialogue", {}).get("camera_ease", 10))
	if _cam_center == Vector2.INF or dt <= 0.0 or rate <= 0.0:
		_cam_center = target
	else:
		_cam_center = _cam_center.lerp(target, 1.0 - exp(-rate * dt))
	if _cam_easing and not world.is_talking() and _cam_center.distance_to(target) < 0.5:
		_cam_easing = false
	if _cam_center.distance_to(target) < 0.25:
		_cam_center = target
	var top_left: Vector2 = world.camera_rect(vs, _cam_center, false).position
	var anchor: Vector2 = world.player_pos.round()
	top_left = anchor + (top_left - world.player_pos).round()
	camera_rect = world.camera_rect(vs, top_left + vs / 2.0)
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
	if naming():
		return  # the world waits behind the Name Editor
	var inp := GameInput.read(touch)
	if touch.stick_vector != Vector2.ZERO:
		_set_last_input("touch")
	# No control while fading or passed out.
	var locked: bool = travel.busy()
	_handle(world.step(dt, Vector2.ZERO if locked else inp["move"], false if locked else inp["run"], inp["crouch"] and not locked))
	if travel.busy():
		_handle_travel(travel.step(dt))
	else:
		Needs.step(dt)
		_check_collapse()
	day.step(dt, GameState.state.flags, is_talking())
	_update_camera(dt)
	world_view.camera_rect = camera_rect
	world_view.sync(dt)
	_update_sound()
	_message_t = maxf(0.0, _message_t - dt)
	_place_overlays()
	_update_fade()


## Hunger or thirst at 0 makes Fern pass out, once: not mid-conversation or
## mid-meal (those finish first), and never while a fade already runs.
func _check_collapse() -> void:
	if Needs.needs.collapsed() and not is_talking() and not world.is_talking() and not world.is_busy() and not world.is_leaping():
		collapse()


## Starts passing out (false if a fade or collapse is already running).
func collapse() -> bool:
	if not travel.collapse(Player.recovery_area, Player.recovery_spawn):
		return false
	world.player_vel = Vector2.ZERO
	world.running = false
	world_view.pose = "down"
	touch.reset()
	_update_touch_visibility()
	_update_fade()
	return true


## An exit was walked into: fade out, load the other area, fade in. Out of
## camp through the entrance, a gathered patrol sets out.
func _on_exit(ev: Dictionary) -> void:
	if not areas.has(ev["to"]):
		push_warning("game: exit '%s' leads to unknown area '%s'" % [ev["id"], ev["to"]])
		return
	var cfg: Dictionary = Patrols.config()
	if world.id == str(cfg.get("camp", "camp")) and ev["id"] == str(cfg.get("entrance_exit", "")):
		Patrols.left_camp()
	if travel.go(ev["to"], ev["spawn"]):
		touch.reset()
		_update_touch_visibility()
		_update_fade()


func _handle_travel(events: Array[Dictionary]) -> void:
	for ev in events:
		match ev["type"]:
			"load":
				if ev["collapsed"]:
					# Carried home: rested, needs restored, nothing in her mouth.
					Needs.needs.restore()
					Needs.refresh()
					Player.drop_carried()
					Player.state.collapses += 1
				if ev["collapsed"] and ev["area"] == world.id:
					world.place_at_spawn(ev["spawn"])
					Player.arrive(ev["area"], world_spawn_name(ev["spawn"]))
					_cam_center = Vector2.INF
					_update_camera(0.0)
				else:
					load_area(ev["area"], ev["spawn"])
				if ev["collapsed"]:
					world_view.pose = "down"
				_message_t = 0.0
			"wake":
				world_view.pose = "wake"
			"done":
				_update_touch_visibility()
		_place_overlays()


func world_spawn_name(n: String) -> String:
	return n if world.spawns.has(n) else "start"


## Debug overlay helper: sets hunger or thirst (e.g. to 5, to test passing out).
func debug_set_need(which: String, value: int) -> void:
	Needs.set_value(which, value)


## Debug overlay helper: a mouse at the prey spot nearest Fern (if free).
func debug_spawn_mouse() -> bool:
	if world.hunt == null:
		return false
	return not world.hunt.spawn_at(world.hunt.nearest_spot(world.player_pos)).is_empty()


## Leaps at the mouse in range (if any).
func pounce() -> bool:
	if is_talking() or travel.busy():
		return false
	var ev: Array[Dictionary] = world.pounce()
	_handle(ev)
	return not ev.is_empty()


## Eats the carried mouse (the touch Eat button).
func eat_carried() -> void:
	if is_talking() or travel.busy():
		return
	_handle(world.eat_carried(Needs.needs))
	Needs.refresh()


func _layout_fade(m) -> void:
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe: Rect2 = m.safe_rect
	var w := minf(safe.size.x - 32.0, 520.0)
	fade_message.size = Vector2(w, 0)
	fade_message.custom_minimum_size = Vector2(w, 0)
	fade_hint.custom_minimum_size = Vector2(w, 0)


## The black overlay follows travel.black(); after passing out, the message
## (and a hint) shows on it.
func _update_fade() -> void:
	if fade == null:
		return
	var a: float = travel.black()
	fade.visible = a > 0.0
	fade.color = Color(0, 0, 0, a)
	var show_msg: bool = travel.phase == "message"
	fade_message.visible = show_msg
	fade_hint.visible = show_msg and travel.phase_time() >= travel.min_message_s
	if show_msg and metrics != null:
		fade_message.text = Player.collapse_message
		var touchy: bool = last_input == "touch" or (last_input == "" and ScreenMetrics.is_touch())
		fade_hint.text = GameStrings.text("collapse.continue_touch" if touchy else "collapse.continue_keys")
		var safe: Rect2 = metrics.safe_rect
		fade_message.reset_size()
		fade_hint.reset_size()
		var c := safe.get_center()
		fade_message.position = metrics.snap(c - Vector2(fade_message.size.x / 2.0, fade_message.size.y))
		fade_hint.position = metrics.snap(Vector2(c.x - fade_hint.size.x / 2.0, c.y + 18.0))


## Footsteps every few px walked (grass or path), ambience for the time of
## day and the pond.
func _update_sound() -> void:
	if sound == null:
		return
	var every := float(tuning.get("audio", {}).get("footstep_px", 14))
	if world.distance - _step_at >= every and not world.is_busy():
		_step_at = world.distance
		if world.speed() >= world_view.idle_speed:
			# Stalking is quieter.
			sound.footstep(world.surface(), -12.0 if world.crouching else 0.0)
	sound.set_indoors(world.is_indoors())
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
	if travel != null and travel.phase == "message" and not paused and _is_continue(event):
		travel.confirm()
		get_viewport().set_input_as_handled()


## A tap, a real click, Interact / Enter or a gamepad button (not emulated
## mouse events from touch, so a tap counts once).
func _is_continue(event: InputEvent) -> bool:
	if event.is_echo() or not event.is_pressed():
		return false
	if event is InputEventScreenTouch:
		return true
	if event is InputEventMouseButton:
		return event.device != InputEvent.DEVICE_ID_EMULATION
	if event is InputEventJoypadButton:
		return true
	return event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")


func _unhandled_input(event: InputEvent) -> void:
	if paused or travel.busy() or naming():
		return
	if is_talking():
		_dialogue_input(event)
		return
	# Pounce shares Interact's keys: a mouse in range wins.
	if event.is_action_pressed("pounce") and not event.is_echo() and world.can_pounce():
		pounce()
		get_viewport().set_input_as_handled()
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
	if not paused and not travel.busy():
		interact()


## Interacts with whatever has focus: talks to a cat, eats from the pile or
## drinks at the pond.
func interact() -> void:
	if is_talking() or travel.busy():
		return
	_handle(world.interact(Needs.needs))
	Needs.refresh()
	world_view.sync()
	_place_overlays()


## World events: conversations, eating and drinking (sounds), short lines.
func _handle(events: Array[Dictionary]) -> void:
	for ev in events:
		match ev["type"]:
			"talk":
				_talk_npc = str(ev.get("id", ""))
				if _talk_npc == Patrols.deputy():
					Patrols.prepare_offer()
				_show(DialogueManager.start(ev["dialogue"], DialogueManager.follow_up_for(_talk_npc)))
			"eat":
				if sound != null:
					sound.play("eat")
				if ev.get("carried", false):
					say(GameStrings.text("hunt.ate"))
			"pounce":
				if sound != null:
					sound.play("pounce")
			"catch":
				if sound != null:
					sound.play("catch")
			"miss", "mouse_flee":
				if sound != null:
					sound.play("flee", _distance_db(ev.get("pos", world.player_pos)))
			"squeak":
				var db := _distance_db(ev["pos"])
				if sound != null and db > -60.0:
					sound.play("squeak", db)
			"deliver":
				if sound != null:
					sound.play("drop")
				say(GameStrings.text("hunt.delivered"))
				_handle_patrol(Patrols.delivered())
			"give":
				if sound != null:
					sound.play("drop")
			"drink":
				if sound != null:
					sound.play("drink")
			"message":
				say(GameState.format_text(GameStrings.text(ev["key"])))
			"exit":
				_on_exit(ev)
			"marking":
				if sound != null:
					sound.play("rustle")
			"scent":
				_handle_patrol(Patrols.mark(world.id, ev["id"]))


## Quieter with distance from Fern; -80 dB (silent) past hunt.hear_px.
func _distance_db(p: Vector2) -> float:
	var hear := float(tuning.get("hunt", {}).get("hear_px", 260))
	var d: float = world.player_pos.distance_to(p)
	if d > hear:
		return -80.0
	return -18.0 * d / maxf(1.0, hear)


## Shows a short line over Fern for a moment (needs_hud.message_s).
func say(text: String) -> void:
	message.text = text
	_message_t = float(tuning.get("needs_hud", {}).get("message_s", 1.8))
	_place_overlays()


func _on_advance() -> void:
	_show(DialogueManager.advance())


func _on_choice(index: int) -> void:
	_show(DialogueManager.choose(index))


func _show(ev: Dictionary) -> void:
	if ev["type"] == "await":
		# The conversation waits on a screen (_on_awaiting opens it); the
		# box steps aside, the talk lock stays.
		_speaker = ""
		dialogue.close()
	elif ev["type"] == "line":
		if ev["speaker"] != _speaker:
			_speaker = ev["speaker"]
			world_view.speak(_speaker)
		dialogue.show_selection = last_input != "touch" and not touch.visible
		var rows: bool = last_input == "touch" or (last_input == "" and ScreenMetrics.is_touch())
		if dialogue.touch_rows != rows:
			dialogue.touch_rows = rows
		dialogue.show_line(ev)
	else:
		_speaker = ""
		dialogue.close()
		world.end_talk()
		var who := _talk_npc
		_talk_npc = ""
		if who == Patrols.deputy():
			_handle_patrol(Patrols.after_talk())
	_update_touch_visibility()
	_place_overlays()


## True while the Name Editor is up (the world is paused behind it).
func naming() -> bool:
	return name_editor != null and name_editor.is_open


## Opens the Name Editor. `from_dialogue`: a conversation waits on it and
## resumes when it closes. Not during a fade or while it is already open.
func open_name_editor(from_dialogue: bool = false) -> bool:
	if naming() or travel.busy():
		return false
	if not from_dialogue and (is_talking() or world.is_talking()):
		return false
	world.player_vel = Vector2.ZERO
	world.running = false
	touch.reset()
	name_editor.touch_mode = last_input == "touch" or (last_input == "" and ScreenMetrics.is_touch())
	name_editor.open(from_dialogue)
	_update_touch_visibility()
	naming_changed.emit(true)
	return true


## A cat was renamed or re-ranked: its name plate follows.
func _on_name_changed(_id: String, _value: String) -> void:
	dialogue.refresh_name()


func _on_awaiting(screen: String) -> void:
	if screen == "name_editor":
		open_name_editor(true)


func _on_name_editor_closed(confirmed: bool) -> void:
	naming_changed.emit(false)
	if name_editor.from_dialogue and DialogueManager.is_waiting():
		_show(DialogueManager.resume(confirmed))
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
	if is_talking() or naming() or (travel != null and travel.busy()):
		show = false
	if touch.visible != show:
		touch.visible = show
		touch.reset()


func _place_overlays() -> void:
	if metrics == null:
		return
	# The paw button lights up when someone is in range (the world view
	# shows the paw-print prompt over them).
	touch.highlight = world.focus_id != "" and not world.is_talking() and not world.is_busy() and not world.is_leaping()
	touch.hunt_buttons = world.hunt != null
	touch.can_pounce = world.can_pounce()
	touch.carrying = world.carrying() != ""
	_place_prompt_label()
	_place_goal()
	message.visible = _message_t > 0.0 and not is_talking()
	if message.visible:
		# Over Fern's head, kept inside the safe area.
		message.modulate.a = clampf(_message_t / 0.3, 0.0, 1.0)
		message.reset_size()
		var head := world_to_ui(world.player_pos - Vector2(0, 26))
		var pos := head - Vector2(message.size.x / 2.0, message.size.y)
		var safe: Rect2 = metrics.safe_rect
		pos.x = clampf(pos.x, safe.position.x, maxf(safe.position.x, safe.end.x - message.size.x))
		pos.y = clampf(pos.y, safe.position.y, maxf(safe.position.y, safe.end.y - message.size.y))
		message.position = metrics.snap(pos)


## The patrol's goal (or with no patrol, the story's: "Investigate the
## rogue scent by the river."), just under the needs bars (not over the
## Name Editor or a fade).
func _place_goal() -> void:
	var text: String = Patrols.goal_text()
	if text == "":
		text = Story.goal_text()
	goal_label.visible = text != "" and not naming() and not (travel != null and travel.busy())
	if not goal_label.visible:
		return
	if goal_label.text != text:
		goal_label.text = text
	goal_label.reset_size()
	goal_label.position = metrics.snap(needs_hud.hud_rect.position + Vector2(0, needs_hud.hud_rect.size.y + 2.0))


## The focused place's name (a spot's `label`) just over its paw prompt,
## while the prompt shows and no line is being said.
func _place_prompt_label() -> void:
	var sp: Dictionary = world.spot_by_id(world.focus_id)
	var key: String = str(sp.get("label", ""))
	var paw: Sprite2D = world_view.paw
	prompt_label.visible = key != "" and paw.visible and _message_t <= 0.0 and not (travel != null and travel.busy())
	if not prompt_label.visible:
		return
	prompt_label.text = GameState.format_text(GameStrings.text(key))
	prompt_label.reset_size()
	var top := world_to_ui(paw.position + Vector2(paw.texture.get_width() / 2.0, -1.0))
	var pos := top - Vector2(prompt_label.size.x / 2.0, prompt_label.size.y)
	var safe: Rect2 = metrics.safe_rect
	pos.x = clampf(pos.x, safe.position.x, maxf(safe.position.x, safe.end.x - prompt_label.size.x))
	pos.y = clampf(pos.y, safe.position.y, maxf(safe.position.y, safe.end.y - prompt_label.size.y))
	prompt_label.position = metrics.snap(pos)

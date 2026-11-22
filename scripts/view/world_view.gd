extends Node2D
## Draws a World (scripts/core/world.gd) in world pixels. Lives inside the
## small SubViewport. Only shows state; never changes it.
##
## Layers, bottom to top:
##   Forest   the forest-floor canopy tile, far past every edge (so a wide
##            or tall screen never shows flat colour)
##   Ground   the baked meadow floor (art/ground.png: grass patches, path),
##            the pond (shimmer shader), sunny spot, drop shadows
##   Decor    tufts and flower clusters (wind sway)
##   Sorted   y-sorted: bushes, rocks, the log, tree trunks, NPCs, Fern and
##            tall-grass blades (so Fern walks *through* the grass)
##   Life     butterflies
##   Canopies tree crowns, over everything on the ground; one Fern stands
##            under goes see-through
##   Sky      slow cloud shadows, the occasional bird shadow, pollen
##   Grade    a CanvasModulate: warm afternoon -> dusk -> night
##   Overlay  a CanvasLayer that the grade doesn't touch: fireflies and the
##            paw-print prompt (it bobs over the NPC Fern can talk to)
## Wind: one sway ShaderMaterial per kind (grass, flower, bush, canopy),
## amplitudes from tuning.json "wind". Fern brushing tall grass or a bush
## gives it a short rustle (a skew) and emits `rustled`.
## Cosmetic randomness (butterflies, birds) uses the view's own RNG.
## Areas: one WorldView per area (game.gd builds a new one on every area
## change). Exits become AreaExit nodes (scenes/area_exit.tscn, Inspector
## exports) and prey spots Marker2D nodes, under "Markers"; both are
## invisible in play. An area may override the palette's grade colours
## (world.grade: the Hunting Grounds is more golden).
## Hunting: mice (life.mouse sheet) are y-sorted with Fern, so tall grass
## hides them; feeding mice shake the blades near them now and then (the
## sign to look for). A "!" (ui.alert_mark) bobs over a mouse with its head
## up; an alert bar shows over mice near Fern; the landing ring
## (ui.pounce_ring, on the ground under it) marks the mouse a pounce would go for. Fern crouches in
## the low frames of her stretch, leaps (her sprite rises, her shadow stays
## on the ground), bounces after a catch and carries the mouse in her mouth
## (life.mouse_carried, hunt.mouth_px from her feet). These go on the
## Overlay layer so they stay readable at night.
## Passing out: `pose` "down" sinks Fern into the low crouch of her stretch
## and holds it; "wake" plays the whole stretch, then she is herself again.

signal rustled(kind: String)

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const NpcScene := preload("res://scenes/npc.tscn")
const PileScene := preload("res://scenes/fresh_catch_pile.tscn")
const ExitScene := preload("res://scenes/area_exit.tscn")
const CatAnim := preload("res://scripts/view/cat_anim.gd")
const PLAYER_ID := "fern"
const MEOW_KEY := "fx.meow"
const PAW_KEY := "ui.paw"
const RIPPLE_KEY := "fx.ripple"
## Fern's animation while eating or drinking (world.action).
const ACTION_ANIM := "lick"
## Passing out and waking: the stretch sheet. Its first frames lower her
## into a crouch (held while she is "down"); the whole sheet is her waking.
const COLLAPSE_ANIM := "stretch"
const COLLAPSE_LOW_FRAME := 2
const COLLAPSE_FPS := 4.0
const SPEAKERS_PATH := "res://data/speakers.json"
const PALETTE_PATH := "res://data/palette.json"
## How far past the camera bounds the forest tile is drawn (world px).
const FOREST_REACH := 1400.0

var world
var day  # day_cycle.gd, or null
## Fern (cat_anim.gd): idle, walk, run, meow and fidgets (data/cats.json).
var player: CatAnim
## The little "meow" puff over a cat that starts speaking.
var meow: Sprite2D
## Who the puff belongs to ("fern" or an NPC id) and seconds left.
var _meow_who := ""
var _meow_t := 0.0
## Fern standing still: seconds since she stopped or finished a fidget.
var _still := 0.0
var _next_fidget := 0
## The interact prompt over whatever has focus (NPC, pile, pond edge).
var paw: Sprite2D
## Each cat's rank symbol over its head (data/names/naming.json "ranks";
## the rank comes from GameState), on the Overlay: cat id -> Sprite2D.
var rank_marks: Dictionary = {}
## Gap between a head and its rank symbol (world px; tuning.json prompt.rank_gap).
var rank_gap := 2.0
## The fresh-catch pile (fresh_catch_pile.gd), or null.
var pile: Sprite2D
## Rings on the water where Fern drinks.
var ripple: Sprite2D
var _action_seen := ""
var walk_frame_px := 7.0
var idle_speed := 4.0
var bob_px := 2.0
var bob_hz := 1.6
var prompt_gap := 3.0
## NPC nodes (npc.gd) by id.
var npc_nodes: Dictionary = {}
var palette: Dictionary = {}
var grade: CanvasModulate
var overlay: CanvasLayer
var pond: Sprite2D
var pollen: CPUParticles2D
var fireflies: CPUParticles2D
var butterflies: Array[Sprite2D] = []
var clouds: Array[Sprite2D] = []
var bird: Sprite2D
var canopies: Array[Sprite2D] = []
## Sway materials by kind ("grass", "flower", "bush", "canopy").
var materials: Dictionary = {}
## The part of the world on screen (set by game.gd every frame).
var camera_rect := Rect2(0, 0, 480, 270)

var _forest: Node2D
var _ground: Node2D
var _decor: Node2D
var _sorted: Node2D
var _life: Node2D
var _canopy_layer: Node2D
var _sky: Node2D
## Rustly things: {"node", "base_y" (sprite height), "kind", "t" (time
## left), "dir"}. Blades by index into world.tall_grass, then bushes.
var _rustlers: Array[Dictionary] = []
var _prop_rustler: Dictionary = {}
var _canopy_rects: Array[Rect2] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _wind: Dictionary = {}
var _amb: Dictionary = {}
var _bird_wait := 6.0
var _bird_vel := Vector2.ZERO
var _butterfly_state: Array[Dictionary] = []
## "", "down" (passed out) or "wake" (stretching awake). Set by game.gd.
var pose := "":
	set(v):
		if v != pose:
			pose = v
			_pose_t = 0.0
			if v == "wake":
				player.play(COLLAPSE_ANIM, true)
var _pose_t := 0.0
## AreaExit nodes and prey-spot markers (Marker2D, named after the spot).
var exit_nodes: Array[Node2D] = []
var prey_markers: Array[Marker2D] = []
## Mouse sprites and their "!" marks by mouse id; the landing ring; the
## mouse in Fern's mouth; her shadow while she leaps.
var mouse_nodes: Dictionary = {}
var mouse_marks: Dictionary = {}
var ring: Sprite2D
var mouth: Sprite2D
var fern_shadow: Sprite2D
var alert_bars: Node2D
var _hunt: Dictionary = {}
var _mouse_rustle_t: Dictionary = {}
var _palette_ui: Dictionary = {}


func setup(w, tuning: Dictionary, day_cycle = null) -> void:
	world = w
	day = day_cycle
	_rng.seed = 1234
	var p: Dictionary = tuning.get("player", {})
	walk_frame_px = float(p.get("walk_frame_px", walk_frame_px))
	idle_speed = float(p.get("idle_speed", idle_speed))
	var pr_t: Dictionary = tuning.get("prompt", {})
	bob_px = float(pr_t.get("bob_px", bob_px))
	bob_hz = float(pr_t.get("bob_hz", bob_hz))
	prompt_gap = float(pr_t.get("gap", prompt_gap))
	rank_gap = float(pr_t.get("rank_gap", rank_gap))
	_wind = tuning.get("wind", {})
	_amb = tuning.get("ambience", {})
	palette = JsonData.load_dict(PALETTE_PATH)
	var speakers := JsonData.load_dict(SPEAKERS_PATH)
	_make_materials()

	_forest = _layer("Forest")
	_forest.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_forest.draw.connect(_draw_forest)
	_ground = _layer("Ground")
	_decor = _layer("Decor")
	_sorted = _layer("Sorted")
	_sorted.y_sort_enabled = true
	_life = _layer("Life")
	_canopy_layer = _layer("Canopies")
	_sky = _layer("Sky")

	# Ground: the baked floor, the pond, decals, shadows.
	if world.ground_art != "":
		var floor_s := Sprite2D.new()
		floor_s.name = "Floor"
		floor_s.texture = AssetCatalog.texture(world.ground_art)
		floor_s.centered = false
		_ground.add_child(floor_s)
	if not world.pond.is_empty():
		pond = Sprite2D.new()
		pond.name = "Pond"
		pond.texture = AssetCatalog.texture(world.pond["art"])
		pond.centered = false
		pond.position = (world.pond["pos"] - pond.texture.get_size() / 2.0).round()
		var sh := AssetCatalog.shader("shader.pond")
		if sh != null:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("night_tint", Color(str(palette.get("pond_night", "#5c6aa0"))))
			pond.material = m
		_ground.add_child(pond)
	for g: Dictionary in world.ground:
		var decal := Sprite2D.new()
		decal.texture = AssetCatalog.texture(g["art"])
		decal.position = (g["pos"] as Vector2).round()
		decal.offset = -(decal.texture.get_size() / 2.0).floor()
		decal.centered = false
		decal.flip_h = g.get("flip", false)
		_ground.add_child(decal)
	for pr: Dictionary in world.props:
		if pr["shadow"] != "" and pr["trunk"]:
			var s := Sprite2D.new()
			s.texture = AssetCatalog.texture(pr["shadow"])
			var big := pr.has("canopy")
			s.position = (pr["pos"] + (Vector2(7, -1) if big else Vector2(2, -1))).round()
			s.offset = -(s.texture.get_size() / 2.0).floor()
			s.centered = false
			_ground.add_child(s)

	# Decor, grouped by art so neighbours share a texture and batch.
	var by_art: Dictionary = {}
	for d: Dictionary in world.decor:
		if not by_art.has(d["art"]):
			by_art[d["art"]] = []
		by_art[d["art"]].append(d)
	for art: String in by_art:
		var mat: Material = materials["flower" if art.contains("flower") else "grass"]
		for d: Dictionary in by_art[art]:
			var s := _sprite(art, d["pos"])
			s.material = mat
			_decor.add_child(s)

	# Sorted: props, NPCs, Fern, tall grass.
	for i in world.props.size():
		var pr: Dictionary = world.props[i]
		if pr["trunk"]:
			var s := _sprite(pr["art"], pr["pos"])
			s.flip_h = pr["flip"]
			if pr["lift"] > 0.0:
				# Sorted at pos, drawn lift px higher (the lichen on the rock).
				s.offset.y -= roundf(pr["lift"])
			if pr["sway"] != "" and not pr.has("canopy") and materials.has(pr["sway"]):
				s.material = materials[pr["sway"]]
			_sorted.add_child(s)
			if pr["rustle"]:
				_prop_rustler[i] = {"node": s, "kind": "bush", "t": 0.0, "h": float(s.texture.get_height()), "dir": 1.0}
		if pr.has("canopy"):
			var c := _sprite(pr["canopy"], pr["pos"] + pr["canopy_offset"])
			c.flip_h = pr["flip"]
			c.material = materials.get("canopy")
			_canopy_layer.add_child(c)
			canopies.append(c)
			_canopy_rects.append(Rect2(c.position + c.offset, c.texture.get_size()))
	if not world.pile.is_empty():
		pile = PileScene.instantiate()
		pile.setup(world.pile)
		_sorted.add_child(pile)
		if world.pile["shadow"] != "":
			var ps := Sprite2D.new()
			ps.texture = AssetCatalog.texture(world.pile["shadow"])
			ps.position = (world.pile["pos"] + Vector2(2, -1)).round()
			ps.offset = -(ps.texture.get_size() / 2.0).floor()
			ps.centered = false
			_ground.add_child(ps)
	if pond != null:
		ripple = Sprite2D.new()
		ripple.name = "Ripple"
		ripple.texture = AssetCatalog.texture(RIPPLE_KEY)
		ripple.hframes = 3
		ripple.visible = false
		_ground.add_child(ripple)
	for npc: Dictionary in world.npcs:
		var n: Node2D = NpcScene.instantiate()
		n.setup(npc, speakers.get(npc["id"], {}), tuning)
		npc_nodes[npc["id"]] = n
		_sorted.add_child(n)
	player = CatAnim.new()
	player.name = "Player"
	player.setup(PLAYER_ID)
	player.position = world.player_pos.round()
	_sorted.add_child(player)
	mouth = Sprite2D.new()
	mouth.name = "Mouth"
	mouth.texture = AssetCatalog.texture("life.mouse_carried")
	mouth.centered = false
	mouth.offset = -(mouth.texture.get_size() / 2.0).floor()
	mouth.visible = false
	player.add_child(mouth)
	fern_shadow = Sprite2D.new()
	fern_shadow.name = "FernShadow"
	fern_shadow.texture = AssetCatalog.texture("shadow.s")
	fern_shadow.centered = false
	fern_shadow.offset = -(fern_shadow.texture.get_size() / 2.0).floor()
	fern_shadow.visible = false
	_ground.add_child(fern_shadow)
	for blade: Dictionary in world.tall_grass:
		var s := _sprite(blade["art"], blade["pos"])
		s.flip_h = blade["flip"]
		s.material = materials["grass"]
		_sorted.add_child(s)
		_rustlers.append({"node": s, "kind": "grass", "t": 0.0, "h": float(s.texture.get_height()), "dir": 1.0})

	_make_markers()
	_make_life()
	_make_sky()

	grade = CanvasModulate.new()
	grade.name = "Grade"
	add_child(grade)
	overlay = CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.follow_viewport_enabled = true
	add_child(overlay)
	_make_fireflies()
	paw = Sprite2D.new()
	paw.name = "Paw"
	paw.texture = AssetCatalog.texture(PAW_KEY)
	paw.centered = false
	paw.visible = false
	overlay.add_child(paw)
	_hunt = tuning.get("hunt", {})
	_palette_ui = palette.get("ui", {})
	ring = Sprite2D.new()
	ring.name = "PounceRing"
	ring.texture = AssetCatalog.texture("ui.pounce_ring")
	ring.centered = false
	ring.offset = -(ring.texture.get_size() / 2.0).floor()
	ring.visible = false
	# Under the mouse (the Ground layer), so it never hides it.
	_ground.add_child(ring)
	alert_bars = Node2D.new()
	alert_bars.name = "AlertBars"
	alert_bars.draw.connect(_draw_alert_bars)
	overlay.add_child(alert_bars)
	meow = Sprite2D.new()
	meow.name = "Meow"
	meow.texture = AssetCatalog.texture(MEOW_KEY)
	meow.hframes = maxi(1, meow.texture.get_width() / maxi(1, meow.texture.get_height()))
	meow.centered = false
	meow.visible = false
	overlay.add_child(meow)
	for id in [PLAYER_ID] + npc_nodes.keys():
		var mark := Sprite2D.new()
		mark.name = "Rank_" + str(id)
		mark.centered = false
		mark.visible = false
		overlay.add_child(mark)
		rank_marks[id] = mark
	refresh_ranks()
	GameState.rank_changed.connect(_on_rank_changed)
	sync()


## Exits (AreaExit nodes, Inspector-editable) and prey spots (empty
## Marker2D nodes for now: mice come next milestone).
func _make_markers() -> void:
	var markers := _layer("Markers")
	for e: Dictionary in world.exits:
		var n: Node2D = ExitScene.instantiate()
		n.setup(e)
		markers.add_child(n)
		exit_nodes.append(n)
	for ps: Dictionary in world.prey_spots:
		var m := Marker2D.new()
		m.name = "PreySpot_" + str(ps["id"])
		m.position = ps["pos"]
		m.set_meta("prey_spot", ps["id"])
		markers.add_child(m)
		prey_markers.append(m)
	# Named places for later systems (MeetingSpot, DeputySpot; GatherArea
	# is a Marker2D at the rect's top-left with its size in meta "size").
	for n: String in world.markers:
		var m := Marker2D.new()
		m.name = n
		m.position = world.markers[n]
		markers.add_child(m)
	for n: String in world.zones:
		var r: Rect2 = world.zones[n]
		var m := Marker2D.new()
		m.name = n
		m.position = r.position
		m.set_meta("size", r.size)
		markers.add_child(m)


func _layer(n: String) -> Node2D:
	var l := Node2D.new()
	l.name = n
	add_child(l)
	return l


func _make_materials() -> void:
	var sh := AssetCatalog.shader("shader.sway")
	if sh == null:
		for k in ["grass", "flower", "bush", "canopy"]:
			materials[k] = null
		return
	for k in ["grass", "flower", "bush", "canopy"]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("amp_px", float(_wind.get(k + "_px", 1.0)))
		m.set_shader_parameter("speed", float(_wind.get("speed", 1.4)) * (0.8 if k == "canopy" else 1.0))
		m.set_shader_parameter("wavelength", float(_wind.get("wavelength", 110.0)))
		m.set_shader_parameter("gust_every", float(_wind.get("gust_every", 7.0)))
		materials[k] = m


func _pal(key: String, fallback: String) -> Color:
	return Color(str(palette.get(key, fallback)))


func _make_life() -> void:
	var cols: Array = palette.get("butterfly", ["#ffffff"])
	var spots: Array[Vector2] = []
	for d: Dictionary in world.decor:
		if str(d["art"]).contains("flower"):
			spots.append(d["pos"])
	for i in int(_amb.get("butterflies", 4)):
		var b := Sprite2D.new()
		b.name = "Butterfly%d" % i
		b.texture = AssetCatalog.texture("life.butterfly")
		b.hframes = 2
		b.centered = true
		b.modulate = Color(str(cols[i % cols.size()]))
		var home: Vector2 = spots[_rng.randi_range(0, spots.size() - 1)] if not spots.is_empty() else world.size / 2.0
		_butterfly_state.append({"pos": home + Vector2(_rng.randf_range(-20, 20), -10), "target": home, "phase": _rng.randf() * TAU, "spots": spots})
		_life.add_child(b)
		butterflies.append(b)


func _make_sky() -> void:
	for i in int(_amb.get("clouds", 3)):
		var c := Sprite2D.new()
		c.name = "Cloud%d" % i
		c.texture = AssetCatalog.texture("sky.cloud_shadow")
		c.centered = false
		var lim: Rect2 = world.camera_bounds()
		c.position = Vector2(lim.position.x + lim.size.x * (float(i) / maxf(1, int(_amb.get("clouds", 3)))) + _rng.randf_range(-40, 40),
			lim.position.y + _rng.randf_range(0, lim.size.y - 60)).round()
		_sky.add_child(c)
		clouds.append(c)
	bird = Sprite2D.new()
	bird.name = "Bird"
	bird.texture = AssetCatalog.texture("sky.bird_shadow")
	bird.hframes = 2
	bird.visible = false
	_sky.add_child(bird)
	_bird_wait = _rng.randf_range(2.0, 5.0)
	pollen = CPUParticles2D.new()
	pollen.name = "Pollen"
	pollen.amount = maxi(1, int(_amb.get("pollen", 14)))
	pollen.lifetime = 7.0
	pollen.preprocess = 7.0
	pollen.local_coords = false
	pollen.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	pollen.direction = Vector2(1, -0.3)
	pollen.spread = 40.0
	pollen.gravity = Vector2(0, -1.5)
	pollen.initial_velocity_min = 3.0
	pollen.initial_velocity_max = 8.0
	pollen.color = _pal("pollen", "#fff4d0")
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 0.9))
	ramp.add_point(0.8, Color(1, 1, 1, 0.7))
	pollen.color_ramp = ramp
	_sky.add_child(pollen)


func _make_fireflies() -> void:
	fireflies = CPUParticles2D.new()
	fireflies.name = "Fireflies"
	fireflies.amount = maxi(1, int(_amb.get("fireflies", 26)))
	fireflies.texture = AssetCatalog.texture("life.firefly")
	fireflies.lifetime = 5.0
	fireflies.local_coords = false
	fireflies.emitting = false
	fireflies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fireflies.direction = Vector2(0, -1)
	fireflies.spread = 70.0
	fireflies.gravity = Vector2(0, -2.0)
	fireflies.initial_velocity_min = 2.0
	fireflies.initial_velocity_max = 7.0
	fireflies.orbit_velocity_min = -0.03
	fireflies.orbit_velocity_max = 0.03
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	for pt in [[0.15, 1.0], [0.3, 0.3], [0.45, 1.0], [0.6, 0.45], [0.75, 1.0]]:
		ramp.add_point(pt[0], Color(1, 1, 1, pt[1]))
	fireflies.color_ramp = ramp
	overlay.add_child(fireflies)


func _draw_forest() -> void:
	if world == null or world.forest_art == "":
		return
	var tex := AssetCatalog.texture(world.forest_art)
	var r: Rect2 = world.camera_bounds().grow(FOREST_REACH)
	r.position = (r.position / tex.get_size()).floor() * tex.get_size()
	_forest.draw_texture_rect(tex, r, true)


## Copies the world state onto the sprites. Positions are whole pixels.
func sync(dt: float = 0.0) -> void:
	_t += dt
	player.position = world.player_pos.round() - Vector2(0, roundf(world.leap_height()))
	player.flip_h = world.facing < 0
	_sync_player(dt)
	_sync_hunt(dt)
	for npc: Dictionary in world.npcs:
		var id: String = npc["id"]
		npc_nodes[id].sync(npc, dt, world.focus_id == id, world.talk_id == id)
	if pile != null:
		pile.sync(world.pile)
	_sync_ripple()
	var focus: String = world.focus_id
	paw.visible = focus != "" and not world.is_talking() and not world.is_busy() and not world.is_leaping()
	if paw.visible:
		var head := focus_head()
		var bob := roundf((0.5 + 0.5 * sin(_t * TAU * bob_hz)) * bob_px)
		# Over the cat's rank symbol, if it has one.
		var mark: Sprite2D = rank_marks.get(focus)
		if mark != null and mark.texture != null:
			head.y -= mark.texture.get_height() + rank_gap
		paw.position = (head - Vector2(floorf(paw.texture.get_width() / 2.0), paw.texture.get_height() + prompt_gap + bob)).round()
	_sync_meow(dt)
	_sync_ranks()
	_sync_rustle(dt)
	_sync_canopies()
	_sync_time()
	if dt > 0.0:
		_sync_life(dt)
		_sync_sky(dt)


## Fern moving through tall grass or along a bush shakes it briefly.
func _sync_rustle(dt: float) -> void:
	var moving: bool = world.speed() >= idle_speed
	var feet: Vector2 = world.player_pos
	var dur := float(_wind.get("rustle_s", 0.45))
	var started := ""
	if moving:
		for r in _rustlers:
			var n: Sprite2D = r["node"]
			if r["t"] <= dur * 0.3 and absf(n.position.x - feet.x) <= 6.0 and absf(n.position.y - feet.y) <= 4.0:
				r["t"] = dur
				r["dir"] = signf(world.player_vel.x) if world.player_vel.x != 0.0 else 1.0
				started = "grass"
		var bi: int = world.brushing_prop()
		if bi >= 0 and _prop_rustler.has(bi) and _prop_rustler[bi]["t"] <= dur * 0.3:
			_prop_rustler[bi]["t"] = dur
			_prop_rustler[bi]["dir"] = signf(world.player_vel.x) if world.player_vel.x != 0.0 else 1.0
			started = "bush"
	for r in _rustlers + _prop_rustler.values():
		if r["t"] <= 0.0:
			continue
		r["t"] = maxf(0.0, r["t"] - dt)
		var k: float = r["t"] / dur
		var px := roundf(sin(k * TAU * 1.5) * k * float(_wind.get("rustle_px", 2.0)) * r["dir"])
		(r["node"] as Sprite2D).skew = atan(px / maxf(1.0, r["h"]))
	if started != "":
		rustled.emit(started)


## A canopy over Fern goes see-through so she never disappears.
func _sync_canopies() -> void:
	var fern := player.body_rect()
	var fade := float(_amb.get("canopy_fade", 0.55))
	for i in canopies.size():
		var a := fade if _canopy_rects[i].intersects(fern) else 1.0
		if canopies[i].modulate.a != a:
			canopies[i].modulate.a = a


func _sync_time() -> void:
	var night := 0.0
	var dayness := 1.0
	var g := _pal_grade("afternoon")
	if day != null:
		g = day.blend(_pal_grade("afternoon"), _pal_grade("dusk"), _pal_grade("night"))
		night = day.night_amount()
		dayness = day.day_amount()
	grade.color = g
	if pond != null and pond.material != null:
		(pond.material as ShaderMaterial).set_shader_parameter("night", night)
	fireflies.emitting = night > 0.25
	pollen.emitting = dayness > 0.3
	var view := camera_rect
	pollen.position = view.get_center()
	pollen.emission_rect_extents = view.size / 2.0
	fireflies.position = view.get_center() + Vector2(0, view.size.y * 0.1)
	fireflies.emission_rect_extents = view.size * Vector2(0.5, 0.4)
	for b in butterflies:
		b.modulate.a = dayness
		b.visible = dayness > 0.02
	for c in clouds:
		c.modulate.a = dayness
	bird.modulate.a = dayness


func _pal_grade(stage: String) -> Color:
	if world != null and world.grade.has(stage):
		return Color(str(world.grade[stage]))
	return Color(str(palette.get("grade", {}).get(stage, "#ffffff")))


## Butterflies flutter from flower to flower.
func _sync_life(dt: float) -> void:
	var speed := float(_amb.get("butterfly_speed", 16))
	for i in butterflies.size():
		var st: Dictionary = _butterfly_state[i]
		var pos: Vector2 = st["pos"]
		var target: Vector2 = st["target"]
		if pos.distance_to(target) < 4.0:
			var spots: Array[Vector2] = st["spots"]
			var near: Array[Vector2] = []
			for s in spots:
				if s.distance_to(pos) < 90.0 and s.distance_to(pos) > 10.0:
					near.append(s)
			var pool := near if not near.is_empty() else spots
			st["target"] = (pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else world.size / 2.0) + Vector2(0, -6)
		st["phase"] += dt * 9.0
		var dir := (target - pos).normalized()
		var wobble := Vector2(-dir.y, dir.x) * sin(st["phase"] * 0.7) * 10.0 + Vector2(0, sin(st["phase"] * 1.3) * 6.0)
		pos += (dir * speed + wobble) * dt
		st["pos"] = pos
		var b := butterflies[i]
		b.position = pos.round()
		b.frame = int(st["phase"] / PI) % 2
		b.flip_h = dir.x < 0.0


## Cloud shadows drift across; now and then a bird's shadow flies over.
func _sync_sky(dt: float) -> void:
	var lim: Rect2 = world.camera_bounds()
	var speed := float(_amb.get("cloud_speed", 5))
	for c in clouds:
		var fx: float = float(c.get_meta("fx", c.position.x)) + speed * dt
		if fx > lim.end.x:
			fx = lim.position.x - c.texture.get_width()
			c.position.y = roundf(lim.position.y + _rng.randf_range(0, lim.size.y - 60))
		c.set_meta("fx", fx)
		c.position.x = roundf(fx)
	if bird.visible:
		var p: Vector2 = bird.get_meta("pos") + _bird_vel * dt
		bird.set_meta("pos", p)
		bird.position = p.round()
		bird.frame = int(_t * 5.0) % 2
		if not camera_rect.grow(60).has_point(p):
			bird.visible = false
			var every: Array = _amb.get("bird_every", [8, 16])
			_bird_wait = _rng.randf_range(float(every[0]), float(every[1]))
	elif day == null or day.day_amount() > 0.5:
		_bird_wait -= dt
		if _bird_wait <= 0.0:
			var v := camera_rect
			var from_left := _rng.randf() < 0.5
			var start := Vector2(v.position.x - 30 if from_left else v.end.x + 30, v.position.y + _rng.randf_range(0.1, 0.8) * v.size.y)
			var bspeed := float(_amb.get("bird_speed", 95))
			_bird_vel = Vector2(bspeed if from_left else -bspeed, _rng.randf_range(-0.25, 0.25) * bspeed)
			bird.flip_h = not from_left
			bird.set_meta("pos", start)
			bird.position = start.round()
			bird.visible = true


## Fern: walk / run by distance walked; standing still she idles, and after
## cats.json fidget_after_s plays a fidget (lick, itch, stretch) in turn.
## A meow plays out unless she starts moving.
func _sync_player(dt: float) -> void:
	if pose == "down":
		# Sinks into the crouch, then lies still.
		_pose_t += dt
		player.hold(COLLAPSE_ANIM, mini(int(_pose_t * COLLAPSE_FPS), COLLAPSE_LOW_FRAME))
		_still = 0.0
		return
	if pose == "wake":
		player.step(dt)
		_still = 0.0
		# Walking off mid-stretch ends it.
		if player.finished() or world.speed() >= idle_speed:
			pose = ""
			player.play("idle")
		return
	if world.is_leaping():
		# Mid-air: stretched out like a trot stride.
		player.hold("run", 2)
		_still = 0.0
		return
	if world.is_busy() and world.action in ["catch", "stumble", "drop"]:
		_still = 0.0
		_action_seen = world.action
		match world.action:
			"catch":
				# A tiny happy bounce.
				var k: float = world.action_t / maxf(0.01, world.hunt_tuning.catch_s)
				player.play("idle")
				player.step(dt)
				player.position.y -= roundf(sin(k * PI * 2.0) * 2.0) if k > 0.5 else 0.0
			"stumble":
				player.hold(COLLAPSE_ANIM, 1)
			_:
				player.play("idle")
				player.step(dt)
		return
	if world.is_busy():
		# Eating or drinking: lap / chew (the lick animation) until done.
		if _action_seen != world.action:
			_action_seen = world.action
			player.play(ACTION_ANIM, true)
		_still = 0.0
		player.step(dt)
		if player.finished():
			player.play(ACTION_ANIM, true)
		return
	if world.crouching:
		# Stalking: low, shuffling between the two lowest stretch frames.
		_still = 0.0
		if world.speed() >= idle_speed:
			player.hold(COLLAPSE_ANIM, 1 + int(world.distance / 4.0) % 2)
		else:
			player.hold(COLLAPSE_ANIM, COLLAPSE_LOW_FRAME)
		return
	if _action_seen != "":
		_action_seen = ""
		player.play("idle")
	if world.speed() >= idle_speed:
		_still = 0.0
		player.show_stride("run" if world.running else "walk", world.distance)
		return
	var spec := CatAnim.cat_spec(PLAYER_ID)
	var fidgets: Array = spec.get("fidgets", [])
	if (player.anim == "meow" or player.anim in fidgets) and not player.finished():
		if player.anim != "meow" and world.is_talking():
			player.play("idle")
		player.step(dt)
		return
	_still += dt
	if not world.is_talking() and not fidgets.is_empty() and _still >= float(spec.get("fidget_after_s", 5.0)):
		_still = 0.0
		player.play(fidgets[_next_fidget % fidgets.size()], true)
		_next_fidget += 1
		return
	player.play("idle")
	player.step(dt)


## Mice, their "!" and alert bars, the landing ring, the mouse in Fern's
## mouth, her leap shadow, and grass shaking over feeding mice.
func _sync_hunt(dt: float) -> void:
	var carrying: bool = world.carrying() != ""
	mouth.visible = carrying
	if carrying:
		var mp: Array = _hunt.get("mouth_px", [9, -6])
		mouth.position = Vector2(float(mp[0]) * world.facing, float(mp[1]))
		mouth.flip_h = world.facing < 0
	fern_shadow.visible = world.is_leaping()
	if fern_shadow.visible:
		fern_shadow.position = (world.player_pos + Vector2(0, -1)).round()
	var target: Dictionary = world.pounce_target()
	ring.visible = not target.is_empty()
	if ring.visible:
		ring.position = (target["pos"] as Vector2).round() + Vector2(0, -1)
	alert_bars.queue_redraw()
	if world.hunt == null:
		return
	var seen := {}
	var every: Array = _hunt.get("rustle_every", [0.9, 1.8])
	for m: Dictionary in world.hunt.mice:
		var id: int = m["id"]
		seen[id] = true
		if not mouse_nodes.has(id):
			var s := Sprite2D.new()
			s.name = "Mouse%d" % id
			s.texture = AssetCatalog.texture("life.mouse")
			s.hframes = 5
			s.centered = false
			s.offset = Vector2(-6, -8)
			_sorted.add_child(s)
			mouse_nodes[id] = s
			var mk := Sprite2D.new()
			mk.name = "Alert%d" % id
			mk.texture = AssetCatalog.texture("ui.alert_mark")
			mk.centered = false
			overlay.add_child(mk)
			mouse_marks[id] = mk
			_mouse_rustle_t[id] = _rng.randf_range(0.2, 1.0)
		var sp: Sprite2D = mouse_nodes[id]
		var pos: Vector2 = (m["pos"] as Vector2).round()
		sp.position = pos
		sp.flip_h = m["facing"] < 0
		match m["state"]:
			"feed":
				# Nibbles in short bursts.
				sp.frame = int(_t * 6.0) % 2 if int(_t * 1.3 + id) % 2 == 0 else 0
			"look":
				sp.frame = 2
			_:
				sp.frame = 3 + int(_t * 12.0) % 2
		var mk: Sprite2D = mouse_marks[id]
		mk.visible = m["state"] == "look"
		if mk.visible:
			var bob := roundf(0.5 + 0.5 * sin(_t * TAU * 2.0))
			mk.position = pos + Vector2(float(m["facing"]) * 3.0 - 1.0, -22.0 - bob)
		# The grass over a feeding mouse shakes now and then.
		if m["state"] != "look" and dt > 0.0:
			_mouse_rustle_t[id] -= dt
			if _mouse_rustle_t[id] <= 0.0:
				_mouse_rustle_t[id] = _rng.randf_range(float(every[0]), float(every[1]))
				_shake_grass_near(pos, 12.0)
	for id in mouse_nodes.keys():
		if not seen.has(id):
			mouse_nodes[id].queue_free()
			mouse_marks[id].queue_free()
			mouse_nodes.erase(id)
			mouse_marks.erase(id)
			_mouse_rustle_t.erase(id)


## Gives the tall-grass blades near `p` a rustle (no sound: a mouse is quiet).
func _shake_grass_near(p: Vector2, radius: float) -> void:
	var dur := float(_wind.get("rustle_s", 0.45))
	for r in _rustlers:
		var n: Sprite2D = r["node"]
		if n.position.distance_to(p) <= radius and r["t"] <= 0.0:
			r["t"] = dur
			r["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0


## A small bar over each mouse near Fern: how close it is to bolting.
func _draw_alert_bars() -> void:
	if world == null or world.hunt == null:
		return
	var show := float(world.hunt_tuning.show_px)
	var back := Color(str(_palette_ui.get("bar_back", "#3a3444")))
	var calm := Color(str(_palette_ui.get("select", "#ffd873")))
	var scared := Color(str(palette.get("berry", "#d8465a")))
	var ink := Color(str(palette.get("ink", "#1c1824")))
	for m: Dictionary in world.hunt.mice:
		if m["state"] == "flee" or world.player_pos.distance_to(m["pos"]) > show:
			continue
		var at: Vector2 = (m["pos"] as Vector2).round() + Vector2(-6, -12)
		alert_bars.draw_rect(Rect2(at, Vector2(12, 3)), ink)
		alert_bars.draw_rect(Rect2(at + Vector2(1, 1), Vector2(10, 1)), back)
		var w := roundf(10.0 * float(m["alert"]))
		if w > 0.0:
			alert_bars.draw_rect(Rect2(at + Vector2(1, 1), Vector2(w, 1)), calm.lerp(scared, float(m["alert"])))


## Picks each cat's rank symbol texture (none: hidden).
func refresh_ranks() -> void:
	var names = GameState.state.names
	for id: String in rank_marks:
		var key: String = names.rank_icon(GameState.get_cat_rank(id))
		var mark: Sprite2D = rank_marks[id]
		mark.texture = AssetCatalog.texture(key) if key != "" else null
	_sync_ranks()


func _on_rank_changed(_id: String, _rank: String) -> void:
	refresh_ranks()


## Rank symbols sit just over each cat's head.
func _sync_ranks() -> void:
	for id: String in rank_marks:
		var mark: Sprite2D = rank_marks[id]
		mark.visible = mark.texture != null
		if not mark.visible:
			continue
		var head: Vector2 = player.position + Vector2(0, player.top_y()) if id == PLAYER_ID else npc_head(id)
		mark.position = (head - Vector2(floorf(mark.texture.get_width() / 2.0), mark.texture.get_height() + rank_gap)).round()


## A cat starts speaking: it meows (if it can in its pose) and a "meow"
## puff pops over its head. `who` is a speaker id; others are ignored.
func speak(who: String) -> void:
	if who == PLAYER_ID:
		player.play("meow", true)
	elif npc_nodes.has(who) and npc_nodes[who].cat != null:
		npc_nodes[who].speak()
	else:
		return
	_meow_who = who
	_meow_t = float(CatAnim.data().get("meow_vfx_s", 0.9))


func _sync_meow(dt: float) -> void:
	_meow_t = maxf(0.0, _meow_t - dt)
	meow.visible = _meow_t > 0.0 and _meow_who != ""
	if not meow.visible:
		return
	var head := player.position + Vector2(0, player.top_y()) if _meow_who == PLAYER_ID else npc_head(_meow_who)
	var w := meow.texture.get_width() / meow.hframes
	var face := -1.0 if (player.flip_h if _meow_who == PLAYER_ID else npc_nodes[_meow_who].sprite.flip_h) else 1.0
	# Over the head, a little towards the way the cat faces (its mouth).
	meow.position = (head + Vector2(face * 6.0 - w / 2.0, -meow.texture.get_height() - 1.0)).round()
	meow.flip_h = face < 0.0
	var shown := float(CatAnim.data().get("meow_vfx_s", 0.9)) - _meow_t
	meow.frame = mini(int(shown * float(CatAnim.data().get("meow_vfx_fps", 8))), meow.hframes - 1)


## Where the interact prompt goes (world px): over the focused NPC's head,
## over the pile, or over the water's edge nearest Fern.
func focus_head() -> Vector2:
	match world.focus_kind():
		"pile":
			return pile.head() if pile != null else world.pile["pos"]
		"pond":
			return world.pond_point() + Vector2(0, -2)
		"npc":
			return npc_head(world.focus_id)
		"spot":
			return world.spot_by_id(world.focus_id)["prompt"]
	return Vector2.ZERO


## Rings spread on the water while Fern drinks.
func _sync_ripple() -> void:
	if ripple == null:
		return
	ripple.visible = world.action == "drink"
	if not ripple.visible:
		return
	var span: float = maxf(0.01, world.drink_s)
	var k: float = 1.0 - world.action_t / span
	ripple.frame = int(k * 6.0) % 3
	# Just inside the water, below Fern's mouth.
	var r: Rect2 = world.pond["rect"]
	var at: Vector2 = world.pond_point()
	at.x = clampf(at.x + world.facing * 4.0, r.position.x + 4.0, r.end.x - 4.0)
	at.y = clampf(at.y, r.position.y + 3.0, r.end.y - 3.0)
	ripple.position = at.round()


## Top-centre of an NPC's art, in world pixels.
func npc_head(id: String) -> Vector2:
	var n: Node2D = npc_nodes.get(id)
	return n.head() if n != null else Vector2.ZERO


## A sprite whose origin is the art's feet (bottom-centre of the opaque
## pixels). Feet rows are cached per texture (get_image() copies).
static var _bottoms: Dictionary = {}


func _sprite(key: String, feet: Vector2, hframes: int = 1) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = AssetCatalog.texture(key)
	s.centered = false
	s.hframes = hframes
	var frame_size := Vector2(s.texture.get_width() / hframes, s.texture.get_height())
	if not _bottoms.has(key):
		var bottom := frame_size.y
		var img := s.texture.get_image()
		if img != null:
			bottom = img.get_used_rect().end.y
		_bottoms[key] = bottom
	s.offset = Vector2(-floorf(frame_size.x / 2.0), -float(_bottoms[key]))
	s.position = feet.round()
	return s

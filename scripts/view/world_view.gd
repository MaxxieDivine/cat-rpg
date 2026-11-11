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

signal rustled(kind: String)

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const NpcScene := preload("res://scenes/npc.tscn")
const CAT_KEY := "cat.sheet"
const CAT_FRAMES := 3
const PAW_KEY := "ui.paw"
const SPEAKERS_PATH := "res://data/speakers.json"
const PALETTE_PATH := "res://data/palette.json"
## How far past the camera bounds the forest tile is drawn (world px).
const FOREST_REACH := 1400.0

var world
var day  # day_cycle.gd, or null
var player: Sprite2D
## The talk prompt over the focused NPC.
var paw: Sprite2D
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
	for npc: Dictionary in world.npcs:
		var n: Node2D = NpcScene.instantiate()
		n.setup(npc, speakers.get(npc["id"], {}), tuning)
		npc_nodes[npc["id"]] = n
		_sorted.add_child(n)
	player = _sprite(CAT_KEY, world.player_pos, CAT_FRAMES)
	player.name = "Player"
	_sorted.add_child(player)
	for blade: Dictionary in world.tall_grass:
		var s := _sprite(blade["art"], blade["pos"])
		s.flip_h = blade["flip"]
		s.material = materials["grass"]
		_sorted.add_child(s)
		_rustlers.append({"node": s, "kind": "grass", "t": 0.0, "h": float(s.texture.get_height()), "dir": 1.0})

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
	sync()


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
	player.position = world.player_pos.round()
	player.flip_h = world.facing < 0
	if world.speed() < idle_speed:
		player.frame = 0
	else:
		player.frame = 1 + int(world.distance / walk_frame_px) % 2
	for npc: Dictionary in world.npcs:
		var id: String = npc["id"]
		npc_nodes[id].sync(npc, dt, world.focus_id == id, world.talk_id == id)
	var focus: String = world.focus_id
	paw.visible = focus != "" and not world.is_talking()
	if paw.visible:
		var head := npc_head(focus)
		var bob := roundf((0.5 + 0.5 * sin(_t * TAU * bob_hz)) * bob_px)
		paw.position = (head - Vector2(floorf(paw.texture.get_width() / 2.0), paw.texture.get_height() + prompt_gap + bob)).round()
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
	var fern := Rect2(player.position + player.offset, Vector2(player.texture.get_width() / CAT_FRAMES, player.texture.get_height()))
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

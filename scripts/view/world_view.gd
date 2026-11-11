extends Node2D
## Draws a World (scripts/core/world.gd) in world pixels. Lives inside the
## small SubViewport. Only shows state; never changes it.
## NPCs are scenes/npc.tscn instances; the paw-print prompt bobs over the
## one NPC Fern can talk to (the nearest in range), hidden while talking.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const NpcScene := preload("res://scenes/npc.tscn")
const CAT_KEY := "cat.sheet"
const CAT_FRAMES := 3
const PAW_KEY := "ui.paw"
const SPEAKERS_PATH := "res://data/speakers.json"

var world
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

var _ground: Node2D
var _sorted: Node2D
var _t := 0.0


func setup(w, tuning: Dictionary) -> void:
	world = w
	var p: Dictionary = tuning.get("player", {})
	walk_frame_px = float(p.get("walk_frame_px", walk_frame_px))
	idle_speed = float(p.get("idle_speed", idle_speed))
	var pr_t: Dictionary = tuning.get("prompt", {})
	bob_px = float(pr_t.get("bob_px", bob_px))
	bob_hz = float(pr_t.get("bob_hz", bob_hz))
	prompt_gap = float(pr_t.get("gap", prompt_gap))
	var speakers := JsonData.load_dict(SPEAKERS_PATH)

	_ground = Node2D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_sorted = Node2D.new()
	_sorted.name = "Sorted"
	_sorted.y_sort_enabled = true
	add_child(_sorted)

	for g: Dictionary in world.ground:
		var decal := Sprite2D.new()
		decal.texture = AssetCatalog.texture(g["art"])
		decal.position = (g["pos"] as Vector2).round()
		decal.offset = -(decal.texture.get_size() / 2.0).floor()
		decal.centered = false
		_ground.add_child(decal)
	for d: Dictionary in world.decor:
		_ground.add_child(_sprite(d["art"], d["pos"]))
	for pr: Dictionary in world.props:
		_sorted.add_child(_sprite(pr["art"], pr["pos"]))
	for npc: Dictionary in world.npcs:
		var n: Node2D = NpcScene.instantiate()
		n.setup(npc, speakers.get(npc["id"], {}), tuning)
		npc_nodes[npc["id"]] = n
		_sorted.add_child(n)
	player = _sprite(CAT_KEY, world.player_pos, CAT_FRAMES)
	player.name = "Player"
	_sorted.add_child(player)

	paw = Sprite2D.new()
	paw.name = "Paw"
	paw.texture = AssetCatalog.texture(PAW_KEY)
	paw.centered = false
	paw.z_index = 10
	paw.visible = false
	add_child(paw)
	sync()


func _draw() -> void:
	if world != null:
		draw_rect(Rect2(Vector2.ZERO, world.size), world.background)


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


## Top-centre of an NPC's art, in world pixels.
func npc_head(id: String) -> Vector2:
	var n: Node2D = npc_nodes.get(id)
	return n.head() if n != null else Vector2.ZERO


## A sprite whose origin is the art's feet (bottom-centre of the opaque pixels).
func _sprite(key: String, feet: Vector2, hframes: int = 1) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = AssetCatalog.texture(key)
	s.centered = false
	s.hframes = hframes
	var frame_size := Vector2(s.texture.get_width() / hframes, s.texture.get_height())
	var bottom := frame_size.y
	var img := s.texture.get_image()
	if img != null:
		bottom = img.get_used_rect().end.y
	s.offset = Vector2(-floorf(frame_size.x / 2.0), -bottom)
	s.position = feet.round()
	return s

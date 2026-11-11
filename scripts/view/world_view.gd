extends Node2D
## Draws a World (scripts/core/world.gd) in world pixels. Lives inside the
## 480x270 SubViewport. Only shows state; never changes it.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const CAT_KEY := "cat.sheet"
const CAT_FRAMES := 3

var world
var player: Sprite2D
var walk_frame_px := 7.0
var idle_speed := 4.0
## Sprites by NPC id.
var npc_sprites: Dictionary = {}

var _ground: Node2D
var _sorted: Node2D


func setup(w, tuning: Dictionary) -> void:
	world = w
	var p: Dictionary = tuning.get("player", {})
	walk_frame_px = float(p.get("walk_frame_px", walk_frame_px))
	idle_speed = float(p.get("idle_speed", idle_speed))

	_ground = Node2D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_sorted = Node2D.new()
	_sorted.name = "Sorted"
	_sorted.y_sort_enabled = true
	add_child(_sorted)

	for d: Dictionary in world.decor:
		_ground.add_child(_sprite(d["art"], d["pos"]))
	for pr: Dictionary in world.props:
		_sorted.add_child(_sprite(pr["art"], pr["pos"]))
	for npc: Dictionary in world.npcs:
		var s := _sprite(npc["art"], npc["pos"])
		s.name = "Npc_" + npc["id"]
		npc_sprites[npc["id"]] = s
		_sorted.add_child(s)
	player = _sprite(CAT_KEY, world.player_pos, CAT_FRAMES)
	player.name = "Player"
	_sorted.add_child(player)
	sync()


func _draw() -> void:
	if world != null:
		draw_rect(Rect2(Vector2.ZERO, world.size), world.background)


## Copies the world state onto the sprites. Positions are whole pixels.
func sync() -> void:
	player.position = world.player_pos.round()
	player.flip_h = world.facing < 0
	if world.speed() < idle_speed:
		player.frame = 0
	else:
		player.frame = 1 + int(world.distance / walk_frame_px) % 2


## Top-centre of an NPC's art, in world pixels (for bubbles and prompts).
func npc_head(id: String) -> Vector2:
	var s: Sprite2D = npc_sprites.get(id)
	if s == null:
		return Vector2.ZERO
	return s.position + Vector2(0, s.offset.y + _used_top(s))


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


func _used_top(s: Sprite2D) -> float:
	var img := s.texture.get_image()
	return float(img.get_used_rect().position.y) if img != null else 0.0

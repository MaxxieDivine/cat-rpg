extends Node2D
## One NPC in the meadow (scenes/npc.tscn). world_view.gd instances it per
## entry in world.json "npcs" and fills the exports from world.json and
## data/speakers.json. Its origin is the NPC's feet (y-sorted with the cat).
## Only shows state from the World core; never changes it.
##
## Behaviours (world.json "behavior"): "sit" blinks now and then, "lie"
## dozes and opens her eyes when Fern is near, "pace" walks its loop with a
## two-frame walk, "stand" just stands.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")

@export var npc_id := ""
@export var display_name := ""
## Voice blip pitch (1.0 = Fern).
@export var voice_pitch := 1.0
@export_file("*.json") var dialogue_file := ""
@export var art_key := ""
@export var frames := 1
@export var behavior := "stand"

var sprite: Sprite2D
var walk_frame_px := 7.0
## Seconds; drives blinking. Cosmetic only.
var _t := 0.0
var _phase := 0.0
## First opaque row of the art (for head()).
var _top := 0.0


func setup(npc: Dictionary, speaker: Dictionary, tuning: Dictionary) -> void:
	npc_id = npc["id"]
	art_key = npc["art"]
	frames = maxi(1, int(npc.get("frames", 1)))
	behavior = npc.get("behavior", "stand")
	dialogue_file = npc.get("dialogue", "")
	display_name = str(speaker.get("name", npc_id))
	voice_pitch = float(speaker.get("voice", {}).get("pitch", 1.0))
	walk_frame_px = float(tuning.get("player", {}).get("walk_frame_px", walk_frame_px))
	name = "Npc_" + npc_id
	_phase = float(npc_id.hash() % 1000) / 1000.0 * 3.0
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = AssetCatalog.texture(art_key)
	sprite.centered = false
	sprite.hframes = frames
	var frame_w := sprite.texture.get_width() / frames
	var bottom := float(sprite.texture.get_height())
	var img := sprite.texture.get_image()
	if img != null:
		bottom = img.get_used_rect().end.y
		_top = img.get_used_rect().position.y
	sprite.offset = Vector2(-floorf(frame_w / 2.0), -bottom)
	add_child(sprite)


## Copies the NPC's state onto the sprite. `near` = Fern is in talk range.
func sync(npc: Dictionary, dt: float, near: bool, talking: bool) -> void:
	_t += dt
	position = (npc["pos"] as Vector2).round()
	if behavior != "stand":
		sprite.flip_h = int(npc.get("facing", 1)) < 0
	var f := 0
	match behavior:
		"sit":
			# A short blink every few seconds; eyes open while talking.
			f = 1 if not talking and fmod(_t + _phase, 3.6) > 3.45 else 0
		"lie":
			f = 1 if near or talking else 0
		"pace":
			f = 1 + int(float(npc.get("distance", 0.0)) / walk_frame_px) % 2 if npc.get("moving", false) else 0
	sprite.frame = mini(f, frames - 1)


## Top-centre of the art's opaque pixels, in world pixels.
func head() -> Vector2:
	return position + Vector2(0, sprite.offset.y + _top)

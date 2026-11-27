extends Node2D
## One NPC in the meadow (scenes/npc.tscn). world_view.gd instances it per
## entry in world.json "npcs" and fills the exports from world.json and
## data/speakers.json. Its origin is the NPC's feet (y-sorted with the cat).
## Only shows state from the World core; never changes it.
##
## Cats listed in data/cats.json are animated (cat_anim.gd); anything else
## (the cow) is a plain sprite with world.json "frames".
##
## Behaviours (world.json "behavior"): "sit" sits and now and then plays a
## fidget (licks a paw, scratches); "lie" sleeps, lies with her head up when
## Fern is near and grooms if Fern lingers; "pace" walks its loop and idles
## at the corners; "stand" just stands. A cat that starts speaking meows if
## it has a meow animation (speak()). Any cat with a walk animation walks
## while it moves (patrol mates following Fern), and rests in its own pose
## when it stops. world.json "perch" stands it on
## something (the leader on the Leader's Rock).

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const CatAnim := preload("res://scripts/view/cat_anim.gd")

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
## The animated cat (null for plain sprites such as the cow).
var cat: CatAnim
## Seconds since the last fidget ended (animated cats).
var _idle := 0.0
var _next_fidget := 0
var _fidgets: Array = []
var _fidget_after := 4.0


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
	if CatAnim.has_cat(npc_id):
		cat = CatAnim.new()
		cat.name = "Sprite"
		cat.setup(npc_id)
		var spec := CatAnim.cat_spec(npc_id)
		_fidgets = spec.get("fidgets", [])
		_fidget_after = float(spec.get("fidget_after_s", _fidget_after))
		_idle = _phase
		# A layout may give a cat another resting pose (Wick lying in the
		# rogue camp: "rest": "sleep").
		var rest_anim := str(npc.get("rest", ""))
		if rest_anim != "":
			cat.set_rest(rest_anim)
		sprite = cat
		add_child(sprite)
		return
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
	# A cutscene may change the pose (Wick getting up: "pose" steps).
	behavior = str(npc.get("behavior", behavior))
	if cat != null:
		var r := str(npc.get("rest", ""))
		if r != "" and r != cat.rest:
			cat.set_rest(r)
	# A perched cat (the leader on the rock) is y-sorted at the ground
	# below it and drawn perch px higher.
	var perch := roundf(float(npc.get("perch", 0.0)))
	position = (npc["pos"] as Vector2).round() + Vector2(0, perch)
	sprite.position = Vector2(0, -perch)
	if behavior != "stand":
		sprite.flip_h = int(npc.get("facing", 1)) < 0
	if cat != null:
		_sync_cat(npc, dt, near, talking)
		return
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


func _sync_cat(npc: Dictionary, dt: float, near: bool, talking: bool) -> void:
	if cat.anim == "meow" and not cat.finished():
		cat.step(dt)
		return
	if npc.get("moving", false) and cat.has_anim("walk"):
		# Pacing, or walking with a patrol.
		cat.show_stride("walk", float(npc.get("distance", 0.0)))
		return
	if behavior == "lie" and not (near or talking):
		cat.hold(cat.rest, 0)
		_idle = 0.0
		return
	if cat.anim in _fidgets and not cat.finished():
		if talking:
			_rest(dt)
		else:
			cat.step(dt)
		return
	_idle += dt
	if not talking and not _fidgets.is_empty() and _idle >= _fidget_after:
		_idle = 0.0
		cat.play(_fidgets[_next_fidget % _fidgets.size()], true)
		_next_fidget += 1
		return
	_rest(dt)


## The resting pose for this behaviour: Sorrel awake = the last frame of
## lying down (head up).
func _rest(dt: float) -> void:
	if behavior == "lie" and cat.has_anim("lie_down"):
		cat.hold("lie_down", -1)
		return
	cat.play("idle" if behavior == "pace" and cat.has_anim("idle") else cat.rest)
	cat.step(dt)


## Starts speaking: a meow, if this cat has one.
func speak() -> void:
	if cat != null and cat.has_anim("meow"):
		cat.play("meow", true)


## Top-centre of the art's opaque pixels, in world pixels.
func head() -> Vector2:
	if cat != null:
		return position + sprite.position + Vector2(0, cat.top_y())
	return position + sprite.position + Vector2(0, sprite.offset.y + _top)

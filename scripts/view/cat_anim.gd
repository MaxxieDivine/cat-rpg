extends Sprite2D
## An animated cat from the Pet Cats Pack (data/cats.json): one sheet per
## animation (art key cat.<id>.<anim>), square frames in a row, facing right.
## The origin is the cat's feet. Animations are either time-driven (`fps`) or
## distance-driven (`stride_px`, see show_stride()); one-shots (`loops` > 0)
## report finished() when done. Cosmetic only: never touches game state.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const CATS_PATH := "res://data/cats.json"

static var _data: Dictionary = {}

var cat_id := ""
## The animation showing now ("" before the first play()).
var anim := ""
## The resting pose: the first anim in cats.json.
var rest := ""
var frame_px := 50
## name -> {"texture", "frames", "fps", "stride_px", "loops"}
var anims: Dictionary = {}
## Part of each frame to show (frame-local px); the whole frame by default.
var crop := Rect2()
var _time := 0.0
var _frame := 0
## Opaque top row of the resting pose (for head()).
var _top := 0.0


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JsonData.load_dict(CATS_PATH)
	return _data


static func has_cat(id: String) -> bool:
	return data().get("cats", {}).has(id)


static func cat_spec(id: String) -> Dictionary:
	return data().get("cats", {}).get(id, {})


func setup(id: String) -> void:
	cat_id = id
	var d := data()
	frame_px = int(d.get("frame_px", 50))
	var feet := float(d.get("feet_px", frame_px))
	var spec: Dictionary = cat_spec(id)
	for n: String in spec.get("anims", {}):
		var a: Dictionary = spec["anims"][n]
		var tex := AssetCatalog.texture("cat.%s.%s" % [id, n])
		anims[n] = {
			"texture": tex,
			"frames": maxi(1, tex.get_width() / frame_px),
			"fps": float(a.get("fps", 8.0)),
			"stride_px": float(a.get("stride_px", 0.0)),
			"loops": int(a.get("loops", 0)),
		}
		if rest == "":
			rest = n
	centered = false
	region_enabled = true
	crop = Rect2(0, 0, frame_px, frame_px)
	offset = Vector2(-floorf(frame_px / 2.0), -feet)
	if rest != "":
		var img: Image = anims[rest]["texture"].get_image()
		if img != null:
			_top = img.get_used_rect().position.y
		play(rest)


func has_anim(n: String) -> bool:
	return anims.has(n)


## Starts `n` from its first frame (or keeps it running if it already is,
## unless `restart`). Unknown names are ignored.
func play(n: String, restart := false) -> void:
	if not anims.has(n) or (n == anim and not restart):
		return
	anim = n
	texture = anims[n]["texture"]
	_time = 0.0
	_set_frame(0)


## Advances a time-driven animation.
func step(dt: float) -> void:
	if anim == "":
		return
	_time += dt
	var a: Dictionary = anims[anim]
	var f := int(_time * a["fps"])
	var n: int = a["frames"]
	if a["loops"] > 0:
		f = mini(f, n * a["loops"] - 1)
	_set_frame(f % n)


## Shows `n` at the frame for `distance` px walked (feet keep pace with the
## ground).
func show_stride(n: String, distance: float) -> void:
	play(n)
	var a: Dictionary = anims.get(n, {})
	if a.is_empty():
		return
	var stride: float = a["stride_px"] if a["stride_px"] > 0.0 else 7.0
	_set_frame(int(distance / stride) % int(a["frames"]))


## Shows one fixed frame of `n` (negative counts from the end).
func hold(n: String, f: int) -> void:
	play(n)
	if anims.has(n):
		var count: int = anims[n]["frames"]
		_set_frame(posmod(f, count))


## A one-shot has played all its loops (always false for looping anims).
func finished() -> bool:
	if anim == "":
		return true
	var a: Dictionary = anims[anim]
	return a["loops"] > 0 and _time * a["fps"] >= float(a["frames"] * a["loops"])


func current_frame() -> int:
	return _frame


## The cat's body in world px (for the canopy fade), from cats.json "body".
func body_rect() -> Rect2:
	var b: Array = data().get("body", [22, 15])
	return Rect2(position + Vector2(-floorf(b[0] / 2.0), -float(b[1])), Vector2(b[0], b[1]))


## Top of the resting pose's opaque pixels, relative to the feet.
func top_y() -> float:
	return offset.y + _top


func _set_frame(f: int) -> void:
	_frame = f
	region_rect = Rect2(crop.position + Vector2(f * frame_px, 0), crop.size)

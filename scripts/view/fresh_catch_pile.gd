extends Sprite2D
## The fresh-catch pile (scenes/fresh_catch_pile.tscn). world_view.gd
## instances it from world.json "fresh_catch" and shows the World core's
## prey count: frame n of the sheet has n prey on it (frame 0 = empty bed).
## Its origin is the pile's feet (bottom-centre), y-sorted with the cats; the
## collider is the footprint at its base, like every other prop. Only shows
## state; never changes it.

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")

@export var art_key := ""
@export var max_prey := 5
## Prey shown now.
var prey := -1


func setup(pile: Dictionary) -> void:
	name = "FreshCatchPile"
	art_key = pile["art"]
	max_prey = int(pile["max"])
	texture = AssetCatalog.texture(art_key)
	centered = false
	hframes = maxi(1, max_prey + 1)
	var fw := texture.get_width() / hframes
	offset = Vector2(-floorf(fw / 2.0), -float(texture.get_height()))
	position = (pile["pos"] as Vector2).round()
	sync(pile)


func sync(pile: Dictionary) -> void:
	var n := clampi(int(pile["prey"]), 0, hframes - 1)
	if n != prey:
		prey = n
		frame = n


func is_empty() -> bool:
	return prey <= 0


## Top-centre of the pile's art (the paw prompt goes above it).
func head() -> Vector2:
	# The full pile is the tallest: prompt height doesn't jump as it empties.
	return position + Vector2(0, offset.y)

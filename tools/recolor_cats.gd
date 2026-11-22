extends SceneTree
## Bakes the placeholder sheets of the cats data/cats.json gives a "recolor"
## ({"from": cat id, "map": {"#rrggbb": "#rrggbb"}}): each anim's sheet is the
## `from` cat's sheet of the same anim (art/cats/<from>_<anim>.png, from the
## CC0 Pet Cats Pack) with the mapped colours swapped; every other pixel is
## kept. Deterministic, so tests/test_cats.gd can check the PNGs are fresh.
## Run: godot --headless --path . --script res://tools/recolor_cats.gd
## Then: godot --headless --path . --import

const JsonData := preload("res://scripts/core/json_data.gd")


func _initialize() -> void:
	var ok := true
	var cats: Dictionary = JsonData.load_dict("res://data/cats.json")["cats"]
	for id: String in cats:
		if not cats[id].has("recolor"):
			continue
		for anim: String in cats[id]["anims"]:
			var img := bake(cats[id]["recolor"], anim)
			if img == null:
				push_error("recolor_cats: no %s sheet for %s" % [anim, id])
				ok = false
				continue
			var path := "res://art/cats/%s_%s.png" % [id, anim]
			var err := img.save_png(ProjectSettings.globalize_path(path))
			print("recolor_cats: wrote %s err=%d" % [path, err])
			ok = ok and err == OK
	quit(0 if ok else 1)


## The recoloured sheet for one anim, or null if the source sheet is missing.
static func bake(recolor: Dictionary, anim: String) -> Image:
	var src := "res://art/cats/%s_%s.png" % [recolor["from"], anim]
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var map := {}
	for k: String in recolor.get("map", {}):
		map[Color(k).to_html(false)] = Color(str(recolor["map"][k]))
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a == 0.0:
				continue
			var key := px.to_html(false)
			if map.has(key):
				var to: Color = map[key]
				to.a = px.a
				img.set_pixel(x, y, to)
	return img

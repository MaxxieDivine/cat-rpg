extends "res://tests/test_base.gd"
## The meadow's art is generated from data/palette.json (and world.json for
## the ground) by tools/make_art.gd. These checks fail when a PNG in art/ no
## longer matches what the painters make from the data, e.g. after editing
## the palette or the path without re-running make_art.

const Painters := preload("res://tools/art/painters.gd")
const MakeArt := preload("res://tools/make_art.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")


func _same(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	return a.get_data() == b.get_data()


func _png(name: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path("res://art/%s.png" % name))


func test_painted_art_matches_the_palette() -> void:
	var p := Painters.new()
	for name: String in MakeArt.PAINTED:
		var spec: Array = MakeArt.PAINTED[name]
		var made: Image = p.callv(spec[0], spec.slice(1))
		check(_same(made, _png(name)), "art/%s.png is up to date (run tools/make_art.gd)" % name)


func test_ground_matches_world_json() -> void:
	for name: String in MakeArt.GROUNDS:
		var area := JsonData.load_dict(MakeArt.GROUNDS[name])
		var made: Image = Painters.new().ground(area)
		check(_same(made, _png(name)), "art/%s.png matches %s path / patches (run tools/make_art.gd)" % [name, MakeArt.GROUNDS[name]])
		var size: Array = area["size"]
		check_eq(made.get_size(), Vector2i(size[0], size[1]), "%s covers its area" % name)
		check_eq(AssetCatalog.path_for(area["ground_art"]), "res://art/%s.png" % name, "%s is the area's ground_art" % name)


func test_every_area_has_its_ground_painted() -> void:
	var listed := {}
	for f: String in MakeArt.GROUNDS.values():
		listed[f] = true
	for a: Dictionary in JsonData.load_dict("res://data/areas.json")["areas"].values():
		if JsonData.load_dict(a["file"]).has("interior"):
			continue  # A den: its floor is a tile (den_interior.gd), not a painted ground.
		check(listed.has(a["file"]), "%s is in make_art.gd GROUNDS" % a["file"])


func test_ground_uses_several_grass_shades_and_dirt() -> void:
	var p := Painters.new()
	var img := _png("ground")
	var seen := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			seen[img.get_pixel(x, y).to_html(false)] = true
	var grass := 0
	for c in p.ramp("grass"):
		if seen.has(c.to_html(false)):
			grass += 1
	check(grass >= 3, "3-4 grass shades on the ground (%d)" % grass)
	var dirt := p.ramp("dirt").filter(func(c): return seen.has(c.to_html(false)))
	check(dirt.size() >= 2, "the worn path is drawn")


func test_painters_only_use_palette_colours() -> void:
	var p := Painters.new()
	var allowed := {}
	_collect(p.pal, allowed)
	for name in ["bush_round", "canopy_a", "rock_big", "log", "tall_grass", "flower_pink"]:
		var img := _png(name)
		var bad := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and not allowed.has(Color(c, 1.0).to_html(false)):
					bad += 1
		check_eq(bad, 0, "%s: pixels not in palette.json" % name)


func _collect(v: Variant, out: Dictionary) -> void:
	if v is String and str(v).begins_with("#"):
		out[Color(str(v)).to_html(false)] = true
	elif v is Array:
		for x in v:
			_collect(x, out)
	elif v is Dictionary:
		for x in v.values():
			_collect(x, out)


func test_every_world_art_key_loads() -> void:
	AssetCatalog.reset()
	for a: Dictionary in JsonData.load_dict("res://data/areas.json")["areas"].values():
		var w := JsonData.load_dict(a["file"])
		var keys := [w["ground_art"], w["forest_art"]]
		if w.has("tall_grass"):
			keys.append(w["tall_grass"]["art"])
		if w.has("pond"):
			keys.append(w["pond"]["art"])
		if w.has("interior"):
			var mat: String = w["interior"].get("walls", "fern_moss")
			keys.append_array(["den.floor", "den.outer", "den.nest", "den.nest_mine",
				"den.wall_%s_top" % mat, "den.wall_%s_side" % mat, "den.wall_%s_bottom" % mat])
		for t in w.get("prop_types", {}).values():
			for k in ["art", "canopy", "shadow"]:
				if t.has(k):
					keys.append(t[k])
		for g: Dictionary in w.get("ground", []):
			keys.append(g["art"])
		for sc: Dictionary in w.get("scatter", {}).get("areas", []):
			keys.append_array(sc.get("decor", {}).keys())
		for k in keys:
			check(not AssetCatalog.is_placeholder(AssetCatalog.texture(k)), "%s: %s loads" % [a["file"], k])

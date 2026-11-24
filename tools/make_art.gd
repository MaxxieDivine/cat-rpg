extends SceneTree
## Bakes every PNG in art/ except the cats (art/cats/, copied from the Pet
## Cats Pack by tools/import_cats.gd). The cow and the paw prompt come from the
## character grids below ("." is transparent; every other character must be in
## that sprite's palette). Everything else in the meadow (trees, bushes, rocks,
## the pond, flowers, the ground itself...) is painted by tools/art/painters.gd
## from data/palette.json (and data/world.json for the ground): see PAINTED.
## Run: godot --headless --path . --script res://tools/make_art.gd
## Then: godot --headless --path . --import

const Painters := preload("res://tools/art/painters.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

## file name (art/<name>.png) -> [painter method, args...]
const PAINTED := {
	"bush_round": ["foliage", 22, 16, 11, 5, 3, true],
	"bush_wide": ["foliage", 30, 15, 12, 6, 4, true],
	"bush_small": ["foliage", 15, 11, 13, 4, 2, true],
	"canopy_a": ["foliage", 60, 50, 21, 9],
	"canopy_b": ["foliage", 46, 40, 22, 7],
	"trunk": ["trunk", 12, 26],
	"rock_big": ["rock", 16, 11, 31],
	"rock_small": ["rock", 9, 7, 32],
	"log": ["log_art", 24, 9],
	"pond": ["pond", 88, 42, 41],
	"tall_grass": ["tall_grass", 9, 12, 51],
	"tuft": ["tuft", 1],
	"flower_pink": ["flower", "pink"],
	"flower_yellow": ["flower", "yellow"],
	"flower_lilac": ["flower", "lilac"],
	"butterfly": ["butterfly"],
	"bird_shadow": ["bird_shadow"],
	"shadow_s": ["shadow", 16, 5],
	"shadow_m": ["shadow", 22, 7],
	"shadow_l": ["shadow", 40, 10],
	"shadow_xl": ["shadow", 54, 14],
	"cloud_shadow": ["cloud_shadow", 200, 110, 61],
	"forest": ["forest_tile", 64, 71],
	"firefly": ["firefly"],
	"fresh_catch": ["fresh_catch", 8, 30, 15],
	"icon_prey": ["icon_prey"],
	"icon_drop": ["icon_drop"],
	"ripple": ["ripple", 11, 5],
	"tall_grass_gold": ["tall_grass", 9, 12, 51, "grass_gold"],
	"tuft_gold": ["tuft", 1, "grass_gold"],
	"flower_white": ["flower", "white"],
	"den": ["den", 30, 12],
	"trail": ["trail", 36, 11],
	"mouse": ["mouse"],
	"mouse_carried": ["mouse_carried"],
	"alert_mark": ["alert_mark"],
	"pounce_ring": ["pounce_ring", 18, 7],
	"rank_kit": ["rank_icon", "kit"],
	"rank_apprentice": ["rank_icon", "apprentice"],
	"rank_warrior": ["rank_icon", "warrior"],
	"rank_medicine": ["rank_icon", "medicine"],
	"rank_deputy": ["rank_icon", "deputy"],
	"rank_leader": ["rank_icon", "leader"],
	"leaders_rock": ["leaders_rock", 48, 40, 81],
	"lichen": ["lichen", 14, 7, 82],
	"worn_patch": ["worn_patch", 26, 9],
	"den_fern": ["den_fern", 72, 44, 91],
	"den_floor": ["den_floor", 64, 92],
	"den_outer": ["den_outer", 32, 93],
	"den_wall_fern_moss_top": ["den_wall_fern_moss", 32, 26, 94],
	"den_wall_fern_moss_side": ["den_wall_side", 14, 32, 95],
	"den_wall_fern_moss_bottom": ["den_wall_bottom", 32, 12, 96],
	"den_nest": ["den_nest", 28, 12],
	"den_nest_mine": ["den_nest", 28, 12, true],
	"bracken": ["bracken", 11, 12, 131],
	"patrol_icon": ["patrol_icon"],
	"patrol_icon_picked": ["patrol_icon", true],
	"scent_ring": ["scent_ring", 20, 9],
	"scent_marked": ["scent_ring", 20, 9, true],
}

## Each area's baked floor: art/<name>.png -> the area file it is painted
## from (its size, path and ground_paint).
const GROUNDS := {
	"ground": "res://data/world.json",
	"ground_hunting": "res://data/hunting_grounds.json",
	"ground_hunting_2": "res://data/hunting_grounds_2.json",
}

const SPRITES := {
	# 48x48, front view
	"cow": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "w": Color8(246, 242, 234), "s": Color8(214, 206, 196),
			"b": Color8(52, 50, 60), "p": Color8(242, 164, 180), "n": Color8(184, 92, 116),
			"e": Color8(20, 18, 26), "h": Color8(236, 220, 170), "k": Color8(96, 88, 100),
		},
		"grid": [
			"................................................",
			"................................................",
			"................................................",
			"............o......................o............",
			"...........oho....................oho...........",
			"...........ohho..................ohho...........",
			"............oho..................oho............",
			"............ohho...oooooooooo...ohho............",
			".............ohhooobbbbbbwwwwooohho.............",
			"..............ooowwwwwwwwwwwbbbooo..............",
			".......ooo.....owwwwwwwwwwwbbbbbo.....ooo.......",
			".....oowwwoo..owwwwwwwwwwwbbbbbbbo..oowwwoo.....",
			"....owwwwwwwoowwwwwwwwwwwwbbbbbbbboowwwwwwwo....",
			"...owwpppppwowwwwwwwwwwwwwbbbbbbbbbowpppppwwo...",
			"...owwpppppwowwwewwwwwwwwwbbbbewbbbowpppppwwo...",
			"....owwwwwwwowwweewwwwwwwwwbbbeebbbowwwwwwwo....",
			".....oowwwooowwweewwwwwwwwwwbbeebbbooowwwoo.....",
			".......ooo.owwwwwwwwwwwwwwwwwwwbwwwwo.ooo.......",
			"............owwwwwwwwwwwwwwwwwwwwwwo............",
			"............owwwwwwwppppppppwwwwwwwo............",
			"............owwwwwppppppppppppwwwwwo............",
			"............owwwwppppppppppppppwwwwo............",
			".............owwppppppppppppppppwwo.............",
			"..............owppppnnppppnnppppwo..............",
			"...............oppppnppppppnppppo...............",
			"................oppppppppppppppo................",
			"................ooppppnnnnppppoo................",
			"..............oowwooppppppppoowwoo..............",
			".............owbwwwwoooooooowwwwwwo.............",
			"............obbbbbbwwwwwwwwwwwwwwwwo............",
			"...........obbbbbbbbwwwwwwwwwwwwwwwwo...........",
			"...........obbbbbbbbwwwwwwwwwwwwwwwwo...........",
			"..........obbbbbbbbbwwwwwwwwwwwwwwwwwo..........",
			"..........obbbbbbbbbwwwwwwwwwwwwwwwwwo..........",
			"..........owbbbbbbbwwwwwwwwwwwwwwwwwwo..........",
			"..........owwwwbwwwwwwwwwwwwwwbbbbbbwo..........",
			"...........owwwwwwwwwwwwwwwwwwbbbbbbo...........",
			"...........owwwwwooooowwwwooooobbbbbo...........",
			"...........oowwwowwwwwowwowwwwwobbboo...........",
			"...........osossowwwwwossowwbbbossoso...........",
			"...........ossooowwwwwossowwbbbooosso...........",
			"...........ossssowwwwwossowwbbbosssso...........",
			"...........okkkkowwwwwoooowwwwwokkkko...........",
			"...........okkkkowwwwwo..owwwwwokkkko...........",
			"............oooookkkkko..okkkkkooooo............",
			"................okkkkko..okkkkko................",
			".................ooooo....ooooo.................",
			"................................................",
		],
	},
	# 11x9 paw print: the "you can talk here" prompt that bobs over an NPC.
	"paw": {
		"palette": {".": Color8(0, 0, 0, 0), "o": Color8(28, 24, 36), "w": Color8(250, 250, 245)},
		"grid": [
			"...oo.oo...",
			"..owwowwo..",
			".oowwowwoo.",
			"owwooooowwo",
			"owwowwwowwo",
			".oowwwwwoo.",
			"..owwwwwo..",
			"..owwwwwo..",
			"...ooooo...",

		],
	},
}


## Web app / home-screen icons: Fern's first idle frame (art/cats/, cropped
## to the cat) on meadow green, whole-number scaled. Sizes are what the Web export preset asks for.
const ICON_SIZES := [144, 180, 512]
const ICON_BG := Color8(111, 179, 90)
const ICON_CAT := "res://art/cats/fern_idle.png"
## The part of a 50x50 frame the idle cat fills.
const ICON_CROP := Rect2i(12, 14, 26, 19)


func _initialize() -> void:
	var ok := true
	for name: String in SPRITES:
		ok = _bake(name, SPRITES[name]) and ok
	for px: int in ICON_SIZES:
		ok = _bake_icon(px) and ok
	ok = _bake_sunspot() and ok
	var painters := Painters.new()
	for name: String in PAINTED:
		var spec: Array = PAINTED[name]
		var img: Image = painters.callv(spec[0], spec.slice(1))
		ok = _save(img, name) and ok
	for name: String in GROUNDS:
		ok = _save(painters.ground(JsonData.load_dict(GROUNDS[name])), name) and ok
	quit(0 if ok else 1)


func _save(img: Image, name: String) -> bool:
	var path := "res://art/%s.png" % name
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("make_art: wrote %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
	return err == OK


## Sorrel's sunny spot: a flat pale-yellow ellipse (two tones, hard edges,
## no gradients) drawn under her on the ground layer.
const SUNSPOT_SIZE := Vector2i(64, 22)
const SUNSPOT_OUTER := Color8(255, 236, 140, 70)
const SUNSPOT_INNER := Color8(255, 244, 180, 110)


func _bake_sunspot() -> bool:
	var img := Image.create(SUNSPOT_SIZE.x, SUNSPOT_SIZE.y, false, Image.FORMAT_RGBA8)
	var c := Vector2(SUNSPOT_SIZE) / 2.0
	for y in SUNSPOT_SIZE.y:
		for x in SUNSPOT_SIZE.x:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - c) / c).length()
			if d <= 0.62:
				img.set_pixel(x, y, SUNSPOT_INNER)
			elif d <= 1.0:
				img.set_pixel(x, y, SUNSPOT_OUTER)
	var path := "res://art/sunspot.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("make_art: wrote %s err=%d" % [path, err])
	return err == OK


func _bake_icon(px: int) -> bool:
	var src := Image.load_from_file(ProjectSettings.globalize_path(ICON_CAT))
	if src == null or src.is_empty():
		push_error("make_art: %s missing (run tools/import_cats.gd)" % ICON_CAT)
		return false
	src.convert(Image.FORMAT_RGBA8)
	var cat := src.get_region(ICON_CROP)
	var k := floori(px * 0.8 / ICON_CROP.size.x)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(ICON_BG)
	var origin := (Vector2i(px, px) - ICON_CROP.size * k) / 2
	for y in ICON_CROP.size.y:
		for x in ICON_CROP.size.x:
			var c := cat.get_pixel(x, y)
			if c.a > 0.0:
				img.fill_rect(Rect2i(origin + Vector2i(x, y) * k, Vector2i(k, k)), Color(c, 1.0))
	var path := "res://art/icon_%d.png" % px
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("make_art: wrote %s (%dx%d, cat x%d) err=%d" % [path, px, px, k, err])
	return err == OK


func _bake(name: String, spec: Dictionary) -> bool:
	var grid: Array = spec["grid"]
	var palette: Dictionary = spec["palette"]
	var h := grid.size()
	var w := (grid[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = grid[y]
		if row.length() != w:
			push_error("make_art: %s row %d has length %d, expected %d" % [name, y, row.length(), w])
			return false
		for x in w:
			if not palette.has(row[x]):
				push_error("make_art: %s has unknown colour '%s' at %d,%d" % [name, row[x], x, y])
				return false
			img.set_pixel(x, y, palette[row[x]])
	var path := "res://art/%s.png" % name
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("make_art: wrote %s (%dx%d) err=%d" % [path, w, h, err])
	return err == OK

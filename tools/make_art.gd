extends SceneTree
## Bakes every PNG in art/. The cats, the cow and the paw prompt come from the
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
	"bush_round": ["foliage", 30, 22, 11, 6, 4, true],
	"bush_wide": ["foliage", 42, 20, 12, 8, 5, true],
	"bush_small": ["foliage", 20, 15, 13, 4, 2, true],
	"canopy_a": ["foliage", 60, 50, 21, 9],
	"canopy_b": ["foliage", 46, 40, 22, 7],
	"trunk": ["trunk", 12, 26],
	"rock_big": ["rock", 22, 15, 31],
	"rock_small": ["rock", 12, 9, 32],
	"log": ["log_art", 32, 12],
	"pond": ["pond", 88, 42, 41],
	"tall_grass": ["tall_grass", 9, 12, 51],
	"tuft": ["tuft", 1],
	"flower_pink": ["flower", "pink"],
	"flower_yellow": ["flower", "yellow"],
	"flower_lilac": ["flower", "lilac"],
	"butterfly": ["butterfly"],
	"bird_shadow": ["bird_shadow"],
	"shadow_s": ["shadow", 16, 5],
	"shadow_m": ["shadow", 28, 8],
	"shadow_l": ["shadow", 40, 10],
	"shadow_xl": ["shadow", 54, 14],
	"cloud_shadow": ["cloud_shadow", 200, 110, 61],
	"forest": ["forest_tile", 64, 71],
	"firefly": ["firefly"],
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
	# 72x24 sheet: three 24x24 frames (idle, walk A, walk B), facing right, feet on row 22
	"cat": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "c": Color8(232, 150, 72), "d": Color8(184, 98, 44),
			"l": Color8(250, 222, 186), "e": Color8(20, 18, 26), "p": Color8(240, 140, 160), "w": Color8(250, 250, 245),
		},
		"grid": [
			".............................................................o.......o..",
			".............o.......o...............o.......o..............oco.....oco.",
			"............oco.....oco.............oco.....oco.............occo...occo.",
			"............occo...occo.............occo...occo.............ocpcooocpco.",
			"............ocpcooocpco.............ocpcooocpco..............ooccdccoo..",
			"....o........ooccdccoo....o..........ooccdccoo......o.......occcdddccco.",
			"...odo......occcdddccco..odo........occcdddccco....odo......occccccccco.",
			"..odo.......occccccccco.odo.........occccccccco...odo......occccccewccco",
			".oco.......occccccewcccooco........occccccewccco.oco.......occcccceeccco",
			".oco.......occcccceecccooco........occcccceeccco.oco.......occccccccllpo",
			".oco.......occccccccllpooco........occccccccllpo.oco...oooooocccccclllo.",
			".oco...oooooocccccclllo..oco...oooooocccccclllo..oco.ooccddcocccccclllo.",
			".oco.ooccddcocccccclllo..oco.ooccddcocccccclllo..ocooccccdccdooccccloo..",
			"..ococcccdccdooccccloo....ococcccdccdooccccloo....occccccccccccooooo....",
			"...occcccccccccooooo.......occcccccccccooooo.......occcccccccccccco.....",
			"...occcccccccccccco........occcccccccccccco........occcccccccccccco.....",
			"...occcccccccccccco........occcccccccccccco.........occclllllllllo......",
			"....occclllllllllo..........occcllllllllloo..........ooclllllllooo......",
			"....oddcllllllldcco........oddocllllllloocco........occddoooooccddo.....",
			"....oddccoooooddcco........oddooccoooddoocco........occddo...occddo.....",
			"....oddcco...oddcco........oddoocco.oddoocco........occddo...occddo.....",
			"....oddcco...oddcco........oddoocco.oddoocco........occddo...occddo.....",
			".....oooo.....oooo..........oo..oo...oo..oo..........oooo.....oooo......",
			"........................................................................",
		],
	},
	# Wick: 72x24 sheet like Fern's (idle, walk A, walk B), facing right, feet
	# on row 22. Lean and long-legged, sandy, white tail tip, so he never
	# reads as Fern (orange, shorter legs, orange tail).
	"wick": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "c": Color8(214, 196, 150), "d": Color8(172, 150, 104),
			"l": Color8(244, 236, 214), "e": Color8(20, 18, 26), "p": Color8(226, 150, 160), "w": Color8(255, 255, 255),
		},
		"grid": [
			".............................................................o.......o..",
			".............o.......o...............o.......o..............oco.....oco.",
			"............oco.....oco.............oco.....oco.............occo...occo.",
			"............occo...occo.............occo...occo.............ocpcooocpco.",
			"............ocpcooocpco.............ocpcooocpco..............ooccdccoo..",
			"....o........ooccdccoo....o..........ooccdccoo......o.......occcdddccco.",
			"...owo......occcdddccco..owo........occcdddccco....owo......occccccccco.",
			"..owo.......occccccccco.owo.........occccccccco...owo......occccccewccco",
			".owo.......occccccewcccoowo........occccccewccco.owo.......occcccceeccco",
			".oco.......occcccceecccooco........occcccceeccco.oco.......occccccccllpo",
			".oco.......occccccccllpooco........occccccccllpo.oco...oooooocccccclllo.",
			".oco...oooooocccccclllo..oco...oooooocccccclllo..oco.ooccddcocccccclllo.",
			".oco.ooccddcocccccclllo..oco.ooccddcocccccclllo..ocooccccdccdooccccloo..",
			"..ococcccdccdooccccloo....ococcccdccdooccccloo....occccccccccccooooo....",
			"...occcccccccccooooo.......occcccccccccooooo.......occcccccccccccco.....",
			"...occcccccccccccco........occcccccccccccco.........occclllllllllo......",
			"....occclllllllllo..........occcllllllllloo..........ooclllllllooo......",
			"....oddcllllllldcco........oddocllllllloocco........occddoooooccddo.....",
			"....oddccoooooddcco........oddooccoooddoocco........occddo...occddo.....",
			"....oddcco...oddcco........oddoocco.oddoocco........occddo...occddo.....",
			"....oddcco...oddcco........oddoocco.oddoocco........occddo...occddo.....",
			"....oddcco...oddcco........oddoocco.oddoocco........occddo...occddo.....",
			".....oooo.....oooo..........oo..oo...oo..oo..........oooo.....oooo......",
			"........................................................................",
		],
	},
	# Bram: 56x24 sheet, two 28x24 frames (sitting, blink), facing right, base
	# on row 22. Broad and dark brown with amber eyes.
	"bram": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "b": Color8(98, 66, 46), "d": Color8(70, 46, 32),
			"m": Color8(150, 112, 82), "y": Color8(236, 184, 64), "k": Color8(20, 18, 26), "p": Color8(206, 126, 128),
		},
		"grid": [
			"........................................................",
			"..............o.......o...................o.......o.....",
			".............obo.....obo.................obo.....obo....",
			".............obbo...obbo.................obbo...obbo....",
			".............obpbooobpbo.................obpbooobpbo....",
			"............obbbbdddbbbbo...............obbbbdddbbbbo...",
			"...........obbbbbbbbbbbbbo.............obbbbbbbbbbbbbo..",
			"...........obbbbbbbbbbbbbo.............obbbbbbbbbbbbbo..",
			"...........obbbbbbbbyybbbbo............obbbbbbbbddbbbbo.",
			"...........obbbbbbbbykbbbmo............obbbbbbbbddbbbmo.",
			"...........obbbbbbbbbbbmmmpo...........obbbbbbbbbbbmmmpo",
			"............obbbbbbbbbmmmmo.............obbbbbbbbbmmmmo.",
			"............oobbbbbbbbbmmo..............oobbbbbbbbbmmo..",
			"..........oobbbbbbbbbbboo.............oobbbbbbbbbbboo...",
			".........obbbbbbbbbbbbmmo............obbbbbbbbbbbbmmo...",
			"........obbbbbdbbbbbbmmmo...........obbbbbdbbbbbbmmmo...",
			".......obbbbbdbbbbbbbmmmo..........obbbbbdbbbbbbbmmmo...",
			".......obbbbdbbbbobbbmmmo..........obbbbdbbbbobbbmmmo...",
			"......obbbbbbbbbobbbbmmbo.........obbbbbbbbbobbbbmmbo...",
			"......obbbbbbbbbobbbbobbo.........obbbbbbbbbobbbbobbo...",
			".oooo.obbbbbbbbbobbbbobbo....oooo.obbbbbbbbbobbbbobbo...",
			"obbbbdobbbbbbbbbbobbbobbo...obbbbdobbbbbbbbbbobbbobbo...",
			".oooooooooooooooooooooooo....oooooooooooooooooooooooo...",
			"........................................................",
		],
	},
	# Sorrel: 64x16 sheet, two 32x16 frames (dozing, awake), lying down facing
	# right, base on row 14. Thin and gray with a pale muzzle.
	"sorrel": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "g": Color8(150, 152, 160), "G": Color8(116, 118, 128),
			"m": Color8(232, 228, 220), "e": Color8(40, 38, 48), "k": Color8(20, 18, 26), "p": Color8(226, 150, 160),
		},
		"grid": [
			"................................................................",
			"......................o....o..........................o....o....",
			".....................ogo..ogo........................ogo..ogo...",
			".....................ogpooogpo.......................ogpooogpo..",
			"....................ogggGGgggo......................ogggGGgggo..",
			"....................oggggggggo......................ogkggggkgo..",
			"....................ogeeggeegmo.....................ogkggggkgmo.",
			"....................oggggggmmmpo....................oggggggmmmpo",
			".........ooooooooooogggggmmmmo...........ooooooooooogggggmmmmo..",
			".......ooggGgggGgggGgoggggmmoo.........ooggGgggGgggGgoggggmmoo..",
			"......ogggGgggGgggGgggooooo...........ogggGgggGgggGgggooooo.....",
			".....ogggggggggggggggggggo...........ogggggggggggggggggggo......",
			"ooooogggggggggggggggggggggo.....ooooogggggggggggggggggggggo.....",
			"oggggGgggggggggggggggmmmmmmo....oggggGgggggggggggggggmmmmmmo....",
			".ooooooooooooooooooooooooooo.....ooooooooooooooooooooooooooo....",
			"................................................................",
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


## Web app / home-screen icons: the idle cat on meadow green, whole-number
## scaled. Sizes are what the Web export preset asks for.
const ICON_SIZES := [144, 180, 512]
const ICON_BG := Color8(111, 179, 90)


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
	ok = _save(painters.ground(JsonData.load_dict("res://data/world.json")), "ground") and ok
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
	var spec: Dictionary = SPRITES["cat"]
	var frame := 24
	var k := floori(px * 0.72 / frame)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(ICON_BG)
	var origin := Vector2i((px - frame * k) / 2, (px - frame * k) / 2 + k)
	var grid: Array = spec["grid"]
	for y in frame:
		var row: String = grid[y]
		for x in frame:
			var c: Color = spec["palette"][row[x]]
			if c.a > 0.0:
				img.fill_rect(Rect2i(origin + Vector2i(x, y) * k, Vector2i(k, k)), c)
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

extends SceneTree
## Bakes every PNG in art/ from the character grids below, one entry per file.
## Run: godot --headless --path . --script res://tools/make_art.gd
## Then: godot --headless --path . --import
## "." is transparent; every other character must be in that sprite's palette.

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
	# 32x24 obstacle, base on row 22
	"bush": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "g": Color8(76, 150, 72), "G": Color8(52, 112, 60),
			"h": Color8(120, 190, 96), "r": Color8(220, 70, 80), "y": Color8(250, 210, 80), "w": Color8(250, 250, 245),
		},
		"grid": [
			"................................",
			"................................",
			".............oooooo.............",
			"...........ooggggggoo...........",
			"..........oggggggggggooo........",
			".........ogggghgggggggggoo......",
			".......ooogghhgggggghgggggoo....",
			".....oogggggggggggghggggggggo...",
			"....ogggggggggggggggggggghggo...",
			"...oggggghgggggggggggggghggggo..",
			"..oggggghgggggggggggggggggggggo.",
			"..ogggggggggggggggggggggggggggo.",
			".oggggggggggggggggggggrgggggggo.",
			".oggggggggggggggggggggggggggggo.",
			".ogggggggrggggggggggggggggggggo.",
			".oggggggggggggggggggggggggggggo.",
			"..ogggggggggggggrgggggggggrggo..",
			"..oGGGGGGGGGGGGGGGGGGGGGGGGGo...",
			"...oGGGGGGGGGGGGGGGGGGGGGGGGo...",
			"...oGGGGGGGGGGGGGGGGGGGGGGGGo...",
			"...oGGGGGGGGGGGGGGGGGGGGGGGGo...",
			"....oooooooooooooooooooooooo....",
			"................................",
			"................................",
		],
	},
	# 8x6 grass tuft (decoration)
	"tuft": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "g": Color8(76, 150, 72), "G": Color8(52, 112, 60),
			"h": Color8(120, 190, 96), "r": Color8(220, 70, 80), "y": Color8(250, 210, 80), "w": Color8(250, 250, 245),
		},
		"grid": [
			"........",
			"........",
			".....G..",
			"...G.G..",
			"..GGGGG.",
			".GGGGGG.",
		],
	},
	# 5x5 daisy (decoration)
	"flower": {
		"palette": {
			".": Color8(0, 0, 0, 0),
			"o": Color8(28, 24, 36), "g": Color8(76, 150, 72), "G": Color8(52, 112, 60),
			"h": Color8(120, 190, 96), "r": Color8(220, 70, 80), "y": Color8(250, 210, 80), "w": Color8(250, 250, 245),
		},
		"grid": [
			".....",
			"..w..",
			".wyw.",
			"..w..",
			".....",
		],
	},
}


func _initialize() -> void:
	var ok := true
	for name: String in SPRITES:
		ok = _bake(name, SPRITES[name]) and ok
	quit(0 if ok else 1)


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

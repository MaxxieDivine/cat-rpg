extends SceneTree
## Bakes art/cow.png from the character grid below.
## Run: godot --headless --path . --script res://tools/make_cow.gd

const OUT_PATH := "res://art/cow.png"

const PALETTE := {
	".": Color8(0, 0, 0, 0),
	"o": Color8(28, 24, 36),      # outline
	"w": Color8(246, 242, 234),   # body white
	"s": Color8(214, 206, 196),   # white shade
	"b": Color8(52, 50, 60),      # black patch
	"p": Color8(242, 164, 180),   # pink nose / ears
	"n": Color8(184, 92, 116),    # nostrils / mouth
	"e": Color8(20, 18, 26),      # eyes
	"h": Color8(236, 220, 170),   # horns
	"k": Color8(96, 88, 100),     # hooves
}

const GRID := [
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
]


func _initialize() -> void:
	var h: int = GRID.size()
	var w: int = (GRID[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = GRID[y]
		assert(row.length() == w, "row %d has length %d, expected %d" % [y, row.length(), w])
		for x in w:
			img.set_pixel(x, y, PALETTE[row[x]])
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("make_cow: wrote %s (%dx%d) err=%d" % [OUT_PATH, w, h, err])
	quit(0 if err == OK else 1)

extends RefCounted
## Procedural pixel-art painters for the meadow (trees, bushes, rocks, the
## pond, flowers, ground...). Every colour comes from data/palette.json, and
## every random choice from a seeded RandomNumberGenerator, so the same data
## always bakes the same PNGs. Used by tools/make_art.gd (bakes art/) and by
## tests/test_art.gd (checks the baked ground still matches world.json).
## The cats and the cow keep their hand-made character grids in make_art.gd.

const JsonData := preload("res://scripts/core/json_data.gd")
const PALETTE_PATH := "res://data/palette.json"

## 4x4 ordered-dither thresholds (0..1).
const BAYER := [
	[0.0 / 16, 8.0 / 16, 2.0 / 16, 10.0 / 16],
	[12.0 / 16, 4.0 / 16, 14.0 / 16, 6.0 / 16],
	[3.0 / 16, 11.0 / 16, 1.0 / 16, 9.0 / 16],
	[15.0 / 16, 7.0 / 16, 13.0 / 16, 5.0 / 16],
]
const CLEAR := Color(0, 0, 0, 0)
## Light comes from the upper left (late-afternoon sun).
const LIGHT := Vector3(-0.55, -0.65, 0.52)

var pal: Dictionary


func _init(palette: Dictionary = {}) -> void:
	pal = palette if not palette.is_empty() else JsonData.load_dict(PALETTE_PATH)


## A palette colour by path: "ink", "leaf.2", "flower.pink", "grade.night".
func c(path: String, alpha: float = 1.0) -> Color:
	var v: Variant = pal
	for part in path.split("."):
		if v is Array:
			v = v[int(part)]
		elif v is Dictionary:
			v = v.get(part)
	if not (v is String):
		push_error("painters: no palette colour '%s'" % path)
		return Color.MAGENTA
	var col := Color(str(v))
	col.a = alpha
	return col


func ramp(name: String) -> Array[Color]:
	var out: Array[Color] = []
	for s in pal.get(name, []):
		out.append(Color(str(s)))
	return out


static func dither(x: int, y: int) -> float:
	return BAYER[posmod(y, 4)][posmod(x, 4)]


## Picks a shade 0..n-1 for brightness v (0..1), ordered-dithered so bands
## blend with a pixel pattern instead of a gradient.
static func level(v: float, n: int, x: int, y: int, spread: float = 0.6) -> int:
	return clampi(floori(v * n + (dither(x, y) - 0.5) * spread), 0, n - 1)


# --- Foliage


## A leafy blob made of overlapping circles, lit from the upper left, with a
## dark leaf outline. Trees' canopies, bushes and the forest use it.
## `flat_bottom` cuts the blob off a couple of pixels above the bottom edge.
func foliage(w: int, h: int, seed: int, blobs: int = 7, berries: int = 0, flat_bottom: bool = false) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var circles: Array[Vector3] = []
	var cx := w / 2.0
	var cy := h / 2.0
	var main_r := minf(w, h) * 0.42
	circles.append(Vector3(cx, cy + h * 0.05, main_r))
	for i in blobs:
		var r := rng.randf_range(main_r * 0.42, main_r * 0.72)
		var ang := rng.randf_range(0.0, TAU)
		var px := cx + cos(ang) * (w / 2.0 - r - 1.0) * rng.randf_range(0.6, 1.0)
		var py := cy + sin(ang) * (h / 2.0 - r - 1.0) * rng.randf_range(0.6, 1.0)
		circles.append(Vector3(px, py, r))
	var img := _lit_circles(w, h, circles, ramp("leaf"), flat_bottom, false)
	_speckle(img, rng, ramp("leaf"), w * h / 14)
	for i in berries:
		var p := Vector2i(rng.randi_range(3, w - 4), rng.randi_range(3, h - 5))
		if img.get_pixelv(p).a > 0.0 and img.get_pixelv(p) != ramp("leaf")[0]:
			img.set_pixelv(p, c("berry"))
	return img


## Circles (x, y, r) -> shaded image. `wrap` makes it tile (the forest).
func _lit_circles(w: int, h: int, circles: Array[Vector3], shades: Array[Color], flat_bottom: bool, wrap: bool) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var height := PackedFloat32Array()
	height.resize(w * h)
	var light := LIGHT.normalized()
	var bottom_cut := h - 2 if flat_bottom else h
	for y in h:
		for x in w:
			var best := -1.0
			var bright := 0.0
			for ci in circles:
				var d := Vector2(x + 0.5 - ci.x, y + 0.5 - ci.y)
				if wrap:
					d.x = wrapf(d.x, -w / 2.0, w / 2.0)
					d.y = wrapf(d.y, -h / 2.0, h / 2.0)
				var q := d.length() / ci.z
				if q < 1.0:
					var z := sqrt(1.0 - q * q)
					# Smaller, nearer blobs sit "on top".
					var top := z * ci.z
					if top > best:
						best = top
						var n := Vector3(d.x / ci.z, d.y / ci.z, z)
						bright = clampf(n.dot(light) * 0.75 + 0.35, 0.0, 1.0)
			if best < 0.0 or y >= bottom_cut:
				height[y * w + x] = -1.0
				continue
			height[y * w + x] = best
			var shade := 1 + level(bright, shades.size() - 1, x, y)
			img.set_pixel(x, y, shades[shade])
	# Outline: filled pixels next to empty ones get the darkest shade.
	for y in h:
		for x in w:
			if height[y * w + x] < 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if wrap:
					nx = posmod(nx, w)
					ny = posmod(ny, h)
				if nx < 0 or ny < 0 or nx >= w or ny >= h or height[ny * w + nx] < 0.0:
					img.set_pixel(x, y, shades[0])
					break
	return img


## Single-pixel leaf texture: a few lighter and darker flecks.
func _speckle(img: Image, rng: RandomNumberGenerator, shades: Array[Color], n: int) -> void:
	for i in n:
		var p := Vector2i(rng.randi_range(1, img.get_width() - 2), rng.randi_range(1, img.get_height() - 2))
		var cur := img.get_pixelv(p)
		var idx := shades.find(cur)
		if idx <= 0:
			continue
		var step := 1 if rng.randf() < 0.5 else -1
		img.set_pixelv(p, shades[clampi(idx + step, 1, shades.size() - 1)])


## A tileable square of dense canopy (the forest past the meadow's edge).
func forest_tile(size: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var circles: Array[Vector3] = []
	for i in 26:
		circles.append(Vector3(rng.randf_range(0, size), rng.randf_range(0, size), rng.randf_range(7.0, 13.0)))
	var shades: Array[Color] = ramp("leaf")
	shades = shades.slice(0, 4)
	var img := _lit_circles(size, size, circles, shades, false, true)
	# Gaps between crowns are deep shadow.
	for y in size:
		for x in size:
			if img.get_pixel(x, y).a == 0.0:
				img.set_pixel(x, y, c("leaf.0").darkened(0.25))
	_speckle(img, rng, shades, size * size / 16)
	return img


## Tree trunk with root flare, lit from the left.
func trunk(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bark := ramp("bark")
	var ink := c("ink")
	var core_w := maxi(4, w - 6)
	for y in h:
		var flare := 0
		if y >= h - 4:
			flare = (y - (h - 5))
		var x0 := (w - core_w) / 2 - flare
		var x1 := (w + core_w) / 2 + flare - 1
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			var col: Color
			if x == x0 or x == x1 or y == h - 1:
				col = ink
			else:
				var t := float(x - x0) / maxf(1.0, x1 - x0)
				col = bark[2] if t < 0.3 else (bark[1] if t < 0.75 else bark[0])
				if (y * 7 + x * 3) % 11 == 0:
					col = bark[0]
			img.set_pixel(x, y, col)
	return img


# --- Stones, wood, water


## A boulder: a lumpy ellipse, lit from the upper left, with an ink outline
## and a moss cap.
func rock(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stone := ramp("stone")
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var light := LIGHT.normalized()
	var bumps: Array[float] = []
	for i in 8:
		bumps.append(rng.randf_range(0.82, 1.0))
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5 - w / 2.0) / (w / 2.0), (y + 0.5 - h / 2.0) / (h / 2.0))
			var ang := fposmod(d.angle(), TAU) / TAU * bumps.size()
			var i0 := int(ang) % bumps.size()
			var r := lerpf(bumps[i0], bumps[(i0 + 1) % bumps.size()], ang - floorf(ang))
			if y >= h - 1:
				r = 0.0
			var q := d.length() / r
			if q >= 1.0:
				continue
			mask[y * w + x] = 1
			var n := Vector3(d.x, d.y, sqrt(1.0 - q * q))
			var b := clampf(n.normalized().dot(light) * 0.8 + 0.3, 0.0, 1.0)
			img.set_pixel(x, y, stone[level(b, stone.size(), x, y)])
	_outline(img, mask, c("ink"))
	# Moss on top.
	for x in w:
		for y in h:
			if mask[y * w + x] == 1 and img.get_pixel(x, y) != c("ink"):
				if y < h * 0.35 and rng.randf() < 0.45:
					img.set_pixel(x, y, c("leaf.3") if rng.randf() < 0.6 else c("leaf.2"))
				break
	return img


## The Leader's Rock: a tall boulder w wide and h high, narrower at the top
## with a pale flat ledge (the top `ledge` rows) the leader stands on, lit
## from the upper left, a few cracks, moss on the ledge's rim, and the dark
## mouth of the leader's den at the base (centre x = cave_x, cave_w wide,
## cave_h high). The bottom row is flat: the base sits on the ground.
func leaders_rock(w: int, h: int, seed: int, ledge: int = 5, cave_x: int = 14, cave_w: int = 14, cave_h: int = 13) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stone := ramp("stone")
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var cx := w / 2.0
	var wobble: Array[float] = []
	for y in h:
		wobble.append(rng.randf_range(-0.6, 0.6))
	for y in h:
		var t := float(y) / float(h - 1)
		# Narrow ledge on top, full width by two thirds down, a slight
		# tuck at the very bottom; the top corners rounded off.
		var hw := cx * (0.62 + 0.38 * smoothstep(0.0, 0.6, t)) + wobble[y]
		if t > 0.9:
			hw -= (t - 0.9) * w * 0.12
		if y < 3:
			hw -= 3 - y
		for x in w:
			var dx := x + 0.5 - cx
			if absf(dx) > hw:
				continue
			mask[y * w + x] = 1
			var col: Color
			if y < ledge:
				# The flat top catches the sun.
				col = stone[3] if dither(x, y) < 0.75 - 0.1 * y else stone[2]
			else:
				var nx := dx / maxf(1.0, hw)
				var b := 0.62 - 0.42 * nx - 0.35 * (t - 0.15)
				if y == ledge:
					b -= 0.35
				col = stone[level(clampf(b, 0.0, 1.0), stone.size(), x, y)]
			img.set_pixel(x, y, col)
	# Cracks: short dark runs down the face.
	for i in 4:
		var x := rng.randi_range(int(w * 0.2), int(w * 0.85))
		var y := rng.randi_range(ledge + 3, int(h * 0.55))
		for k in rng.randi_range(4, 8):
			if x >= 0 and x < w and y < h and mask[y * w + x] == 1:
				img.set_pixel(x, y, stone[0])
			y += 1
			if rng.randf() < 0.35:
				x += 1 if rng.randf() < 0.5 else -1
	# The leader's den: a dark arch at the base.
	var half := cave_w / 2.0
	for y in range(h - cave_h, h):
		for x in range(cave_x - int(half) - 1, cave_x + int(half) + 2):
			if x < 0 or x >= w or mask[y * w + x] == 0:
				continue
			var q := Vector2((x + 0.5 - cave_x) / half, (y + 0.5 - h) / float(cave_h)).length()
			if q < 0.82:
				img.set_pixel(x, y, c("ink"))
			elif q < 1.0:
				img.set_pixel(x, y, stone[0])
	_outline(img, mask, c("ink"))
	# Moss along the ledge's rim.
	for x in w:
		for y in h:
			if mask[y * w + x] == 1:
				if img.get_pixel(x, y) != c("ink") and rng.randf() < 0.3:
					img.set_pixel(x, y, c("leaf.3") if rng.randf() < 0.6 else c("leaf.2"))
				break
	return img


## A curtain of lichen hanging over the leader's den: a full top row and
## strands of uneven length, light at the top, darker towards the tips.
func lichen(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var leaf := ramp("leaf")
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var edge := mini(x, w - 1 - x)
		var n := h if edge >= 2 and rng.randf() < 0.55 else rng.randi_range(2, h - 1)
		if edge == 0:
			n = mini(n, 2)
		if x % 2 == 1 and rng.randf() < 0.4:
			n = rng.randi_range(1, 3)
		for y in n:
			var b := 1.0 - float(y) / float(h)
			var col := leaf[clampi(1 + level(b, 4, x, y), 1, 4)]
			img.set_pixel(x, y, col)
		if n >= 3:
			img.set_pixel(x, n - 1, leaf[0])
	return img


## A worn patch of bare earth (the deputy's spot): a flat dirt ellipse with
## a dithered, trampled rim fading into the grass.
func worn_patch(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dirt := ramp("dirt")
	var ctr := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - ctr) / ctr).length()
			if d > 1.0:
				continue
			if d > 0.75 and dither(x, y) < (d - 0.75) * 4.0:
				continue
			var col: Color = dirt[1] if d < 0.5 and dither(x, y) < 0.5 else dirt[0]
			if d > 0.75:
				col = c("dirt_edge")
			img.set_pixel(x, y, col)
	return img


## The apprentices' den from outside: a fern clump (a flat-bottomed foliage
## dome) with a dark arched entrance `gap` px wide and `gap_h` high in the
## middle of its base, facing the clearing.
func den_fern(w: int, h: int, seed: int, gap: int = 34, gap_h: int = 22) -> Image:
	var img := foliage(w, h, seed, 9, 0, true)
	var leaf := ramp("leaf")
	var cx := w / 2.0
	var half := gap / 2.0
	for y in range(h - gap_h - 2, h):
		for x in range(int(cx - half) - 2, int(cx + half) + 2):
			if x < 0 or x >= w:
				continue
			var q := Vector2((x + 0.5 - cx) / half, (y + 0.5 - h) / float(gap_h)).length()
			if q < 0.86:
				img.set_pixel(x, y, c("ink"))
			elif q < 1.0:
				img.set_pixel(x, y, leaf[0])
			elif q < 1.12 and img.get_pixel(x, y).a > 0.0:
				# Fronds curling over the entrance.
				img.set_pixel(x, y, leaf[3] if dither(x, y) < 0.5 else leaf[2])
	return img


## Periodic soft noise 0..1 (tiles every `w` x `h` px).
static func _wrap_noise(x: float, y: float, w: float, h: float, a: float, b: float) -> float:
	var u := TAU * x / w
	var v := TAU * y / h
	return clampf(0.5 + 0.22 * sin(u + a) * cos(v * 2.0 + b) + 0.18 * sin(u * 2.0 + v + b) + 0.1 * cos(u * 3.0 - v * 2.0 + a), 0.0, 1.0)


## Den floor tile (tileable): packed warm earth with moss specks and a few
## pebbles. The den's floor_color tints it.
func den_floor(size: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var shades: Array[Color] = [c("dirt_edge"), c("dirt_edge"), c("dirt.0")]
	var a := rng.randf() * TAU
	var b := rng.randf() * TAU
	for y in size:
		for x in size:
			img.set_pixel(x, y, shades[level(_wrap_noise(x, y, size, size, a, b), 3, x, y, 0.35)])
	for i in 9:
		var p := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
			if rng.randf() < 0.8:
				img.set_pixelv((p + o) % size, c("leaf.1") if rng.randf() < 0.6 else c("leaf.2"))
	for i in 3:
		var p := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		img.set_pixelv(p, c("stone.1"))
		img.set_pixelv((p + Vector2i(1, 0)) % size, c("stone.2"))
	return img


## What lies beyond a den's walls (tileable): dense dark undergrowth.
func den_outer(size: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var a := rng.randf() * TAU
	var b := rng.randf() * TAU
	for y in size:
		for x in size:
			var v := _wrap_noise(x, y, size, size, a, b)
			img.set_pixel(x, y, c("ink") if level(v, 2, x, y) == 0 else c("leaf.0"))
	return img


## One wall band of a den, fern and moss (tileable along x): dark depth at
## the top, fronds hanging towards the room, a mossy lip at the bottom edge.
## Side walls are this rotated, the bottom wall this flipped.
func den_wall_fern_moss(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var leaf := ramp("leaf")
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := float(y) / float(maxi(1, h - 1))
			img.set_pixel(x, y, c("ink") if d < 0.25 and dither(x, y) > d * 3.0 else leaf[0] if d < 0.6 or dither(x, y) > (d - 0.6) * 2.5 else leaf[1])
	# Fronds: a stem with leaflets every other row, wrapping round the tile.
	var fronds := maxi(2, w / 7)
	for f in fronds:
		var x0 := float(f) * float(w) / float(fronds) + rng.randf_range(-2.0, 2.0)
		var reach := rng.randf_range(0.55, 0.95) * h
		var bend := rng.randf_range(-3.0, 3.0)
		for y in int(reach):
			var t := float(y) / reach
			var x := int(roundf(x0 + bend * t * t))
			var shade := leaf[2] if t < 0.5 else leaf[3]
			img.set_pixel(posmod(x, w), y, shade)
			if y % 2 == 1 and y > 1:
				var span := 1 + int((1.0 - absf(t - 0.5)) * 1.5)
				for k in range(1, span + 1):
					img.set_pixel(posmod(x - k, w), y, leaf[2])
					img.set_pixel(posmod(x + k, w), y, leaf[3] if k == 1 else leaf[2])
	# Mossy lip along the bottom edge.
	var a := rng.randf() * TAU
	for x in w:
		var lip := 2 + int(roundf(1.5 + 1.5 * sin(TAU * x / w * 2.0 + a)))
		for y in range(h - lip, h):
			img.set_pixel(x, y, leaf[4] if y == h - lip and dither(x, y) < 0.6 else leaf[3])
	return img


func den_wall_side(w: int, h: int, seed: int) -> Image:
	# A band h long and w deep: painted as a top band, turned so the moss
	# faces the room (the left wall; the right wall is drawn mirrored).
	var img := den_wall_fern_moss(h, w, seed)
	img.rotate_90(COUNTERCLOCKWISE)
	return img


func den_wall_bottom(w: int, h: int, seed: int) -> Image:
	var img := den_wall_fern_moss(w, h, seed)
	img.flip_y()
	return img


## A nest: a ring of moss round a soft hollow. `mine` adds a white feather,
## so Fern's nest is easy to find.
func den_nest(w: int, h: int, mine: bool = false) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var leaf := ramp("leaf")
	var ctr := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - ctr) / ctr).length()
			if d > 1.0:
				continue
			var col: Color
			if d > 0.6:
				var lit := y < h / 2 and x < w * 0.6
				col = leaf[4] if lit and dither(x, y) < 0.5 else leaf[3]
				if d > 0.9:
					col = leaf[2]
			else:
				col = leaf[1] if dither(x, y) < 0.6 else c("dirt_edge")
			img.set_pixel(x, y, col)
	if mine:
		# A feather lying across the hollow.
		var pts := [Vector2i(w / 2 - 4, h / 2 + 1), Vector2i(w / 2 - 3, h / 2 + 1), Vector2i(w / 2 - 2, h / 2), Vector2i(w / 2 - 1, h / 2),
			Vector2i(w / 2, h / 2), Vector2i(w / 2 + 1, h / 2 - 1), Vector2i(w / 2 + 2, h / 2 - 1), Vector2i(w / 2 + 3, h / 2 - 2)]
		for i in pts.size():
			img.set_pixelv(pts[i], c("ink") if i < 2 else c("flower.white"))
		for p in [Vector2i(w / 2 - 1, h / 2 - 1), Vector2i(w / 2 + 1, h / 2), Vector2i(w / 2 + 2, h / 2)]:
			img.set_pixelv(p, c("stone.3"))
	return img


## Rogue bedding: torn, flattened scraps of moss with bare earth showing
## through, a few loose bits around (seeded, so it is deterministic).
func bedding_scraps(w: int, h: int, seed: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var leaf := ramp("leaf")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var blobs: Array = []
	for i in 3:
		blobs.append([Vector2(rng.randf_range(w * 0.25, w * 0.75), rng.randf_range(h * 0.35, h * 0.65)),
			Vector2(rng.randf_range(w * 0.18, w * 0.3), rng.randf_range(h * 0.28, h * 0.42))])
	for y in h:
		for x in w:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var best := 9.0
			for b in blobs:
				best = minf(best, ((p - b[0]) / b[1]).length())
			if best > 1.0:
				continue
			if best > 0.7 and dither(x, y) < (best - 0.7) * 3.0:
				continue
			var col: Color = leaf[1] if dither(x + 3, y) < 0.55 else leaf[2]
			if best < 0.45 and dither(x, y + 1) < 0.35:
				col = c("dirt_edge")
			elif y < h / 2 and dither(x, y) < 0.2:
				col = leaf[3]
			img.set_pixel(x, y, col)
	for i in 5:
		var q := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if img.get_pixelv(q).a == 0.0:
			img.set_pixelv(q, leaf[2])
	return img


## Old bones on the ground: a long bone and a short one, pale with an ink
## outline.
func bones(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fill := {}
	var light := c("flower.white")
	var shade := c("stone.3")
	# Long bone, left-right, with knobbed ends.
	var y0 := h - 3
	for x in range(2, w - 3):
		fill[Vector2i(x, y0)] = light
	for p in [Vector2i(1, y0 - 1), Vector2i(1, y0 + 1), Vector2i(w - 3, y0 - 1), Vector2i(w - 3, y0 + 1)]:
		fill[p] = shade
	# Short bone, slanting.
	for i in 4:
		fill[Vector2i(3 + i, 2 + i / 2)] = light
	fill[Vector2i(2, 1)] = shade
	fill[Vector2i(7, 4)] = shade
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if fill.has(p):
				continue
			for d in _N4:
				if fill.has(p + d):
					img.set_pixel(x, y, c("ink"))
					break
	for p: Vector2i in fill:
		img.set_pixelv(p, fill[p])
	return img


## A fallen log lying left-right, with a cut end showing rings on the right.
func log_art(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bark := ramp("bark")
	var ink := c("ink")
	var mask := PackedByteArray()
	mask.resize(w * h)
	var r := h / 2.0
	for y in h:
		for x in w - 1:
			var t := float(y) / (h - 1)
			var col := bark[2] if t < 0.3 else (bark[1] if t < 0.7 else bark[0])
			if (x * 5 + y * 9) % 13 == 0:
				col = bark[0]
			img.set_pixel(x, y, col)
			mask[y * w + x] = 1
	# Cut end: an ellipse of pale wood with rings.
	var end_c := Vector2(w - r * 0.6 - 1, r)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5 - end_c.x) / (r * 0.6), (y + 0.5 - end_c.y) / r)
			var q := d.length()
			if q < 1.0:
				mask[y * w + x] = 1
				img.set_pixel(x, y, c("dirt.2") if fmod(q * 3.0, 1.0) > 0.35 else c("dirt.0"))
	_outline(img, mask, ink)
	# A sprig of moss.
	for x in range(3, mini(w - 6, 9)):
		img.set_pixel(x, 1, c("leaf.3"))
	return img


## The pond: an irregular ellipse of water (deep in the middle) with a dark
## wet edge and a stony bank. The shimmer is a shader (pond.gdshader); it
## finds water pixels by colour (blue-dominant).
func pond(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var water := ramp("water")
	var stone := ramp("stone")
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.08
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c0 := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := (Vector2(x + 0.5, y + 0.5) - c0) / (c0 - Vector2(1, 1))
			var q := d.length() + noise.get_noise_2d(x, y) * 0.08
			if q >= 1.0:
				continue
			if q > 0.9:
				# Bank: pebbles, lit on the far (upper) side.
				img.set_pixel(x, y, stone[2] if d.y < 0.0 and rng.randf() < 0.6 else stone[1] if rng.randf() < 0.7 else stone[0])
			elif q > 0.84:
				img.set_pixel(x, y, c("ink").lerp(water[0], 0.35))
			else:
				var depth := 1.0 - q / 0.84
				# Reflected sky is lighter towards the bottom (the near side).
				var v := clampf(0.25 + (d.y + 1.0) * 0.3 - depth * 0.3, 0.0, 1.0)
				img.set_pixel(x, y, water[level(v, 3, x, y)])
	return img


# --- Small decor


## Tall grass: a clump of blades Fern walks through (drawn in front of her
## feet, y-sorted). Bottom-centre is the base.
## `grass` names the palette ramp: "grass" (camp) or "grass_gold" (the
## Hunting Grounds); "<grass>_dark" / "<grass>_light" go with it.
func tall_grass(w: int, h: int, seed: int, grass: String = "grass") -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shades := [c(grass + "_dark"), c(grass + ".0"), c(grass + ".2"), c(grass + "_light")]
	for b in 6:
		var x := float(rng.randi_range(1, w - 2))
		var lean := rng.randf_range(-0.35, 0.35)
		var top := rng.randi_range(1, h / 3)
		var col: Color = shades[rng.randi_range(0, 3)]
		for y in range(h - 1, top - 1, -1):
			var px := int(roundf(x + lean * (h - 1 - y)))
			if px >= 0 and px < w:
				img.set_pixel(px, y, col if y > top else shades[3])
		# Darker base so the clump sits on the ground.
	for x in range(1, w - 1):
		img.set_pixel(x, h - 1, shades[0])
	return img


## A short grass tuft (scattered decor).
func tuft(seed: int, grass: String = "grass") -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	var rows := ["..d.d..", ".dd.dd.", "ddldd.d", ".dddld.", "..ddd.."]
	for y in rows.size():
		for x in 7:
			match rows[y][x]:
				"d":
					img.set_pixel(x, y, c(grass + "_dark"))
				"l":
					img.set_pixel(x, y, c(grass + ".0"))
	return img


## A flower: petals of a palette colour around a centre, on a short stem.
func flower(color_name: String) -> Image:
	var img := Image.create(5, 7, false, Image.FORMAT_RGBA8)
	var petal := c("flower." + color_name)
	var rows := [".p.p.", "ppcpp", ".ppp.", "..s..", ".ls..", "..s..", "....."]
	for y in rows.size():
		for x in 5:
			match rows[y][x]:
				"p":
					img.set_pixel(x, y, petal)
				"c":
					img.set_pixel(x, y, c("flower.center"))
				"s":
					img.set_pixel(x, y, c("grass_dark"))
				"l":
					img.set_pixel(x, y, c("grass.1"))
	return img


## A butterfly sheet: 2 frames (wings open / closed), white, tinted in game.
func butterfly() -> Image:
	var rows := [
		"ww...ww" + "...w...",
		"wwwiwww" + "..wiw..",
		".wwiww." + "..wiw..",
		"ww.i.ww" + "...i...",
		".......",
	]
	var img := Image.create(14, 5, false, Image.FORMAT_RGBA8)
	for y in 4:
		var row: String = rows[y]
		for x in 14:
			match row[x]:
				"w":
					img.set_pixel(x, y, Color.WHITE)
				"i":
					img.set_pixel(x, y, c("ink"))
	return img


## A bird's shadow passing overhead: 2 frames (wings up / down).
func bird_shadow() -> Image:
	var rows := [
		"o.....o........" + "...............",
		"oo...oo........" + "...............",
		".ooooo..." + "......" + "ooooooooooooo..",
		"..ooo.........." + "....ooooo......",
		"...o..........." + ".....ooo.......",
	]
	var img := Image.create(30, 5, false, Image.FORMAT_RGBA8)
	var col := c("shadow", 0.32)
	for y in rows.size():
		var row: String = rows[y]
		for x in mini(30, row.length()):
			if row[x] == "o":
				img.set_pixel(x, y, col)
	return img


## A soft drop shadow: two dithered alpha rings in the shadow colour.
func shadow(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c0 := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var q := ((Vector2(x + 0.5, y + 0.5) - c0) / c0).length()
			if q < 0.62:
				img.set_pixel(x, y, c("shadow", 0.34))
			elif q < 1.0 and (q < 0.82 or dither(x, y) < 0.5):
				img.set_pixel(x, y, c("shadow", 0.2))
	return img


## A cloud's shadow on the meadow: big, faint, dithered edges.
func cloud_shadow(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var circles: Array[Vector3] = []
	for i in 7:
		circles.append(Vector3(rng.randf_range(w * 0.25, w * 0.75), rng.randf_range(h * 0.35, h * 0.65), rng.randf_range(h * 0.22, h * 0.4)))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var col := c("shadow", 0.13)
	for y in h:
		for x in w:
			var best := 9.0
			for ci in circles:
				best = minf(best, Vector2(x - ci.x, y - ci.y).length() / ci.z)
			if best < 0.85 or (best < 1.0 and dither(x, y) < (1.0 - best) / 0.15 * 0.8):
				img.set_pixel(x, y, col)
	return img


func _outline(img: Image, mask: PackedByteArray, ink: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or mask[ny * w + nx] == 0:
					img.set_pixel(x, y, ink)
					break


# --- Ground


## The meadow floor from world.json: 3-4 grass shades in soft noise patches
## (dither-blended), a worn dirt path along world.json "path" lines with a
## trampled edge, and a few dark specks. One image the size of the world.
func ground(world: Dictionary) -> Image:
	var size: Array = world.get("size", [720, 405])
	var w := int(size[0])
	var h := int(size[1])
	var g: Dictionary = world.get("ground_paint", {})
	var seed := int(g.get("seed", 1))
	# Which grass ramp ("grass", or "grass_gold" for the Hunting Grounds).
	var gname := str(g.get("ramp", "grass"))
	var grass := ramp(gname)
	var dirt := ramp("dirt")
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(g.get("patch_frequency", 0.011))
	noise.fractal_octaves = 2
	var fine := FastNoiseLite.new()
	fine.seed = seed + 7
	fine.frequency = 0.15

	# Distance to the nearest path line, only near the lines.
	var path: Dictionary = world.get("path", {})
	var half := float(path.get("width", 10)) / 2.0
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	dist.fill(INF)
	for line in path.get("lines", []):
		for i in range(line.size() - 1):
			var a := Vector2(line[i][0], line[i][1])
			var b := Vector2(line[i + 1][0], line[i + 1][1])
			var reach := half + 4.0
			var lo := Vector2i((a.min(b) - Vector2.ONE * reach).floor()).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
			var hi := Vector2i((a.max(b) + Vector2.ONE * reach).ceil()).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var p := Vector2(x + 0.5, y + 0.5)
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					if d < dist[y * w + x]:
						dist[y * w + x] = d

	# A stream (Hunting Grounds 2): water along a polyline, a pebbly bank,
	# and past it (the border's side) another Clan's grass.
	var st: Dictionary = world.get("stream", {})
	var sline: Array = st.get("points", [])
	var shalf := float(st.get("width", 14)) / 2.0
	var sbank := float(st.get("bank", 3))
	var bd: Dictionary = world.get("territory", {})
	var far_name := str(bd.get("ramp", gname))
	var far := ramp(far_name)
	var water := ramp("water")
	var stone := ramp("stone")

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in h:
		for x in w:
			var v := (noise.get_noise_2d(x, y) + 1.0) / 2.0
			var col: Color = grass[level(clampf((v - 0.5) * 1.25 + 0.5, 0.0, 0.999), grass.size(), x, y, 0.9)]
			if not sline.is_empty():
				var sy := _poly_y(sline, x + 0.5) + fine.get_noise_2d(x * 0.5, 300.0) * 1.2
				var sd := absf(y + 0.5 - sy)
				if str(bd.get("side", "")) == "north" and y + 0.5 < sy:
					col = far[level(clampf((v - 0.5) * 1.25 + 0.5, 0.0, 0.999), far.size(), x, y, 0.9)]
				if sd < shalf - sbank:
					# Darker in the middle; light glints by dither.
					var depth := 1.0 - sd / maxf(1.0, shalf - sbank)
					var wv := clampf(0.55 - depth * 0.45 + fine.get_noise_2d(x * 1.5, y * 3.0) * 0.25, 0.0, 0.999)
					col = water[level(wv, 4, x, y)]
					if fine.get_noise_2d(x * 0.6 + 50.0, y * 2.0) > 0.42 and dither(x, y) < 0.3:
						col = water[4]
					img.set_pixel(x, y, col)
					continue
				elif sd < shalf:
					col = stone[2] if y + 0.5 < sy and dither(x, y) < 0.6 else stone[1] if dither(x + 1, y) < 0.7 else stone[0]
					img.set_pixel(x, y, col)
					continue
				elif sd < shalf + 1.5 and dither(x, y) < 0.5:
					col = c((far_name if y + 0.5 < sy else gname) + "_dark")
					img.set_pixel(x, y, col)
					continue
			var d: float = dist[y * w + x] + fine.get_noise_2d(x, y) * 1.6
			if d < half - 1.0:
				var dv := (fine.get_noise_2d(x * 0.7 + 100.0, y * 0.7) + 1.0) / 2.0
				col = dirt[level(dv, dirt.size(), x, y, 1.0)]
			elif d < half:
				col = c("dirt_edge")
			elif d < half + 2.0 and dither(x, y) < 0.5:
				col = c(gname + "_dark")
			img.set_pixel(x, y, col)
	# Specks: tiny darker / lighter dots so big patches don't look flat.
	for i in w * h / 90:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if dist[p.y * w + p.x] > half + 2.0:
			var r := rng.randf()
			if not sline.is_empty() and absf(p.y + 0.5 - _poly_y(sline, p.x + 0.5)) < shalf + 2.0:
				continue
			var gn := far_name if not sline.is_empty() and str(bd.get("side", "")) == "north" and p.y + 0.5 < _poly_y(sline, p.x + 0.5) else gname
			img.set_pixelv(p, c(gn + "_dark") if r < 0.6 else c(gn + "_light"))
	return img


## y of a left-to-right polyline ([[x, y], ...]) at x, clamped at its ends.
static func _poly_y(line: Array, x: float) -> float:
	if x <= float(line[0][0]):
		return float(line[0][1])
	for i in range(line.size() - 1):
		var b: Array = line[i + 1]
		if x <= float(b[0]):
			var a: Array = line[i]
			var u := (x - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), u)
	return float(line[line.size() - 1][1])


## Bracken: a few arching rust-brown fronds (the plants along a border's
## far bank). Bottom-centre is the base.
func bracken(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shades := ramp("bracken")
	var cx := (w - 1) / 2.0
	# Fronds: up the middle, and arching out to each side, tips drooping.
	var fronds := [[0.0, 1.0, 0.0], [-1.0, 0.8, 0.35], [1.0, 0.85, 0.35], [-0.5, 0.95, 0.15]]
	for f in fronds:
		var dir: float = f[0] + rng.randf_range(-0.15, 0.15)
		var tall: float = (h - 1) * f[1]
		var droop: float = h * f[2]
		var steps := h * 3
		for i in steps:
			var t := float(i) / float(steps - 1)
			var x := cx + dir * sin(t * 1.6) * (w / 2.0 - 0.5)
			var y := (h - 1) - t * tall + droop * t * t * t
			var px := clampi(int(roundf(x)), 0, w - 1)
			var py := clampi(int(roundf(y)), 0, h - 1)
			img.set_pixelv(Vector2i(px, py), shades[1] if t < 0.5 else shades[2])
			# Leaflets: pale ticks either side, more towards the tip.
			if t > 0.3 and i % 4 == 0:
				for side in [-1, 1]:
					var lx: int = clampi(px + side, 0, w - 1)
					var ly: int = clampi(py - 1 if absf(dir) < 0.5 else py + (1 if side * dir > 0.0 else -1), 0, h - 1)
					if img.get_pixel(lx, ly).a == 0.0:
						img.set_pixel(lx, ly, shades[3] if t > 0.6 else shades[2])
	for x in range(1, w - 1):
		if img.get_pixel(x, h - 1).a == 0.0 and dither(x, h) < 0.4:
			img.set_pixel(x, h - 1, shades[0])
	return img


## Where a path leaves the area: the worn path carried on into the forest
## floor past the painted ground, dithering away (w x h, the path's width).
## Drawn so the left end joins the meadow; flip it for an exit on the left.
func trail(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dirt := ramp("dirt")
	for y in h:
		for x in w:
			var fade := pow(float(x) / float(w), 1.4)
			if dither(x, y) < fade * 1.1:
				continue
			var edge := y == 0 or y == h - 1
			# Narrower as it goes: the edges give out first.
			if (y <= 1 or y >= h - 2) and dither(x + 2, y) < fade * 2.0:
				continue
			img.set_pixel(x, y, c("dirt_edge") if edge else dirt[0 if dither(x, y + 1) < 0.5 else 1])
	return img


## Fern's den in camp (where she wakes after passing out): an oval nest of
## bracken and moss, darker inside, a flat ground decal.
func den(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var leaf := ramp("leaf")
	var dirt := ramp("dirt")
	var ctr := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - ctr) / ctr).length()
			if d > 1.0:
				continue
			var col: Color
			if d > 0.72:
				# The rim: bracken, lit from the upper left.
				var lit := y < h / 2 and x < w * 0.6
				col = leaf[3] if lit and dither(x, y) < 0.6 else leaf[2]
				if d > 0.93:
					col = leaf[1]
			elif d > 0.58:
				col = leaf[1] if dither(x, y) < 0.5 else dirt[0]
			else:
				col = dirt[0] if dither(x, y) < 0.7 else c("dirt_edge")
			img.set_pixel(x, y, col)
	return img


## A firefly: a bright plus-shaped core with a soft dithered glow (7x7).
func firefly() -> Image:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	var col := c("firefly")
	for y in 7:
		for x in 7:
			var d := Vector2(x - 3, y - 3).length()
			if d < 1.01:
				img.set_pixel(x, y, Color(col.lightened(0.6), 1.0))
			elif d < 1.5:
				img.set_pixel(x, y, Color(col, 0.7))
			elif d < 2.3:
				img.set_pixel(x, y, Color(col, 0.35))
			elif d < 3.2 and dither(x, y) < 0.5:
				img.set_pixel(x, y, Color(col, 0.18))
	return img


# --- Needs: the fresh-catch pile, HUD icons, drinking ripple


## Stamps a character grid at `at` ("." = clear; other characters map to
## palette paths through `cols`), optionally mirrored.
func _stamp(img: Image, rows: Array, cols: Dictionary, at: Vector2i, flip: bool = false) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or not cols.has(ch):
				continue
			var px := at.x + (row.length() - 1 - x if flip else x)
			var py := at.y + y
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, c(cols[ch]))


## A small mouse / vole lying on its side (fresh-kill), facing left.
const PREY_ROWS := [
	"..oo......",
	".obbooo...",
	"oebbbbbo..",
	"nbblllbott",
	".oooooo...",
]
const PREY_COLS := {"o": "ink", "b": "prey.1", "l": "prey.2", "e": "ink", "n": "prey_tail", "t": "prey_tail"}
## Where each prey lies on the pile (bottom row first), frame-local.
const PILE_SLOTS := [Vector2i(3, 8), Vector2i(12, 9), Vector2i(19, 8), Vector2i(7, 5), Vector2i(15, 4), Vector2i(0, 5), Vector2i(20, 4), Vector2i(11, 1)]


## The fresh-catch pile: a sheet of `count + 1` frames (`w` x `h`), frame n
## showing n prey on a bed of dry leaves (frame 0 = the empty bed).
## Origin (feet) is the bottom-centre of a frame.
func fresh_catch(count: int, w: int, h: int) -> Image:
	var img := Image.create(w * (count + 1), h, false, Image.FORMAT_RGBA8)
	var bed := [c("dirt_edge"), c("dirt.0"), c("dirt.1"), c("leaf.2")]
	for f in count + 1:
		var ox := f * w
		var c0 := Vector2(w / 2.0, h - 3.0)
		var rad := Vector2(w / 2.0 - 1.0, 3.0)
		var mask := PackedByteArray()
		mask.resize(w * h)
		var frame := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var q := ((Vector2(x + 0.5, y + 0.5) - c0) / rad).length()
				if q < 1.0:
					var v := clampf(0.8 - (y - (c0.y - rad.y)) / (rad.y * 2.0) * 0.7, 0.0, 1.0)
					frame.set_pixel(x, y, bed[level(v, 3, x, y)])
					mask[y * w + x] = 1
		# A few green leaves in the bed.
		for p in [Vector2i(5, h - 3), Vector2i(w - 7, h - 4), Vector2i(w / 2, h - 2)]:
			frame.set_pixel(p.x, p.y, bed[3])
		_outline(frame, mask, c("ink"))
		for i in mini(f, PILE_SLOTS.size()):
			_stamp(frame, PREY_ROWS, PREY_COLS, PILE_SLOTS[i], i % 2 == 1)
		img.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i(ox, 0))
	return img


## HUD icon for hunger: a mouse, 11x9.
func icon_prey() -> Image:
	var img := Image.create(11, 9, false, Image.FORMAT_RGBA8)
	_stamp(img, [
		"...oo......",
		"..oppo.....",
		".obbbbooo..",
		"obebbbbbbo.",
		"nbbbbbbbbbo",
		"oblllllllbo",
		".ooooooooo.",
		".......ott.",
		"........tt.",
	], {"o": "ink", "b": "prey.1", "l": "prey.2", "e": "ink", "p": "prey_tail", "n": "prey_tail", "t": "prey_tail"}, Vector2i.ZERO)
	return img


## HUD icon for thirst: a water drop, 9x9 (same height as the mouse).
func icon_drop() -> Image:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	_stamp(img, [
		"....o....",
		"...oho...",
		"..ohmmo..",
		".ohmmmmo.",
		"ohmmmmmmo",
		"ommmmmmdo",
		"ommmmmddo",
		".odddddo.",
		"..ooooo..",
	], {"o": "ink", "h": "water.4", "m": "water.2", "d": "water.1"}, Vector2i.ZERO)
	return img


## A ripple where Fern laps the water: 3 frames of a widening ring, w x h.
func ripple(w: int, h: int) -> Image:
	var img := Image.create(w * 3, h, false, Image.FORMAT_RGBA8)
	var c0 := Vector2(w, h) / 2.0
	for f in 3:
		var r := (0.4 + f * 0.3)
		for y in h:
			for x in w:
				var q := ((Vector2(x + 0.5, y + 0.5) - c0) / c0).length()
				if absf(q - r) < 0.14:
					img.set_pixel(f * w + x, y, c("water.4", 1.0 - f * 0.3))
	return img


# --- Hunting: the live mouse, the carried mouse, the "!" and the landing ring

## A live mouse, side view facing right, 12x8 frames (feet on the bottom
## row): 0-1 head down nibbling, 2 head up with ears up (looking around),
## 3-4 running.
const MOUSE_FRAMES := [
	[
		"............",
		"............",
		"..ooooo.....",
		".obbbbbooo..",
		"obbbbbbbbbo.",
		"obllllbbbbeo",
		"toollllobbbn",
		"t..oo..oo...",
	],
	[
		"............",
		"............",
		"..ooooo.....",
		".obbbbbooo..",
		"obbbbbbbbbo.",
		"obllllbbbbeo",
		"toollllobbno",
		"t..oo..oo...",
	],
	[
		"........o.o.",
		".......onono",
		"..oooo.obbbo",
		".obbbboobbeo",
		"obbbbbbbbbbn",
		"obllllllbbo.",
		"toollllloo..",
		"t..oo..oo...",
	],
	[
		"............",
		"............",
		"............",
		"...ooooooo..",
		"toobbbbbbbbo",
		"t.obllllbben",
		"...oooooooo.",
		"..o......o..",
	],
	[
		"............",
		"............",
		"............",
		"...ooooooo..",
		"toobbbbbbbbo",
		"t.obllllbben",
		"...oooooooo.",
		"....o..o....",
	],
]
const MOUSE_COLS := {"o": "ink", "b": "prey.1", "l": "prey.2", "e": "ink", "n": "prey_tail", "t": "prey_tail"}


func mouse() -> Image:
	var fw := 12
	var img := Image.create(fw * MOUSE_FRAMES.size(), 8, false, Image.FORMAT_RGBA8)
	for f in MOUSE_FRAMES.size():
		var rows: Array = []
		for r: String in MOUSE_FRAMES[f]:
			rows.append(r.substr(0, fw))
		_stamp(img, rows, MOUSE_COLS, Vector2i(f * fw, 0))
	return img


## The mouse in Fern's mouth: limp, on its side (the fresh-kill look), 10x5.
func mouse_carried() -> Image:
	var img := Image.create(10, 5, false, Image.FORMAT_RGBA8)
	_stamp(img, PREY_ROWS, PREY_COLS, Vector2i.ZERO, true)
	return img


## "!" over a mouse that has its head up: 3x8, yellow on ink.
func alert_mark() -> Image:
	var img := Image.create(3, 8, false, Image.FORMAT_RGBA8)
	_stamp(img, ["ooo", "oyo", "oyo", "oyo", "ooo", "ooo", "oyo", "ooo"], {"o": "ink", "y": "ui.select"}, Vector2i.ZERO)
	return img


## The landing circle under a mouse Fern can pounce on: a flat ring of ink
## and paper dashes (reads on green and golden grass alike).
func pounce_ring(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - ctr) / ctr).length()
			if d <= 1.0 and d > 0.62:
				var ang := atan2(y + 0.5 - ctr.y, x + 0.5 - ctr.x)
				if posmod(int(floor((ang + PI) / TAU * 12.0)), 2) == 0:
					img.set_pixel(x, y, c("ink"))
				else:
					img.set_pixel(x, y, c("ui.paper"))
	return img


## Rank symbols (11x11): a 9x9 shape inside a 1 px ink outline (4-way, so
## corners round off), so they read over grass, sand and the dialogue paper
## alike. "c" = claws (paper spikes), "y" gold, "g" / "d" leaf; the deputy
## adds a tiny gold star in the corner.
const RANK_SHAPES := {
	"kit": [
		"w.w......",
		".........",
		"www......",
		"www......",
		".....w.w.",
		".........",
		".....www.",
		".....www.",
		"........."],
	"apprentice": [
		"..ww.ww..",
		"..ww.ww..",
		".........",
		"ww.....ww",
		"ww.www.ww",
		"..wwwww..",
		".wwwwwww.",
		".wwwwwww.",
		"..wwwww.."],
	"warrior": [
		".c.c.c.c.",
		"..c...c..",
		"..ww.ww..",
		"c.ww.ww.c",
		"c.......c",
		"ww.www.ww",
		"..wwwww..",
		".wwwwwww.",
		"..wwwww.."],
	"deputy": [
		".c.c.c.c.",
		"..c...c..",
		"..ww.ww..",
		"c.ww.ww.c",
		"c.......c",
		"ww.www.ww",
		"..wwwww..",
		".wwwwwww.",
		"..wwwww.."],
	"medicine": [
		".......gg",
		".....gggg",
		"....ggggg",
		"...gggdgg",
		"..gggdgg.",
		".gggdgg..",
		".ggdgg...",
		".gdg.....",
		"d........"],
	"leader": [
		"....y....",
		"....y....",
		"...yyy...",
		"yyyyyyyyy",
		".yyyyyyy.",
		"..yyyyy..",
		"..yyyyy..",
		".yyy.yyy.",
		".yy...yy."],
}
const RANK_COLOURS := {"w": "ui.paper", "c": "ui.paper", "y": "ui.select", "g": "leaf.4", "d": "leaf.2"}
const _N4 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]


func rank_icon(kind: String) -> Image:
	var rows: Array = RANK_SHAPES[kind]
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	var fill := {}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] != ".":
				fill[Vector2i(x + 1, y + 1)] = row[x]
	if kind == "deputy":
		# A tiny gold star (a plus) in the top-right corner.
		for p in [Vector2i(9, 0), Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1), Vector2i(9, 2)]:
			fill[p] = "y"
		fill.erase(Vector2i(7, 1))
		fill.erase(Vector2i(7, 2))
	_outline_fill(img, fill)
	return img


## The patrol icon over a cat that could go on a patrol: a small paper
## chevron ("out we go") with an ink outline, 7x7. `picked`: inside a gold
## ring (13x13), for the cats the deputy sends.
const PATROL_SHAPE := ["ww...", ".ww..", "..ww.", ".ww..", "ww..."]


func patrol_icon(picked: bool = false) -> Image:
	var n := 13 if picked else 7
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var at := Vector2i(4, 4) if picked else Vector2i(1, 1)
	var fill := {}
	for y in PATROL_SHAPE.size():
		for x in PATROL_SHAPE[y].length():
			if PATROL_SHAPE[y][x] != ".":
				fill[at + Vector2i(x, y)] = "w"
	if picked:
		var ctr := Vector2(n, n) / 2.0
		for y in n:
			for x in n:
				var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(ctr)
				if d >= 4.7 and d < 5.9:
					fill[Vector2i(x, y)] = "y"
	_outline_fill(img, fill)
	return img


const WAY_SHAPE := ["ww...ww...", ".ww...ww..", "..ww...ww.", "...ww...ww", "..ww...ww.", ".ww...ww..", "ww...ww..."]


## A double chevron (">>", 12x9 with its outline): "this way", over the
## story exit after the rogue points the way.
func way_arrow() -> Image:
	var img := Image.create(12, 9, false, Image.FORMAT_RGBA8)
	var fill := {}
	for y in WAY_SHAPE.size():
		for x in WAY_SHAPE[y].length():
			if WAY_SHAPE[y][x] != ".":
				fill[Vector2i(1 + x, 1 + y)] = "w"
	_outline_fill(img, fill)
	return img


## A border marking spot on the ground (w x h, an ellipse seen from
## above). Unmarked: a dashed pale ring ("mark here"). Marked: the ring
## drawn solid in rust and filled in with a darker scent patch.
func scent_ring(w: int, h: int, marked: bool = false) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var d := ((Vector2(x, y) + Vector2(0.5, 0.5) - ctr) / (ctr - Vector2(0.5, 0.5))).length()
			if d > 1.0:
				continue
			var edge := d > 0.62
			var ang := atan2((y + 0.5 - ctr.y) * w / float(h), x + 0.5 - ctr.x)
			if edge:
				if marked:
					img.set_pixel(x, y, c("bracken.1"))
				elif int(floorf((ang + PI) / TAU * 12.0)) % 2 == 0:
					# Pale dashes with a dark lower lip, so they read on
					# any grass.
					var below := ((Vector2(x, y + 1) + Vector2(0.5, 0.5) - ctr) / (ctr - Vector2(0.5, 0.5))).length()
					img.set_pixel(x, y, c("ink", 0.7) if below > 1.0 or (y + 0.5 > ctr.y and d > 0.9) else c("ui.paper"))
			elif marked and dither(x, y) < 0.75:
				img.set_pixel(x, y, c("bracken.0", 0.55))
	return img


## Paints `fill` (pixel -> RANK_COLOURS key) with an ink outline round it.
func _outline_fill(img: Image, fill: Dictionary) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2i(x, y)
			if fill.has(p):
				continue
			for d in _N4:
				if fill.has(p + d):
					img.set_pixel(x, y, c("ink"))
					break
	for p: Vector2i in fill:
		img.set_pixel(p.x, p.y, c(RANK_COLOURS[fill[p]]))

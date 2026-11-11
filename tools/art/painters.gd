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
func tall_grass(w: int, h: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shades := [c("grass_dark"), c("grass.0"), c("grass.2"), c("grass_light")]
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
func tuft(seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	var rows := ["..d.d..", ".dd.dd.", "ddldd.d", ".dddld.", "..ddd.."]
	for y in rows.size():
		for x in 7:
			match rows[y][x]:
				"d":
					img.set_pixel(x, y, c("grass_dark"))
				"l":
					img.set_pixel(x, y, c("grass.0"))
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
	var grass := ramp("grass")
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

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in h:
		for x in w:
			var v := (noise.get_noise_2d(x, y) + 1.0) / 2.0
			var col: Color = grass[level(clampf((v - 0.5) * 1.25 + 0.5, 0.0, 0.999), grass.size(), x, y, 0.9)]
			var d: float = dist[y * w + x] + fine.get_noise_2d(x, y) * 1.6
			if d < half - 1.0:
				var dv := (fine.get_noise_2d(x * 0.7 + 100.0, y * 0.7) + 1.0) / 2.0
				col = dirt[level(dv, dirt.size(), x, y, 1.0)]
			elif d < half:
				col = c("dirt_edge")
			elif d < half + 2.0 and dither(x, y) < 0.5:
				col = c("grass_dark")
			img.set_pixel(x, y, col)
	# Specks: tiny darker / lighter dots so big patches don't look flat.
	for i in w * h / 90:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if dist[p.y * w + p.x] > half + 2.0:
			img.set_pixelv(p, c("grass_dark") if rng.randf() < 0.6 else c("grass_light"))
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

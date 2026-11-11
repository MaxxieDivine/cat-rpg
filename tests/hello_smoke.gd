extends "res://tests/test_base.gd"
## Instantiates the real main scene at phone and desktop sizes and pokes it.

const ScreenMetrics := preload("res://scripts/view/screen_metrics.gd")
const JsonData := preload("res://scripts/core/json_data.gd")
const MAIN_SCENE := "res://scenes/hello.tscn"

## name, CSS size, devicePixelRatio, safe-area insets [top, right, bottom, left] in CSS px
const CONFIGS := [
	["phone", Vector2i(390, 844), 3.0, [47.0, 0.0, 34.0, 0.0]],
	["phone_landscape", Vector2i(844, 390), 3.0, [0.0, 47.0, 21.0, 47.0]],
	["phone_dpr1", Vector2i(390, 844), 1.0, [0.0, 0.0, 0.0, 0.0]],
	["desktop", Vector2i(1280, 720), 1.0, [0.0, 0.0, 0.0, 0.0]],
]


func after_each() -> void:
	ScreenMetrics.override_dpr = 0.0
	ScreenMetrics.override_insets_css = []


func test_phone() -> void:
	await _run_config(CONFIGS[0])


func test_phone_landscape() -> void:
	await _run_config(CONFIGS[1])


func test_phone_dpr1() -> void:
	await _run_config(CONFIGS[2])


func test_desktop() -> void:
	await _run_config(CONFIGS[3])


func test_bubble_times_out_and_tap_restarts_it() -> void:
	var hello: Control = await _open(CONFIGS[3])
	var secs: float = JsonData.load_dict("res://data/tuning.json")["hello"]["bubble_seconds"]
	await _tap(hello.tap_target.get_global_rect().get_center(), hello)
	await tree.create_timer(secs * 0.7).timeout
	await _tap(hello.tap_target.get_global_rect().get_center(), hello)
	await tree.create_timer(secs * 0.7).timeout
	check(hello.is_bubble_visible(), "second tap restarted the bubble timer")
	await tree.create_timer(secs * 0.5).timeout
	check(not hello.is_bubble_visible(), "bubble hides after %ss" % secs)
	check(not hello.bob_up, "bob has finished")
	_close(hello)


func _open(cfg: Array) -> Control:
	var css: Vector2i = cfg[1]
	var dpr: float = cfg[2]
	ScreenMetrics.override_dpr = dpr
	ScreenMetrics.override_insets_css = cfg[3]
	tree.root.size = Vector2i((Vector2(css) * dpr).round())
	await tree.process_frame
	var hello: Control = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(hello)
	await tree.process_frame
	await tree.process_frame
	return hello


func _close(hello: Control) -> void:
	tree.root.remove_child(hello)
	hello.free()


func _run_config(cfg: Array) -> void:
	var name: String = cfg[0]
	var css: Vector2i = cfg[1]
	var dpr: float = cfg[2]
	var hello: Control = await _open(cfg)
	var m = hello.metrics
	var tuning: Dictionary = JsonData.load_dict("res://data/tuning.json")["hello"]
	var strings := JsonData.load_dict("res://data/strings.json")

	# 1 UI unit ~ 1 CSS px.
	check_near(m.ui_size.x, css.x, 1.0, "%s: UI width in CSS px" % name)
	check_near(m.ui_size.y, css.y, 1.0, "%s: UI height in CSS px" % name)

	# Whole-number scale, whole device-pixel position.
	var ppu: Vector2 = m.px_per_unit
	var k: int = hello.cow_scale
	check(k >= 1, "%s: cow scale >= 1" % name)
	check_near(hello.cow.scale.x * ppu.x, k, 0.001, "%s: cow x scale is whole device px" % name)
	check_near(hello.cow.scale.y * ppu.y, k, 0.001, "%s: cow y scale is whole device px" % name)
	var pos_px: Vector2 = hello.cow.position * ppu
	check_near(pos_px.x, roundf(pos_px.x), 0.01, "%s: cow x on a whole device px" % name)
	check_near(pos_px.y, roundf(pos_px.y), 0.01, "%s: cow y on a whole device px" % name)
	# Largest whole scale near the target fraction of the short side.
	var safe_px: Rect2i = m.safe_rect_px()
	var short_px := mini(safe_px.size.x, safe_px.size.y)
	var expected_k := maxi(1, floori(short_px * float(tuning["cow_screen_fraction"]) / 48.0))
	check_eq(k, expected_k, "%s: cow scale" % name)

	# Centred in the safe area, entirely inside it.
	var cow_rect: Rect2 = hello.cow_rect()
	var tol := 1.0 / ppu.x
	check_near(cow_rect.get_center().x, m.safe_rect.get_center().x, tol + 0.01, "%s: cow centred x" % name)
	check_near(cow_rect.get_center().y, m.safe_rect.get_center().y, tol + 0.01, "%s: cow centred y" % name)
	check(m.safe_rect.encloses(cow_rect), "%s: cow inside safe area" % name)
	var label_rect: Rect2 = hello.build_label.get_global_rect()
	check(m.safe_rect.encloses(label_rect), "%s: build label inside safe area %s vs %s" % [name, label_rect, m.safe_rect])
	check(hello.build_label.text.begins_with("build "), "%s: build label text '%s'" % [name, hello.build_label.text])

	# Tap target at least 48 CSS px.
	var min_css := float(tuning["min_tap_target"])
	var target_css: Vector2 = hello.tap_target.size * ppu / dpr
	check(target_css.x >= min_css - 0.01 and target_css.y >= min_css - 0.01, "%s: tap target %s CSS px >= %s" % [name, target_css, min_css])

	if not is_headless():
		await _check_cow_pixels(hello, name)

	# Tap on empty space: nothing happens.
	var taps := [0]
	hello.cow_tapped.connect(func() -> void: taps[0] += 1)
	var empty := Vector2(m.safe_rect.position.x + 20, m.safe_rect.get_center().y)
	check(not hello.tap_target.get_global_rect().has_point(empty), "%s: test point is outside the cow" % name)
	await _tap(empty, hello)
	check(not hello.is_bubble_visible(), "%s: tap on empty space shows no bubble" % name)
	check(not hello.bob_up, "%s: tap on empty space does not bob" % name)
	check_eq(taps[0], 0, "%s: empty tap count" % name)

	# Tap the cow: the bubble shows the text from strings.json, the cow bobs.
	await _tap(hello.tap_target.get_global_rect().get_center(), hello)
	check(hello.is_bubble_visible(), "%s: bubble visible after tapping the cow" % name)
	check_eq(hello.bubble_text.text, str(strings["hello.moo"]), "%s: bubble text" % name)
	check(hello.bob_up, "%s: cow bobs on tap" % name)
	check_eq(taps[0], 1, "%s: one tap gives exactly one event" % name)
	check(m.safe_rect.encloses(hello.bubble.get_global_rect()), "%s: bubble inside safe area" % name)
	check(hello.bubble.get_global_rect().end.y <= cow_rect.position.y, "%s: bubble is above the cow" % name)

	if shots_dir != "" and not is_headless():
		await RenderingServer.frame_post_draw
		var img := tree.root.get_texture().get_image()
		var path := shots_dir.path_join("hello_%s.png" % name)
		img.save_png(path)
		print("     shot: ", path)
	_close(hello)


## Every opaque art pixel must cover exactly k x k device pixels of its colour.
func _check_cow_pixels(hello: Control, name: String) -> void:
	await RenderingServer.frame_post_draw
	var shot := tree.root.get_texture().get_image()
	var art: Image = hello.cow.texture.get_image()
	var k: int = hello.cow_scale
	var origin := Vector2i((hello.cow.position * hello.metrics.px_per_unit).round())
	var bad := 0
	for ay in art.get_height():
		for ax in art.get_width():
			var c := art.get_pixel(ax, ay)
			if c.a < 1.0:
				continue
			for dy in k:
				for dx in k:
					var p := origin + Vector2i(ax * k + dx, ay * k + dy)
					var s := shot.get_pixelv(p)
					if absf(s.r - c.r) > 0.02 or absf(s.g - c.g) > 0.02 or absf(s.b - c.b) > 0.02:
						bad += 1
	check_eq(bad, 0, "%s: device pixels not matching their art pixel (blur / uneven pixels)" % name)


func _tap(ui_pos: Vector2, hello: Control) -> void:
	var px: Vector2 = hello.metrics.ui_to_px(ui_pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		tree.root.push_input(ev)
	await tree.process_frame

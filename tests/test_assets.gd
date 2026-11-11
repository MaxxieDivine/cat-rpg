extends "res://tests/test_base.gd"

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")


func before_each() -> void:
	AssetCatalog.reset()


func test_known_key_loads() -> void:
	var tex := AssetCatalog.texture("cow.idle")
	check(tex != null, "cow.idle returns a texture")
	check(not AssetCatalog.is_placeholder(tex), "cow.idle is the real art, not the placeholder (did you run --import?)")
	check(AssetCatalog.warned_keys.is_empty(), "no warnings for a known key")


func test_listed_keys_resolve_to_data_paths() -> void:
	var map := JsonData.load_dict(AssetCatalog.ASSETS_PATH)
	check(not map.is_empty(), "assets.json has entries")
	for key in map:
		check_eq(AssetCatalog.path_for(key), str(map[key]), "path for %s" % key)
		if key.begins_with("font."):
			check(AssetCatalog.font(key) != null, "%s loads" % key)
		elif key.begins_with("shader."):
			check(AssetCatalog.shader(key) != null, "%s loads" % key)
		else:
			check(not AssetCatalog.is_placeholder(AssetCatalog.texture(key)), "%s loads" % key)


func test_unlisted_key_falls_back_to_art_folder() -> void:
	check_eq(AssetCatalog.path_for("cat.walk"), "res://art/cat.walk.png", "fallback path")


func test_missing_key_returns_placeholder_and_warns_once() -> void:
	var a := AssetCatalog.texture("no.such.asset")
	var b := AssetCatalog.texture("no.such.asset")
	check(a != null, "missing key still returns a texture")
	check(AssetCatalog.is_placeholder(a), "missing key returns the placeholder")
	check(a == b, "same placeholder both times")
	check_eq(AssetCatalog.warned_keys.count("no.such.asset"), 1, "warning count")
	var img := a.get_image()
	check_eq(img.get_pixel(0, 0), Color.MAGENTA, "placeholder is a magenta checker")


func test_cow_is_48x48() -> void:
	var tex := AssetCatalog.texture("cow.idle")
	check_eq(tex.get_size(), Vector2(48, 48), "cow size")
	var img := tex.get_image()
	check_eq(img.get_pixel(0, 0).a, 0.0, "cow background is transparent")
	check_eq(img.get_pixel(24, 24).a, 1.0, "cow centre is opaque")


func test_dialogue_font_has_a_license() -> void:
	var path := AssetCatalog.path_for("font.dialogue")
	var license := path.get_basename() + "-OFL.txt"
	check(FileAccess.file_exists(license), "font license next to the font (%s)" % license)
	check(FileAccess.get_file_as_string(license).contains("SIL Open Font License"), "license is the OFL")

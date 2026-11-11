extends RefCounted
## Looks up art by key. data/assets.json maps keys to paths; unlisted keys fall
## back to res://art/<key>.png. A missing asset warns once per key and returns a
## magenta checker placeholder. Never crashes. preload() this script.

const JsonData := preload("res://scripts/core/json_data.gd")
const ASSETS_PATH := "res://data/assets.json"
const PLACEHOLDER_SIZE := 16
const PLACEHOLDER_CHECK := 4

static var _map: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}
## Keys that have already produced a "missing asset" warning.
static var warned_keys: Array[String] = []
static var _placeholder: Texture2D


## Path an asset key resolves to (it may not exist).
static func path_for(key: String) -> String:
	_ensure_loaded()
	if _map.has(key):
		return str(_map[key])
	return "res://art/%s.png" % key


## The texture for a key, or the placeholder if it is missing.
static func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := path_for(key)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		if not warned_keys.has(key):
			warned_keys.append(key)
			push_warning("AssetCatalog: missing asset '%s' (%s), using placeholder" % [key, path])
		tex = placeholder()
	_cache[key] = tex
	return tex


## A font by key (data/assets.json). Missing fonts warn once and return
## null: callers then use the theme's default font.
static func font(key: String) -> Font:
	if _cache.has(key):
		return _cache[key]
	var path := path_for(key)
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null and not warned_keys.has(key):
		warned_keys.append(key)
		push_warning("AssetCatalog: missing font '%s' (%s)" % [key, path])
	_cache[key] = f
	return f


static func is_placeholder(tex: Texture2D) -> bool:
	return tex != null and tex == _placeholder


static func placeholder() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
		for y in PLACEHOLDER_SIZE:
			for x in PLACEHOLDER_SIZE:
				var on := ((x / PLACEHOLDER_CHECK) + (y / PLACEHOLDER_CHECK)) % 2 == 0
				img.set_pixel(x, y, Color.MAGENTA if on else Color.BLACK)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


## Forget cached lookups and warnings (tests use this).
static func reset() -> void:
	_map = {}
	_loaded = false
	_cache = {}
	warned_keys = []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_map = JsonData.load_dict(ASSETS_PATH)

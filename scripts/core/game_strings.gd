extends RefCounted
## Player-facing text from data/strings.json. preload() this script.
## text("build.label", {"sha": "abc"}) fills {sha}-style placeholders.
## A missing key warns and returns the key itself.

const JsonData := preload("res://scripts/core/json_data.gd")
const STRINGS_PATH := "res://data/strings.json"

static var _strings: Dictionary = {}
static var _loaded := false


static func text(key: String, args: Dictionary = {}) -> String:
	_ensure_loaded()
	if not _strings.has(key):
		push_warning("GameStrings: missing key '%s'" % key)
		return key
	var s := str(_strings[key])
	return s.format(args) if not args.is_empty() else s


static func has(key: String) -> bool:
	_ensure_loaded()
	return _strings.has(key)


static func _ensure_loaded() -> void:
	if not _loaded:
		_loaded = true
		_strings = JsonData.load_dict(STRINGS_PATH)

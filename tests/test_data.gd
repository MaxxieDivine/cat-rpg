extends "res://tests/test_base.gd"

const GameStrings := preload("res://scripts/core/game_strings.gd")
const JsonData := preload("res://scripts/core/json_data.gd")


func test_data_files_parse() -> void:
	for path in ["res://data/assets.json", "res://data/strings.json", "res://data/tuning.json", "res://data/world.json", "res://data/speakers.json", "res://data/state.json"]:
		check(not JsonData.load_dict(path).is_empty(), "%s parses to a non-empty object" % path)


func test_strings_come_from_json() -> void:
	var raw := JsonData.load_dict(GameStrings.STRINGS_PATH)
	check_eq(GameStrings.text("title.name"), str(raw["title.name"]), "title.name")


func test_string_formatting() -> void:
	check_eq(GameStrings.text("build.label", {"sha": "abc1234", "date": "2026-01-01"}),
		str(JsonData.load_dict(GameStrings.STRINGS_PATH)["build.label"]).format({"sha": "abc1234", "date": "2026-01-01"}),
		"build.label format")


func test_missing_string_returns_key() -> void:
	check_eq(GameStrings.text("no.such.string"), "no.such.string", "missing key")

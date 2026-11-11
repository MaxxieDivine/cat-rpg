extends SceneTree
## Validates every dialogue file in data/dialogue/ (see
## scripts/core/dialogue_validator.gd for what is checked). Exits 1 on any
## error so CI fails the build.
##   godot --headless --path . --script res://tools/validate_dialogue.gd

const Validator := preload("res://scripts/core/dialogue_validator.gd")


func _initialize() -> void:
	var files := Validator.dialogue_files()
	var bad := 0
	if files.is_empty():
		print("validate_dialogue: no files in %s" % Validator.DIALOGUE_DIR)
		quit(1)
		return
	for f in files:
		var errors := Validator.validate_file(f)
		if errors.is_empty():
			print("ok    ", f)
		else:
			bad += 1
			print("ERROR ", f)
			for e in errors:
				print("      ", e)
	print("validate_dialogue: %d file(s), %d with errors" % [files.size(), bad])
	quit(1 if bad > 0 else 0)

extends SceneTree
## Copies the cat sheets data/cats.json asks for out of the Pet Cats Pack
## (CC0) into art/cats/<cat>_<anim>.png, plus the meow puff (art/meow_vfx.png).
## Run: godot --headless --path . --script res://tools/import_cats.gd -- <pack dir>
## (<pack dir> holds Cat-1 ... Cat-6 and Meow-VFX). Then: godot --headless --path . --import
## Prints the assets.json lines for the keys. Cats with a "recolor" and no
## "pack" are skipped: run tools/recolor_cats.gd for them afterwards.

const JsonData := preload("res://scripts/core/json_data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("import_cats: pass the pack folder after --")
		quit(1)
		return
	var pack: String = args[0]
	var data := JsonData.load_dict("res://data/cats.json")
	var ok := true
	var keys: Array[String] = []
	for id: String in data["cats"]:
		var cat: Dictionary = data["cats"][id]
		if not cat.has("pack"):
			# A recoloured placeholder (tools/recolor_cats.gd).
			continue
		for anim: String in cat["anims"]:
			if cat["anims"][anim].has("recolor"):
				# This one anim is a recoloured placeholder (recolor_cats.gd).
				continue
			var file: String = cat["anims"][anim]["file"]
			var src := "%s/%s/%s-%s.png" % [pack, cat["pack"], cat["pack"], file]
			ok = _copy(src, "res://art/cats/%s_%s.png" % [id, anim]) and ok
			keys.append("\t\"cat.%s.%s\": \"res://art/cats/%s_%s.png\"," % [id, anim, id, anim])
	ok = _copy(pack + "/Meow-VFX/Meow-VFX.png", "res://art/meow_vfx.png") and ok
	print("\n".join(keys))
	quit(0 if ok else 1)


func _copy(src: String, dst: String) -> bool:
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		push_error("import_cats: can't read " + src)
		return false
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(ProjectSettings.globalize_path(dst))
	print("import_cats: %s -> %s err=%d" % [src.get_file(), dst, err])
	return err == OK

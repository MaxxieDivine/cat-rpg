extends "res://tests/test_base.gd"
## The animated cats (data/cats.json, art/cats/ from the Pet Cats Pack) and
## the animator (scripts/view/cat_anim.gd).

const JsonData := preload("res://scripts/core/json_data.gd")
const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const CatAnim := preload("res://scripts/view/cat_anim.gd")

## Animations each behaviour (world.json) needs.
const NEEDS := {"sit": [], "lie": ["lie_down"], "pace": ["idle", "walk"], "stand": []}


func _cats() -> Dictionary:
	return JsonData.load_dict("res://data/cats.json")


func test_every_sheet_loads_with_whole_frames_and_feet_on_the_row() -> void:
	AssetCatalog.reset()
	var d := _cats()
	var fpx := int(d["frame_px"])
	for id: String in d["cats"]:
		for anim: String in d["cats"][id]["anims"]:
			var key := "cat.%s.%s" % [id, anim]
			var tex := AssetCatalog.texture(key)
			if not check(not AssetCatalog.is_placeholder(tex), "%s loads (run tools/import_cats.gd)" % key):
				continue
			check_eq(tex.get_height(), fpx, "%s is one row of %d px frames" % [key, fpx])
			check_eq(tex.get_width() % fpx, 0, "%s: whole frames" % key)
			check_eq(tex.get_image().get_used_rect().end.y, int(d["feet_px"]), "%s: feet on row %d" % [key, d["feet_px"]])


func test_fern_and_every_npc_cat_have_what_they_need() -> void:
	var cats: Dictionary = _cats()["cats"]
	for a in ["idle", "walk", "run", "meow"]:
		check(cats["fern"]["anims"].has(a), "Fern has %s" % a)
	var w := JsonData.load_dict("res://data/world.json")
	for npc: Dictionary in w["npcs"]:
		if not check(cats.has(npc["id"]), "%s is in cats.json" % npc["id"]):
			continue
		for a: String in NEEDS[npc.get("behavior", "stand")]:
			check(cats[npc["id"]]["anims"].has(a), "%s (%s) has %s" % [npc["id"], npc["behavior"], a])
	for id: String in cats:
		for f: String in cats[id].get("fidgets", []):
			var a: Dictionary = cats[id]["anims"].get(f, {})
			check(int(a.get("loops", 0)) > 0, "%s fidget %s is a one-shot" % [id, f])


func test_one_shots_finish_and_loops_wrap() -> void:
	var c := CatAnim.new()
	c.setup("fern")
	check_eq(c.anim, "idle", "starts in the resting pose")
	var idle: Dictionary = c.anims["idle"]
	c.step((idle["frames"] + 1) / idle["fps"])
	check_eq(c.current_frame(), 1, "idle loops back to the start")
	check(not c.finished(), "a loop never finishes")
	c.play("meow", true)
	var meow: Dictionary = c.anims["meow"]
	c.step((meow["frames"] - 0.5) / meow["fps"])
	check(not c.finished(), "meow still playing")
	c.step(1.0 / meow["fps"])
	check(c.finished(), "meow finished")
	check_eq(c.current_frame(), meow["frames"] - 1, "a finished one-shot holds its last frame")
	c.show_stride("walk", c.anims["walk"]["stride_px"] * 3.0)
	check_eq([c.anim, c.current_frame()], ["walk", 3], "walk frame follows distance")
	c.hold("run", -1)
	check_eq(c.current_frame(), c.anims["run"]["frames"] - 1, "hold(-1) shows the last frame")
	check_eq(c.region_rect.size, Vector2(c.frame_px, c.frame_px), "shows one frame")
	c.free()


## Recoloured placeholder cats (cats.json "recolor") match what
## tools/recolor_cats.gd bakes from their source sheets.
func test_recoloured_cats_are_fresh() -> void:
	var Recolor = load("res://tools/recolor_cats.gd")
	var cats: Dictionary = _cats()["cats"]
	for id: String in cats:
		if not cats[id].has("recolor"):
			continue
		for a: String in cats[id]["anims"]:
			var want: Image = Recolor.bake(cats[id]["recolor"], a)
			var have := Image.load_from_file(ProjectSettings.globalize_path("res://art/cats/%s_%s.png" % [id, a]))
			if not check(want != null and have != null and not have.is_empty(), "%s %s: both sheets exist" % [id, a]):
				continue
			have.convert(Image.FORMAT_RGBA8)
			check_eq(have.get_data(), want.get_data(), "%s %s is fresh (run tools/recolor_cats.gd)" % [id, a])

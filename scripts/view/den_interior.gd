extends Node2D
## The den template (scenes/den_interior.tscn): draws one den's room from
## its World (world.interior, built by scripts/core/den_layout.gd): the
## floor (den.floor tiled, tinted floor_color), the walls of wall_material
## (den.wall_<material>_top / _side / _bottom, tiled) and the nests
## (Fern's with a feather). Children:
##   (itself)  the floor and walls (drawn in _draw)
##   Nests     a Sprite2D per nest (Nest_<i>; Fern's is Nest_player)
##   DecorSlots  empty Marker2D nodes (DecorSlot_<i>) along the walls and
##             by the nests: where decorations will go
##   Decor     an empty, y-sorted layer for decorations (none yet), so they
##             can be added without touching the walls and nests
## world_view.gd adds it to its Ground layer. The exports are the den's
## settings (filled from its area file); changing one while the game runs
## (remote Inspector) rebuilds the room through World.apply_interior().

const AssetCatalog := preload("res://scripts/core/asset_catalog.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

@export_enum("small", "medium", "large") var size_name := "medium":
	set(v):
		size_name = v
		_changed()
@export var floor_color := Color.WHITE:
	set(v):
		floor_color = v
		queue_redraw()
@export_enum("fern_moss", "bramble", "bark", "stone") var wall_material := "fern_moss":
	set(v):
		wall_material = v
		_changed()
@export_range(0, 12) var nest_count := 3:
	set(v):
		nest_count = v
		_changed()
@export var player_nest := 0:
	set(v):
		player_nest = v
		_changed()

var world
var nests: Node2D
var decor_slots: Node2D
var decor: Node2D
var _ready_done := false


func setup(w) -> void:
	world = w
	name = "DenInterior"
	var s: Dictionary = world.interior["settings"]
	size_name = str(world.interior["size_name"])
	floor_color = Color(str(s.get("floor_color", "#ffffff")))
	wall_material = str(s.get("walls", "fern_moss"))
	nest_count = int(s.get("nests", 3))
	player_nest = int(s.get("player_nest", 0))
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	nests = Node2D.new()
	nests.name = "Nests"
	add_child(nests)
	decor_slots = Node2D.new()
	decor_slots.name = "DecorSlots"
	add_child(decor_slots)
	decor = Node2D.new()
	decor.name = "Decor"
	decor.y_sort_enabled = true
	add_child(decor)
	_ready_done = true
	rebuild()


## The settings as den_layout.gd takes them.
func settings() -> Dictionary:
	var out: Dictionary = world.interior["settings"].duplicate() if world != null else {}
	out.merge({"size": size_name, "floor_color": "#" + floor_color.to_html(false), "walls": wall_material,
		"nests": nest_count, "player_nest": player_nest}, true)
	return out


func _changed() -> void:
	if not _ready_done or world == null:
		return
	world.apply_interior(settings())
	rebuild()


## Re-creates the nests and decor slots from world.interior and redraws.
func rebuild() -> void:
	for c in nests.get_children():
		nests.remove_child(c)
		c.queue_free()
	for c in decor_slots.get_children():
		decor_slots.remove_child(c)
		c.queue_free()
	var lay: Dictionary = world.interior
	for i in lay["nests"].size():
		var n: Dictionary = lay["nests"][i]
		var s := Sprite2D.new()
		s.name = "Nest_player" if n["mine"] else "Nest_%d" % i
		s.texture = AssetCatalog.texture("den.nest_mine" if n.get("feather", n["mine"]) else "den.nest")
		s.centered = false
		var r: Rect2 = n["rect"]
		s.position = (r.get_center() - s.texture.get_size() / 2.0).round()
		s.set_meta("mine", n["mine"])
		nests.add_child(s)
	var slots: Array = lay["decor_slots"]
	for i in slots.size():
		var m := Marker2D.new()
		m.name = "DecorSlot_%d" % i
		m.position = slots[i]
		decor_slots.add_child(m)
	queue_redraw()


func _draw() -> void:
	if world == null or world.interior.is_empty():
		return
	var lay: Dictionary = world.interior
	var size: Vector2 = lay["size"]
	var fr: Rect2 = lay["floor_rect"]
	var wl: Dictionary = lay["wall"]
	# Floor (under the walls' edges), tinted.
	draw_texture_rect(AssetCatalog.texture("den.floor"), Rect2(Vector2.ZERO, size), true, floor_color)
	var top := AssetCatalog.texture("den.wall_%s_top" % wall_material)
	var side := AssetCatalog.texture("den.wall_%s_side" % wall_material)
	var bottom := AssetCatalog.texture("den.wall_%s_bottom" % wall_material)
	var door: Rect2 = lay["door_rect"]
	var door_l := door.position.x - 3.0
	var door_r := door.end.x + 3.0
	# Bottom wall, either side of the doorway.
	draw_texture_rect(bottom, Rect2(0, size.y - wl["bottom"], door_l, wl["bottom"]), true)
	draw_set_transform(Vector2(door_r, size.y - wl["bottom"]))
	draw_texture_rect(bottom, Rect2(0, 0, size.x - door_r, wl["bottom"]), true)
	draw_set_transform(Vector2.ZERO)
	# Sides (the right one mirrored), then the back wall over their tops.
	draw_texture_rect(side, Rect2(0, 0, wl["side"], size.y), true)
	draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
	draw_texture_rect(side, Rect2(0, 0, wl["side"], size.y), true)
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(top, Rect2(0, 0, size.x, wl["top"]), true)
	# Rounded floor corners: a little extra wall.
	var cc := Color(str(JsonData.load_dict("res://data/palette.json").get("leaf", ["#264c33"])[0]))
	var k: float = wl["corner"]
	for corner in [fr.position, Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fr.end]:
		var sx := 1.0 if corner.x == fr.position.x else -1.0
		var sy := 1.0 if corner.y == fr.position.y else -1.0
		draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(sx * k, 0), corner + Vector2(0, sy * k)]), cc)

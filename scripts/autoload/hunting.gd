extends Node
## Autoload "Hunting": the hunting numbers, exported for the Inspector. A
## thin Node around one shared scripts/core/hunt_tuning.gd (defaults from
## tuning.json "hunt"); game.gd hands `tuning` to every area's World, so
## changing a value in the remote Inspector (Scene dock > Remote > root >
## Hunting) while the game runs applies at once. Tests use hunt_tuning.gd.

const HuntTuning := preload("res://scripts/core/hunt_tuning.gd")

var tuning := HuntTuning.new()

## Fern's speed while crouched (px/s).
@export_range(5.0, 120.0, 1.0) var crouch_speed := 30.0:
	set(v):
		crouch_speed = v
		tuning.crouch_speed = v
## Head down (feeding) time range, seconds (x = min, y = max).
@export var head_down_s := Vector2(2, 4):
	set(v):
		head_down_s = v
		tuning.feed_s = v
## Head up (looking around) time range, seconds.
@export var head_up_s := Vector2(1, 2):
	set(v):
		head_up_s = v
		tuning.look_s = v
## Alert per second when Fern moves while the head is up.
@export_range(0.0, 10.0, 0.05) var look_rise := 1.4:
	set(v):
		look_rise = v
		tuning.look_rise = v
## Alert per second when Fern walks (not crouched) within walk_noise_px.
@export_range(0.0, 10.0, 0.05) var walk_rise := 0.8:
	set(v):
		walk_rise = v
		tuning.walk_rise = v
## Alert per second when Fern moves (not crouched) within close_px.
@export_range(0.0, 10.0, 0.05) var close_rise := 2.5:
	set(v):
		close_rise = v
		tuning.close_rise = v
## Alert lost per second while Fern holds still.
@export_range(0.0, 5.0, 0.01) var alert_fall := 0.2:
	set(v):
		alert_fall = v
		tuning.alert_fall = v
## Walking (not crouched) within this distance makes noise (px).
@export_range(0.0, 300.0, 1.0) var walk_noise_px := 64.0:
	set(v):
		walk_noise_px = v
		tuning.noise_px = v
@export_range(0.0, 100.0, 1.0) var close_px := 24.0:
	set(v):
		close_px = v
		tuning.close_px = v
## Pounce range from Fern's feet to the mouse (px).
@export_range(5.0, 150.0, 1.0) var pounce_range := 40.0:
	set(v):
		pounce_range = v
		tuning.pounce_range = v
## How long the leap takes (s).
@export_range(0.1, 2.0, 0.01) var leap_s := 0.45:
	set(v):
		leap_s = v
		tuning.leap_s = v
## A prey spot stays empty this long after its mouse is caught or runs (s).
@export_range(0.0, 600.0, 1.0) var respawn_s := 30.0:
	set(v):
		respawn_s = v
		tuning.respawn_s = v
## Most mice in an area at once.
@export_range(0, 8) var max_mice := 2:
	set(v):
		max_mice = v
		tuning.max_mice = v


func _init() -> void:
	crouch_speed = tuning.crouch_speed
	head_down_s = tuning.feed_s
	head_up_s = tuning.look_s
	look_rise = tuning.look_rise
	walk_rise = tuning.walk_rise
	close_rise = tuning.close_rise
	alert_fall = tuning.alert_fall
	walk_noise_px = tuning.noise_px
	close_px = tuning.close_px
	pounce_range = tuning.pounce_range
	leap_s = tuning.leap_s
	respawn_s = tuning.respawn_s
	max_mice = tuning.max_mice


## Back to tuning.json (tests).
## Copies into the shared object, so worlds holding it see the reset.
func reset() -> void:
	var fresh := HuntTuning.new()
	for prop in fresh.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			tuning.set(prop["name"], fresh.get(prop["name"]))
	_init()

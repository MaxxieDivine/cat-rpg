extends RefCounted
## Every hunting number in one place (tuning.json "hunt"): crouching, the
## mice's head-down / head-up timers, alert, pouncing, respawning. One shared
## instance lives in the `Hunting` autoload (exported for the Inspector);
## World and Hunt read it every frame, so live edits apply at once. Tests
## make their own from tuning.json. preload(), no class_name.

const JsonData := preload("res://scripts/core/json_data.gd")

## Fern's stalking speed while crouched (px/s).
var crouch_speed := 30.0
## Head down (feeding) and head up (looking around), seconds: [min, max].
var feed_s := Vector2(2.0, 4.0)
var look_s := Vector2(1.0, 2.0)
## Alert (0..1) per second: moving while the head is up; walking (not
## crouched) within noise_px; moving (not crouched) within close_px.
var look_rise := 1.4
var walk_rise := 0.8
var close_rise := 2.5
## Alert lost per second while Fern holds still.
var alert_fall := 0.2
var noise_px := 64.0
var close_px := 24.0
## Mice only notice Fern within this distance; the alert bar shows within show_px.
var notice_px := 120.0
var show_px := 90.0
## Pounce: range from Fern's feet to the mouse, leap time and fake height.
var pounce_range := 40.0
var leap_s := 0.45
var leap_height := 10.0
## Pauses after landing: a catch (a happy bounce) or a miss (a stumble).
var catch_s := 0.4
var stumble_s := 0.6
## A spot stays empty this long after its mouse is caught or runs off.
var respawn_s := 30.0
var max_mice := 2
## New mice appear at least this far from Fern (off-screen on a phone).
var spawn_min_px := 160.0
## Feeding mice nose about within wander_px of their spot.
var wander_px := 6.0
var wander_speed := 8.0
var wander_every := Vector2(1.5, 3.5)
var flee_speed := 70.0
## A quiet squeak now and then: [min, max] seconds apart.
var squeak_every := Vector2(5.0, 10.0)
## Below this speed Fern counts as holding still (px/s).
var still_speed := 4.0


func _init(t: Dictionary = {}) -> void:
	if t.is_empty():
		t = JsonData.load_dict("res://data/tuning.json").get("hunt", {})
	for k in t:
		if str(k).begins_with("_") or not (k in self):
			continue
		var v: Variant = t[k]
		if v is Array:
			set(k, Vector2(float(v[0]), float(v[1])))
		elif get(k) is int:
			set(k, int(v))
		else:
			set(k, float(v))

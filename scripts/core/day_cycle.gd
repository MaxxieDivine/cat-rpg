extends RefCounted
## Time of day: afternoon until every conversation in tuning.json
## "time_of_day.after_flags" is done (and the box has closed), then dusk and
## night over "duration" seconds. Plain data, no Nodes. The view reads t
## (0 = afternoon, `dusk_at` = dusk, 1 = night) and blends the colour grade,
## fireflies, pond, music and ambience from it.
## preload() this script; no class_name.

## 0..1 through the change; stays 0 until it starts, 1 once it is night.
var t := 0.0
var started := false
var duration := 8.0
var dusk_at := 0.5
var after_flags: Array[String] = []


func _init(tuning: Dictionary = {}) -> void:
	duration = maxf(0.01, float(tuning.get("duration", duration)))
	dusk_at = clampf(float(tuning.get("dusk_at", dusk_at)), 0.01, 0.99)
	for f in tuning.get("after_flags", []):
		after_flags.append(str(f))


## Whether every trigger flag is set in `flags` (a flag -> value Dictionary).
func ready_for_night(flags: Dictionary) -> bool:
	if after_flags.is_empty():
		return false
	for f in after_flags:
		if flags.get(f, false) != true:
			return false
	return true


## Advances by dt. Starts the change when every trigger flag is set and
## nobody is talking. Returns events: {"type": "nightfall"} when it starts,
## {"type": "night"} when it is fully night.
func step(dt: float, flags: Dictionary, talking: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not started:
		if not talking and ready_for_night(flags):
			started = true
			events.append({"type": "nightfall"})
		else:
			return events
	if t < 1.0:
		t = minf(1.0, t + dt / duration)
		if t >= 1.0:
			events.append({"type": "night"})
	return events


## Jumps straight to a time (tests, screenshots). t > 0 counts as started.
func set_t(value: float) -> void:
	t = clampf(value, 0.0, 1.0)
	started = t > 0.0


## "afternoon", "dusk" or "night": the stage nearest to t.
func phase() -> String:
	if t < dusk_at * 0.5:
		return "afternoon"
	if t < (dusk_at + 1.0) * 0.5:
		return "dusk"
	return "night"


## How far into the night it is, 0..1 (0 until dusk, eased). Fireflies,
## crickets and the night music follow this.
func night_amount() -> float:
	return smoothstep(dusk_at * 0.6, 1.0, t)


## How much of the day is left, 0..1 (birds, butterflies, pollen).
func day_amount() -> float:
	return 1.0 - smoothstep(0.0, dusk_at + (1.0 - dusk_at) * 0.4, t)


## Blends three values (afternoon, dusk, night) for the current t, eased.
## Works for Colors and floats.
func blend(afternoon: Variant, dusk: Variant, night: Variant) -> Variant:
	if t <= dusk_at:
		return lerp(afternoon, dusk, smoothstep(0.0, 1.0, t / dusk_at))
	return lerp(dusk, night, smoothstep(0.0, 1.0, (t - dusk_at) / (1.0 - dusk_at)))

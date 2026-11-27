extends RefCounted
## Fern's footfalls (polish P2), locked to her walk / run sprite cycle.
##
## The cat sheets are distance-driven (cat_anim.gd show_stride(): frame =
## distance / stride_px), so one stride = frames x stride_px world px and
## the stride phase (0..1) is the same clock the drawn legs follow. Each
## gait lists its beats as [phase, paw] (tuning.json audio.gait):
## - walk: four even beats, back-left, front-left, back-right, front-right;
## - run (trot): paired beats, the back pair close together, the front pair
##   close together, then a gap (da-da . da-da . gap).
## step() returns the paws that landed since the last call. Headless; no
## Nodes; no randomness (sound.gd adds the variation).

const WALK_BEATS := [[0.0, "back_left"], [0.25, "front_left"], [0.5, "back_right"], [0.75, "front_right"]]
const RUN_BEATS := [[0.0, "back_left"], [0.1, "back_right"], [0.45, "front_left"], [0.55, "front_right"]]

## px per full stride (all four paws once).
var walk_stride := 36.0
var run_stride := 56.0
var walk_beats: Array = WALK_BEATS
var run_beats: Array = RUN_BEATS
## Shifts every beat (fraction of a stride) to line up with the frames.
var walk_offset := 0.0
var run_offset := 0.0

var _last := 0.0
var _last_running := false


## `gait` = tuning.json audio.gait; the strides come from the sprite sheets.
func configure(gait: Dictionary, walk_stride_px: float, run_stride_px: float) -> void:
	walk_stride = maxf(1.0, walk_stride_px)
	run_stride = maxf(1.0, run_stride_px)
	var w: Dictionary = gait.get("walk", {})
	var r: Dictionary = gait.get("run", {})
	walk_beats = w.get("beats", WALK_BEATS)
	run_beats = r.get("beats", RUN_BEATS)
	walk_offset = float(w.get("offset", 0.0))
	run_offset = float(r.get("offset", 0.0))


## Starts counting from `distance` (a new area, a fresh start): no beat.
func reset(distance: float) -> void:
	_last = distance
	_last_running = false


static func is_back(paw: String) -> bool:
	return paw.begins_with("back")


func stride(running: bool) -> float:
	return run_stride if running else walk_stride


## Stride phase 0..1 at `distance`.
func phase(distance: float, running: bool) -> float:
	var off := run_offset if running else walk_offset
	return fposmod(distance / stride(running) - off, 1.0)


## The paws that landed between the last call and `distance` (oldest
## first). Switching gait restarts the count, so it never bursts; a jump of
## more than one stride gives each beat once at most.
func step(distance: float, running: bool) -> Array[String]:
	var out: Array[String] = []
	if running != _last_running:
		_last_running = running
		_last = distance
		return out
	var moved := distance - _last
	if moved <= 0.0:
		_last = distance
		return out
	var len_px := stride(running)
	var off := run_offset if running else walk_offset
	# Positions in strides; the same formula for both ends, so a beat on the
	# boundary counts in exactly one call.
	var to_s := distance / len_px - off
	var from_s := maxf(_last / len_px - off, to_s - 0.999999)
	_last = distance
	var beats: Array = run_beats if running else walk_beats
	var hits: Array = []
	for b: Array in beats:
		var p := float(b[0])
		# The beat lands at k + p for whole k: crossed if one lies in (from, to].
		if floorf(to_s - p) > floorf(from_s - p):
			hits.append([fposmod(p - from_s, 1.0), str(b[1])])
	hits.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	for h: Array in hits:
		out.append(h[1])
	return out

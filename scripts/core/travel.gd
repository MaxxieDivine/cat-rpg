extends RefCounted
## Fades between areas, and passing out. Plain data, no Nodes: game.gd
## calls step() every frame and acts on the events; black() is how dark the
## fade overlay is (0..1). preload(), no class_name. Tuning: tuning.json
## "travel" and "collapse".
##
## Walking into an exit (go()):
##   "out"  fade to black over fade_s          -> event "load" (area, spawn)
##   "in"   fade back in over fade_s           -> event "done"
## Passing out (collapse()):
##   "lie"  Fern sinks down for lie_s (control already locked)
##   "out"  fade to black over collapse.fade_s -> event "load" (the
##          recovery area and spawn, collapsed = true: restore the needs,
##          drop what she carries)
##   "message" the message on black until confirm() (after min_message_s) or
##          message_s                         -> event "wake" (she stretches)
##   "in"   fade in over collapse.fade_s
##   "wake" wake_s more before control comes back -> event "done"
## A story scene (scene(): sleeping in her nest, carried off by a rogue,
## sneaking home): like passing out, but its own `message` (none = no
## message phase), no needs restored, and "lie" / "wake" only if asked.
## Only one sequence runs at a time: go() and collapse() return false (and
## change nothing) while busy(), so a collapse can't fire twice.

var fade_s := 0.3
var collapse_fade_s := 0.8
var lie_s := 1.2
var message_s := 2.0
var min_message_s := 0.4
var wake_s := 1.2

## "", "lie", "out", "message", "in", "wake".
var phase := ""
## "exit", "collapse" or "scene" while busy().
var kind := ""
## A scene's line on black ("" = none; passing out uses Player's).
var message := ""
var _lie := true
var _wake := true
## Where the "load" event sends Fern.
var area := ""
var spawn := ""
var _t := 0.0


func _init(t: Dictionary = {}) -> void:
	var tr: Dictionary = t.get("travel", {})
	var co: Dictionary = t.get("collapse", {})
	fade_s = float(tr.get("fade_s", fade_s))
	collapse_fade_s = float(co.get("fade_s", collapse_fade_s))
	lie_s = float(co.get("lie_s", lie_s))
	message_s = float(co.get("message_s", message_s))
	min_message_s = float(co.get("min_message_s", min_message_s))
	wake_s = float(co.get("wake_s", wake_s))


func busy() -> bool:
	return phase != ""


## Starts the fade to area `to_area`, spawn `to_spawn`.
func go(to_area: String, to_spawn: String) -> bool:
	if busy():
		return false
	kind = "exit"
	area = to_area
	spawn = to_spawn
	_enter("out")
	return true


## Starts passing out; she wakes at `to_area` / `to_spawn`.
func collapse(to_area: String, to_spawn: String) -> bool:
	if busy():
		return false
	kind = "collapse"
	area = to_area
	spawn = to_spawn
	message = ""
	_lie = true
	_wake = true
	_enter("lie")
	return true


## Starts a story scene to `to_area` / `to_spawn`: Fern lies down first if
## `lie`, `text` shows on black (if any), she stretches awake if `wake`.
func scene(to_area: String, to_spawn: String, text: String = "", lie: bool = true, wake: bool = true) -> bool:
	if busy():
		return false
	kind = "scene"
	area = to_area
	spawn = to_spawn
	message = text
	_lie = lie
	_wake = wake
	_enter("lie" if lie else "out")
	return true


## Already black (the area is loaded): `text` shows (if any), then the
## fade in and Fern stretches awake. Scene select's "just woken up".
func wake_from_black(text: String) -> bool:
	if busy():
		return false
	kind = "scene"
	message = text
	_lie = false
	_wake = true
	_enter("message" if text != "" else "in")
	return true


## Whether Fern stretches awake at the end (passing out, or a scene that asked).
func wakes() -> bool:
	return kind == "collapse" or (kind == "scene" and _wake)


## Whether the screen shows a line on black now (passing out or a scene).
func has_message() -> bool:
	return phase == "message"

## A tap / key while the message shows: carry on (once it has shown for
## min_message_s, so a tap already on its way doesn't skip it unread).
func confirm() -> bool:
	if phase != "message" or _t < min_message_s:
		return false
	_t = message_s
	return true


## How dark the screen is: 0 = clear, 1 = black.
func black() -> float:
	var f := _fade()
	match phase:
		"out":
			return clampf(_t / f, 0.0, 1.0) if f > 0.0 else 1.0
		"message":
			return 1.0
		"in":
			return 1.0 - clampf(_t / f, 0.0, 1.0) if f > 0.0 else 0.0
	return 0.0


## Seconds since the current phase started.
func phase_time() -> float:
	return _t


func step(dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not busy():
		return events
	_t += maxf(0.0, dt)
	# A long frame can finish several phases; never more than a few.
	for i in 6:
		var ev := _advance()
		if ev.is_empty():
			break
		events.append_array(ev)
	return events


func _fade() -> float:
	return fade_s if kind == "exit" else collapse_fade_s


func _enter(p: String) -> void:
	phase = p
	_t = 0.0


## Moves on when the current phase is over; returns its events.
func _advance() -> Array[Dictionary]:
	match phase:
		"lie":
			if _t >= lie_s:
				_carry("out", lie_s)
				return [{"type": "lie_done"}]
		"out":
			if _t >= _fade():
				var says := kind == "collapse" or (kind == "scene" and message != "")
				_carry("message" if says else "in", _fade())
				var ev: Array[Dictionary] = [{"type": "load", "area": area, "spawn": spawn, "collapsed": kind == "collapse", "kind": kind}]
				if not says and kind == "scene" and _wake:
					ev.append({"type": "wake"})
				return ev
		"message":
			if _t >= message_s:
				_carry("in", message_s)
				var ev: Array[Dictionary] = [{"type": "wake" if wakes() else "message_done"}]
				return ev
		"in":
			if _t >= _fade():
				if kind == "collapse" or (kind == "scene" and _wake):
					_carry("wake", _fade())
					return [{"type": "faded_in"}]
				return _finish()
		"wake":
			if _t >= wake_s:
				return _finish()
	return []


## Next phase, keeping the time left over from the one that ended.
func _carry(p: String, used: float) -> void:
	var rest := maxf(0.0, _t - used)
	phase = p
	_t = rest


func _finish() -> Array[Dictionary]:
	var was := kind
	phase = ""
	kind = ""
	message = ""
	_t = 0.0
	return [{"type": "done", "kind": was}]

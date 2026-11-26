extends RefCounted
## A cutscene: a list of steps (data/cutscenes/<id>.json) played one after
## another while the player watches. Plain data, no Nodes; game.gd runs one
## and shows what it says. preload(), no class_name.
##
## File: {"id", "steps": [...]}. Each step is one of:
##   {"camera": [x, y] | "player", "s": seconds}  the camera glides there
##       (smoothstep) and the scene waits until it arrives; "player" glides
##       back to following Fern, and the scene's camera hold ends there.
##   {"move": npc id, "to": [x, y], "speed": px/s, "wait": true}  the cat
##       walks there (World.send_npc()); waits until it arrives unless
##       "wait" is false.
##   {"face": npc id or "fern", "dir": 1 | -1}  turns a cat.
##   {"say": speaker id, "text": "...", "expression": "neutral"}  a line in
##       the dialogue box; waits for advance() (a tap or Interact).
##   {"wait": seconds}  a pause.
##   {"set": {flag: value}}  writes GameState flags.
## No skipping in v1: lines advance one by one; everything else runs by
## itself.
##
## Events from start() / step() / advance(): {"type": "line", "speaker",
## "expression", "text", "choices": []} (show it), {"type": "line_done"}
## (close the box: the next step isn't a line), {"type": "end"}.

const JsonData := preload("res://scripts/core/json_data.gd")
const STEP_KINDS := ["camera", "move", "face", "say", "wait", "set"]

var id := ""
var steps: Array = []
## Index of the step running now (-1 before start, steps.size() when done).
var index := -1
var world
## Something with apply_set() (GameState's core), for "set" steps.
var state
## The line waiting for advance(), or {}.
var line: Dictionary = {}
var _wait := 0.0
var _moving := ""
## The camera: where it glides from / to (INF = following Fern) and how
## far along (0..1). camera_point() is INF while Fern is followed.
var _cam_from := Vector2.INF
var _cam_to := Vector2.INF
var _cam_t := 1.0
var _cam_s := 0.0
var _cam_now := Vector2.INF
var _follow := Vector2.ZERO


static func load_file(path: String) -> Dictionary:
	return JsonData.load_dict(path)


func _init(data: Dictionary = {}) -> void:
	id = str(data.get("id", ""))
	steps = data.get("steps", [])


func is_running() -> bool:
	return index >= 0 and index < steps.size()


func is_done() -> bool:
	return index >= steps.size()


## Starts the scene in `w` (a World), writing flags to `st`. `follow` is
## the camera's centre right now (where it glides from).
func start(w, st, follow: Vector2) -> Array[Dictionary]:
	world = w
	state = st
	_follow = follow
	_cam_now = Vector2.INF
	index = -1
	return _next()


## Where the camera should centre (world px), or INF to follow Fern as
## usual. `follow` = where following would put it this frame.
func camera_point() -> Vector2:
	return _cam_now


## Advances time. `follow` = where the camera would centre following Fern.
func step(dt: float, follow: Vector2) -> Array[Dictionary]:
	_follow = follow
	var ev: Array[Dictionary] = []
	if not is_running():
		return ev
	_step_camera(dt)
	var s: Dictionary = steps[index]
	if s.has("camera"):
		if _cam_t >= 1.0:
			if _cam_to == Vector2.INF:
				_cam_now = Vector2.INF
			ev.append_array(_next())
	elif s.has("move"):
		var npc: Dictionary = world.npc_by_id(_moving)
		if npc.is_empty() or str(npc.get("mode", "")) != "goto":
			ev.append_array(_next())
	elif s.has("wait"):
		_wait -= dt
		if _wait <= 0.0:
			ev.append_array(_next())
	return ev


## The player read the line: on to the next step.
func advance() -> Array[Dictionary]:
	if line.is_empty():
		return []
	line = {}
	return _next()


func _step_camera(dt: float) -> void:
	if _cam_t >= 1.0:
		if _cam_to != Vector2.INF:
			_cam_now = _cam_to
		return
	_cam_t = minf(1.0, _cam_t + dt / maxf(0.01, _cam_s))
	var k := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
	var to := _follow if _cam_to == Vector2.INF else _cam_to
	_cam_now = _cam_from.lerp(to, k)


## Runs instant steps until one that waits; returns their events.
func _next() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var was_line := false
	while true:
		index += 1
		if index >= steps.size():
			_cam_now = Vector2.INF
			ev.append({"type": "end"})
			return ev
		var s: Dictionary = steps[index]
		if s.has("say"):
			line = {"type": "line", "speaker": str(s["say"]), "expression": str(s.get("expression", "neutral")),
				"text": str(s.get("text", "")), "choices": [] as Array[String], "node": "%s_%d" % [id, index], "conversation": id}
			ev.append(line)
			return ev
		if not was_line:
			was_line = true
			ev.append({"type": "line_done"})
		if s.has("set"):
			state.apply_set(s["set"])
		elif s.has("face"):
			var d := 1 if int(s.get("dir", 1)) >= 0 else -1
			if str(s["face"]) == "fern":
				world.facing = d
			else:
				var npc: Dictionary = world.npc_by_id(str(s["face"]))
				if not npc.is_empty():
					npc["facing"] = d
		elif s.has("camera"):
			_cam_from = _cam_now if _cam_now != Vector2.INF else _follow
			var c: Variant = s["camera"]
			_cam_to = Vector2(float(c[0]), float(c[1])) if c is Array else Vector2.INF
			_cam_s = float(s.get("s", 1.0))
			_cam_t = 0.0
			_cam_now = _cam_from
			return ev
		elif s.has("move"):
			_moving = str(s["move"])
			var to := Vector2(float(s["to"][0]), float(s["to"][1]))
			if not world.send_npc(_moving, to, false, float(s.get("speed", 30))):
				continue
			if not bool(s.get("wait", true)):
				continue
			return ev
		elif s.has("wait"):
			_wait = float(s["wait"])
			return ev
	return ev


## Problems with a cutscene file (for tests): unknown step kinds, speakers
## not in `speakers`, unknown flags (`st`, GameState's core).
static func check(data: Dictionary, speakers: Dictionary, st) -> Array[String]:
	var errs: Array[String] = []
	var list: Variant = data.get("steps")
	if not list is Array or (list as Array).is_empty():
		errs.append("no steps")
		return errs
	for i in list.size():
		var s: Dictionary = list[i]
		var kinds: Array = STEP_KINDS.filter(func(k): return s.has(k))
		if kinds.size() != 1:
			errs.append("step %d: needs exactly one of %s (has %s)" % [i, STEP_KINDS, kinds])
			continue
		if s.has("say") and not speakers.has(str(s["say"])):
			errs.append("step %d: unknown speaker '%s'" % [i, s["say"]])
		if s.has("say") and str(s.get("text", "")).strip_edges() == "":
			errs.append("step %d: no text" % i)
		if s.has("set"):
			for f: String in s["set"]:
				if not st.is_valid_value(f, s["set"][f]):
					errs.append("step %d: bad flag %s = %s" % [i, f, s["set"][f]])
		if s.has("move") and not (s.get("to") is Array and (s["to"] as Array).size() == 2):
			errs.append("step %d: move needs \"to\": [x, y]" % i)
	return errs

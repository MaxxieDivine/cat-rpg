extends Node
## Player-facing view settings (autoload "Settings"). No settings screen yet:
## these are hooks. On the web they can be set from the page URL for
## testing on a phone, e.g. `...?zoom=2&text=1&debug=1`.
##
## - camera_zoom: 0 = auto (about `view.target_rows` world pixels top to
##   bottom), 1 / 2 / 3 = that many times the old fit (the whole 480x270
##   base view at the largest whole scale; 1 = the Milestone 3 view).
## - text_scale: 2 = the readable dialogue box (default), 1 = compact (the
##   box at the world's old pixel scale).
## - debug_overlay: the build / fps label. Off by default in release builds
##   (the Pages build), on in debug builds; F3 or a triple tap in the
##   top-left corner toggles it.

signal changed

const ZOOMS := [0, 1, 2, 3]
const TEXT_SCALES := [1, 2]

var camera_zoom := 0:
	set(v):
		v = v if v in ZOOMS else 0
		if v != camera_zoom:
			camera_zoom = v
			changed.emit()
var text_scale := 2:
	set(v):
		v = v if v in TEXT_SCALES else 2
		if v != text_scale:
			text_scale = v
			changed.emit()
var debug_overlay := OS.is_debug_build():
	set(v):
		if v != debug_overlay:
			debug_overlay = v
			changed.emit()


func _ready() -> void:
	if OS.has_feature("web"):
		_read_url()


## Resets to the defaults (tests).
func reset() -> void:
	camera_zoom = 0
	text_scale = 2
	debug_overlay = OS.is_debug_build()


func _read_url() -> void:
	var q := str(JavaScriptBridge.eval("window.location.search || ''", true))
	for part in q.trim_prefix("?").split("&", false):
		var kv := part.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"zoom":
				camera_zoom = 0 if kv[1] == "auto" else kv[1].to_int()
			"text":
				text_scale = kv[1].to_int()
			"debug":
				debug_overlay = kv[1] == "1"

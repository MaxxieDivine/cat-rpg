extends Node
## Pauses the game and mutes the Master bus while the app is in the
## background, and undoes both when it comes back (autoload "AppFocus").
##
## - Web: the page's document "visibilitychange" event (app switcher, home
##   button, another tab, screen off). Window / canvas focus events aren't
##   used on the web: Android Chrome doesn't send them reliably, and the
##   canvas often stays unfocused after coming back until the next tap,
##   which would leave the game stuck paused.
## - Desktop / native: NOTIFICATION_APPLICATION_FOCUS_OUT / _IN.
## - Native mobile (and any platform that sends them):
##   NOTIFICATION_APPLICATION_PAUSED / _RESUMED.
##
## Each source is a "reason"; the game stays paused while any reason holds.
## It only undoes what it did itself: if the tree was already paused (a menu,
## the player) it never unpauses it, and if the Master bus was already muted
## (the volume button's "off" step) it never unmutes it. The game screen's own
## pause (portrait, game.gd `paused`) is a separate flag it never touches.

const MASTER_BUS := 0

## Off = ignore every event (the test runner turns it off so a window losing
## focus under xvfb can't pause a smoke test).
var enabled := true:
	set(v):
		enabled = v
		if not v:
			_reasons.clear()
			_apply()
## Times the game was sent to the background (catRpgStats, tests).
var pauses := 0

var _reasons: Dictionary = {}
## True while this node is the one holding the tree paused / the bus muted.
var _paused_by_us := false
var _muted_by_us := false
## Keeps the JS callback alive (JavaScriptBridge drops it otherwise).
var _js_visibility: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_js_visibility = JavaScriptBridge.create_callback(_on_visibility_change)
		var document: JavaScriptObject = JavaScriptBridge.get_interface("document")
		if document != null:
			document.addEventListener("visibilitychange", _js_visibility)
		set_reason("hidden", _page_hidden())


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not OS.has_feature("web"):
				set_reason("focus", true)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if not OS.has_feature("web"):
				set_reason("focus", false)
		NOTIFICATION_APPLICATION_PAUSED:
			set_reason("os_paused", true)
		NOTIFICATION_APPLICATION_RESUMED:
			set_reason("os_paused", false)


## True while the app is in the background (any reason).
func backgrounded() -> bool:
	return not _reasons.is_empty()


## Sets or clears one reason to be in the background ("hidden", "focus",
## "os_paused"; tests use it directly).
func set_reason(reason: String, on: bool) -> void:
	if not enabled:
		return
	var was := backgrounded()
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)
	if backgrounded() != was:
		_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if backgrounded():
		pauses += 1
		if not tree.paused:
			tree.paused = true
			_paused_by_us = true
		if not AudioServer.is_bus_mute(MASTER_BUS):
			AudioServer.set_bus_mute(MASTER_BUS, true)
			_muted_by_us = true
	else:
		if _paused_by_us:
			tree.paused = false
			_paused_by_us = false
		if _muted_by_us:
			AudioServer.set_bus_mute(MASTER_BUS, false)
			_muted_by_us = false


func _on_visibility_change(_args: Array) -> void:
	set_reason("hidden", _page_hidden())


func _page_hidden() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("(document.hidden ? 1 : 0)", true)
	return v != null and int(v) == 1

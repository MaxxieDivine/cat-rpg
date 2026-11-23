extends "res://tests/test_base.gd"
## AppFocus (scripts/autoload/app_focus.gd): going to the background pauses
## the tree and mutes Master; coming back undoes only what it did itself.

const MASTER := 0

var focus: Node


func before_each() -> void:
	focus = tree.root.get_node("AppFocus")
	tree.paused = false
	AudioServer.set_bus_mute(MASTER, false)
	focus.enabled = true


func after_each() -> void:
	focus.enabled = false
	tree.paused = false
	AudioServer.set_bus_mute(MASTER, false)


func test_hidden_pauses_and_mutes_then_restores() -> void:
	var before: int = focus.pauses
	focus.set_reason("hidden", true)
	check(tree.paused, "tree paused while hidden")
	check(AudioServer.is_bus_mute(MASTER), "Master muted while hidden")
	check(focus.backgrounded(), "backgrounded")
	check_eq(focus.pauses, before + 1, "counted once")
	focus.set_reason("hidden", true)
	check_eq(focus.pauses, before + 1, "a repeated event doesn't count again")
	focus.set_reason("hidden", false)
	check(not tree.paused, "tree unpaused when visible again")
	check(not AudioServer.is_bus_mute(MASTER), "Master unmuted when visible again")


func test_focus_and_os_pause_behave_the_same() -> void:
	for what in [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN],
			[Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]]:
		focus.notification(what[0])
		check(tree.paused and AudioServer.is_bus_mute(MASTER), "%d pauses and mutes" % what[0])
		focus.notification(what[1])
		check(not tree.paused and not AudioServer.is_bus_mute(MASTER), "%d restores" % what[1])


func test_stays_paused_until_every_reason_clears() -> void:
	focus.set_reason("hidden", true)
	focus.set_reason("focus", true)
	focus.set_reason("focus", false)
	check(tree.paused, "still hidden: still paused")
	focus.set_reason("hidden", false)
	check(not tree.paused, "all clear: running")


func test_never_unpauses_a_tree_someone_else_paused() -> void:
	tree.paused = true
	focus.set_reason("hidden", true)
	focus.set_reason("hidden", false)
	check(tree.paused, "a menu's / the player's pause survives coming back")
	check(not AudioServer.is_bus_mute(MASTER), "sound still comes back")


func test_never_unmutes_the_volume_buttons_off_step() -> void:
	AudioServer.set_bus_mute(MASTER, true)
	focus.set_reason("hidden", true)
	focus.set_reason("hidden", false)
	check(AudioServer.is_bus_mute(MASTER), "muted by the volume button stays muted")
	check(not tree.paused, "the game still resumes")


func test_leaves_the_game_screens_own_pause_alone() -> void:
	var App: PackedScene = load("res://scenes/app.tscn")
	var app: Node = App.instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	app.start_game()
	await tree.process_frame
	app.game.set_paused(true)
	focus.set_reason("hidden", true)
	focus.set_reason("hidden", false)
	check(app.game.paused, "game.gd's portrait pause is untouched")
	app.queue_free()
	await tree.process_frame


func test_disabled_ignores_events_and_releases() -> void:
	focus.set_reason("hidden", true)
	focus.enabled = false
	check(not tree.paused and not AudioServer.is_bus_mute(MASTER), "turning it off releases the pause")
	focus.set_reason("hidden", true)
	check(not tree.paused, "ignored while off")

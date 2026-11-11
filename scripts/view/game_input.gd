extends RefCounted
## Merges keyboard, gamepad and the touch controls into one move vector, a run
## flag and interact presses. Registers the input actions in code so they live
## in one place. preload() this script.

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"run": [KEY_SHIFT],
	"interact": [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
}
const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"run": [JOY_BUTTON_B],
	"interact": [JOY_BUTTON_A],
}
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


static func ensure_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for b: JoyButton in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var ja := InputEventJoypadMotion.new()
			ja.axis = PAD_AXES[action][0]
			ja.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, ja)


## Returns {"move": Vector2 (length <= 1), "run": bool}. The touch stick wins
## while a thumb is on it.
static func read(touch) -> Dictionary:
	if touch != null and touch.is_visible_in_tree() and touch.stick_vector != Vector2.ZERO:
		return {"move": touch.stick_vector, "run": touch.trot}
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return {"move": move, "run": Input.is_action_pressed("run")}

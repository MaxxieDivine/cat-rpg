extends RefCounted
## Base for test suites. Assertions record failures instead of stopping, so a
## test reports every problem it finds. Test methods are named test_* and may
## use `await` (smoke tests need frames).

var tree: SceneTree
## Directory for screenshots, or "" when not requested.
var shots_dir := ""
var failures: Array[String] = []


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String) -> bool:
	return check(actual == expected, "%s: expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func check_near(actual: float, expected: float, tol: float, msg: String) -> bool:
	return check(absf(actual - expected) <= tol, "%s: expected %s ±%s, got %s" % [msg, expected, tol, actual])


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Optional per-test hooks.
func before_each() -> void:
	pass


func after_each() -> void:
	pass

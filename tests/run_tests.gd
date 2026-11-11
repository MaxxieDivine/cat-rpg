extends SceneTree
## Runs every suite in SUITES. Exit code is non-zero if any test fails.
##   godot --headless --path . --script res://tests/run_tests.gd
##   xvfb-run -a godot --path . --script res://tests/run_tests.gd -- --shots=<dir>
## Optional: --only=<substring> runs matching tests only.

const SUITES := [
	"res://tests/test_assets.gd",
	"res://tests/test_data.gd",
	"res://tests/test_world.gd",
	"res://tests/app_smoke.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shots := ""
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)

	var passed := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s (could not load: parse error?)" % path)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (only != "" and not name.contains(only)):
				continue
			var suite: RefCounted = script.new()
			suite.tree = self
			suite.shots_dir = shots
			suite.before_each()
			await suite.call(name)
			suite.after_each()
			var label := "%s::%s" % [path.get_file().get_basename(), name]
			if suite.failures.is_empty():
				print("PASS ", label)
				passed += 1
			else:
				print("FAIL ", label)
				for f in suite.failures:
					print("     - ", f)
				failed += 1
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

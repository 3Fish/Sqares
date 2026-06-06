extends SceneTree

## Headless test runner.
##
## Run with:  godot --headless --script res://tests/run_tests.gd
##
## The project has no third-party test framework, so this is a minimal
## SceneTree-based harness: each `_test_*` method is discovered and executed,
## assertions accumulate failures, and the process exits non-zero if any fail
## (so it can gate CI). Tests live in `res://tests/cases/` and extend `TestCase`.

const CASE_DIR: String = "res://tests/cases/"

var _total: int = 0
var _failed: int = 0
var _current: String = ""


func _initialize() -> void:
	print("\n=== Sqares test run ===")
	for script_path in _discover_cases():
		_run_case(script_path)

	print("\n=== %d assertions, %d failed ===" % [_total, _failed])
	if _failed > 0:
		print("RESULT: FAIL")
		quit(1)
	else:
		print("RESULT: PASS")
		quit(0)


func _discover_cases() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(CASE_DIR)
	if dir == null:
		push_error("Test runner: cannot open %s" % CASE_DIR)
		return paths
	for file in dir.get_files():
		# Godot exports .gd as .gd.remap; tolerate both.
		if file.ends_with(".gd") or file.ends_with(".gd.remap"):
			paths.append(CASE_DIR + file.trim_suffix(".remap"))
	paths.sort()
	return paths


func _run_case(script_path: String) -> void:
	var script: GDScript = load(script_path)
	if script == null:
		push_error("Test runner: failed to load %s" % script_path)
		_failed += 1
		return
	var case = script.new()
	case.runner = self
	for method in case.get_method_list():
		var name: String = method.get("name", "")
		if name.begins_with("_test_"):
			_current = "%s::%s" % [script_path.get_file(), name]
			if case.has_method("before_each"):
				case.before_each()
			case.call(name)
			if case.has_method("after_each"):
				case.after_each()


# --- Assertion API used by TestCase ----------------------------------------

func report(passed: bool, message: String) -> void:
	_total += 1
	if not passed:
		_failed += 1
		print("  [FAIL] %s — %s" % [_current, message])

extends RefCounted
class_name TestCase

## Base class for test cases. Subclasses define `_test_*` methods and call the
## assertion helpers below. The runner injects itself as `runner`.

var runner   ## Set by run_tests.gd; receives assertion results.


func assert_true(value: bool, message: String = "") -> void:
	runner.report(value, "expected true: %s" % message)


func assert_false(value: bool, message: String = "") -> void:
	runner.report(not value, "expected false: %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	runner.report(actual == expected, "expected %s == %s %s" % [actual, expected, message])


func assert_almost_eq(actual: float, expected: float, message: String = "", epsilon: float = 0.0001) -> void:
	runner.report(absf(actual - expected) <= epsilon, "expected ~%s == %s %s" % [actual, expected, message])


func assert_null(value: Variant, message: String = "") -> void:
	runner.report(value == null, "expected null: %s" % message)


func assert_not_null(value: Variant, message: String = "") -> void:
	runner.report(value != null, "expected not null: %s" % message)

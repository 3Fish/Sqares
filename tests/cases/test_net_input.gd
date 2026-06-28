extends TestCase

## Unit tests for the NetPlayerInput wire format (#27).


func _test_to_dict_shape() -> void:
	var input := NetPlayerInput.new()
	input.seq = 7
	input.move_axis = -0.5
	input.jump = true
	input.shoot = true
	input.shield = true
	# 0.5 / -0.5 are exactly representable, so the flattened array compares cleanly.
	input.aim = Vector2(0.5, -0.5)
	var d := input.to_dict()
	assert_eq(d["seq"], 7, "seq serialised")
	assert_almost_eq(d["move_axis"], -0.5, "move_axis serialised")
	assert_true(d["jump"], "jump serialised")
	assert_true(d["shoot"], "shoot serialised")
	assert_true(d["shield"], "shield serialised")
	assert_eq(d["aim"], [0.5, -0.5], "aim flattened to [x, y]")


func _test_from_dict_roundtrip() -> void:
	var original := NetPlayerInput.new()
	original.seq = 42
	original.move_axis = 1.0
	original.jump = true
	original.shoot = false
	original.shield = true
	original.aim = Vector2(1, 0)
	var restored := NetPlayerInput.from_dict(original.to_dict())
	assert_eq(restored.seq, 42, "seq round-trips")
	assert_almost_eq(restored.move_axis, 1.0, "move_axis round-trips")
	assert_true(restored.jump, "jump round-trips")
	assert_false(restored.shoot, "shoot round-trips")
	assert_true(restored.shield, "shield round-trips")
	assert_eq(restored.aim, Vector2(1, 0), "aim round-trips")


func _test_from_dict_defaults_on_empty() -> void:
	var input := NetPlayerInput.from_dict({})
	assert_eq(input.seq, 0, "missing seq -> 0")
	assert_almost_eq(input.move_axis, 0.0, "missing move_axis -> 0")
	assert_false(input.jump, "missing jump -> false")
	assert_false(input.shoot, "missing shoot -> false")
	assert_false(input.shield, "missing shield -> false")
	assert_eq(input.aim, Vector2.ZERO, "missing aim -> ZERO")


func _test_from_dict_clamps_move_axis() -> void:
	# A hostile/buggy payload can't request super-speed through the axis.
	assert_almost_eq(NetPlayerInput.from_dict({"move_axis": 5.0}).move_axis, 1.0, "axis clamped to 1")
	assert_almost_eq(NetPlayerInput.from_dict({"move_axis": -5.0}).move_axis, -1.0, "axis clamped to -1")


func _test_to_vec2_coercion() -> void:
	assert_eq(NetPlayerInput.to_vec2([3, 4]), Vector2(3, 4), "array -> Vector2")
	assert_eq(NetPlayerInput.to_vec2(Vector2(1, 2)), Vector2(1, 2), "Vector2 passes through")
	assert_eq(NetPlayerInput.to_vec2([1]), Vector2.ZERO, "short array -> ZERO")
	assert_eq(NetPlayerInput.to_vec2("nope"), Vector2.ZERO, "non-array -> ZERO")
	assert_eq(NetPlayerInput.to_vec2(null), Vector2.ZERO, "null -> ZERO")

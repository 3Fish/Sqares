extends TestCase

## Pure homing-math coverage for Projectile.compute_homing_velocity (#21).


func _test_homing_noop_cases() -> void:
	var v := Vector2(100.0, 0.0)
	assert_true(Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, 999), 0.0, 0.1) == v,
		"homing=0 leaves velocity unchanged")
	assert_true(Projectile.compute_homing_velocity(Vector2.ZERO, Vector2.ZERO, Vector2(0, 999), 1.0, 0.1) == Vector2.ZERO,
		"zero velocity stays zero")
	var ahead := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(500, 0), 1.0, 0.1)
	assert_true(ahead.is_equal_approx(v), "target dead ahead → no course change")


func _test_homing_small_angle_unclamped() -> void:
	var v := Vector2(100.0, 0.0)
	var target := Vector2(100.0, 10.0)
	var needed := v.angle_to(target - Vector2.ZERO)
	assert_true(absf(needed) < 0.6, "precondition: needed angle within turn budget")
	var out := Projectile.compute_homing_velocity(v, Vector2.ZERO, target, 1.0, 0.1)
	assert_true(is_equal_approx(v.angle_to(out), needed), "small angle rotates fully toward target")


func _test_homing_clamped_to_turn_budget() -> void:
	var v := Vector2(100.0, 0.0)
	var budget := Projectile.HOMING_TURN_RATE * 1.0 * 0.1  # 0.6 rad
	var out := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, -100), 1.0, 0.1)
	assert_true(is_equal_approx(v.angle_to(out), -budget), "perpendicular target clamps to -budget")
	var out_half := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, -100), 0.5, 0.1)
	assert_true(is_equal_approx(v.angle_to(out_half), -budget * 0.5), "homing strength scales turn budget")


func _test_homing_preserves_speed() -> void:
	var v := Vector2(623.0, -141.0)
	var out := Projectile.compute_homing_velocity(v, Vector2(10, 10), Vector2(-300, 400), 1.0, 0.05)
	assert_true(is_equal_approx(v.length(), out.length()), "homing preserves speed magnitude")

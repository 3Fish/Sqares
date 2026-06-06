extends TestCase

## Projectile.setup stores the new homing/knockback params and keeps existing
## call sites working via their 0.0 defaults (#21).


func _test_setup_stores_homing_and_knockback() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null, 0.7, 250.0)
	assert_true(is_equal_approx(proj.homing, 0.7), "Projectile.setup stores homing")
	assert_true(is_equal_approx(proj.knockback_force, 250.0), "Projectile.setup stores knockback_force")
	proj.free()


func _test_setup_defaults_keep_old_call_sites_working() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null)
	assert_true(is_equal_approx(proj.homing, 0.0), "Projectile.setup homing defaults to 0")
	assert_true(is_equal_approx(proj.knockback_force, 0.0), "Projectile.setup knockback defaults to 0")
	proj.free()

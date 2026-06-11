extends TestCase

## explosion_radius plumbing + the pure blast-selection helper (#22).


func _test_setup_stores_explosion_radius() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null, 0.0, 0.0, 120.0)
	assert_true(is_equal_approx(proj.explosion_radius, 120.0), "Projectile.setup stores explosion_radius")
	proj.free()


func _test_setup_explosion_radius_defaults_to_zero() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null)
	assert_true(is_equal_approx(proj.explosion_radius, 0.0), "explosion_radius defaults to 0 for old call sites")
	proj.free()


func _test_in_blast_radius_inside() -> void:
	var center := Vector2(0.0, 0.0)
	assert_true(
		Projectile.is_in_blast_radius(center, Vector2(30.0, 40.0), 100.0),
		"point 50px away is within a 100px blast",
	)


func _test_in_blast_radius_on_edge_inclusive() -> void:
	var center := Vector2(0.0, 0.0)
	assert_true(
		Projectile.is_in_blast_radius(center, Vector2(100.0, 0.0), 100.0),
		"a point exactly on the radius counts as inside",
	)


func _test_in_blast_radius_outside() -> void:
	var center := Vector2(0.0, 0.0)
	assert_false(
		Projectile.is_in_blast_radius(center, Vector2(101.0, 0.0), 100.0),
		"point past the radius is outside the blast",
	)


func _test_in_blast_radius_zero_radius_never_hits() -> void:
	assert_false(
		Projectile.is_in_blast_radius(Vector2.ZERO, Vector2.ZERO, 0.0),
		"a zero radius produces no blast even at the exact center",
	)


func _test_in_blast_radius_negative_radius_never_hits() -> void:
	assert_false(
		Projectile.is_in_blast_radius(Vector2.ZERO, Vector2(1.0, 0.0), -50.0),
		"a negative radius produces no blast",
	)

extends TestCase

## Projectile._find_nearest_target picks the closest group member, excluding
## the shooter, and returns null when no valid targets remain (#21).


func _test_find_nearest_target() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var shooter := Node2D.new()
	tree.root.add_child(shooter)
	shooter.add_to_group(Projectile.TARGET_GROUP)
	var far := Node2D.new()
	far.position = Vector2(500.0, 0.0)
	tree.root.add_child(far)
	far.add_to_group(Projectile.TARGET_GROUP)
	var near := Node2D.new()
	near.position = Vector2(100.0, 0.0)
	tree.root.add_child(near)
	near.add_to_group(Projectile.TARGET_GROUP)
	var proj := Projectile.new()
	tree.root.add_child(proj)
	proj.global_position = Vector2.ZERO
	proj.shooter = shooter

	var found := proj._find_nearest_target()
	assert_true(found == near, "picks nearest group member")
	assert_true(found != shooter, "excludes the shooter even when closest")

	near.remove_from_group(Projectile.TARGET_GROUP)
	far.remove_from_group(Projectile.TARGET_GROUP)
	assert_true(proj._find_nearest_target() == null, "returns null when no valid targets")

	proj.free()
	shooter.free()
	far.free()
	near.free()

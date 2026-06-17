extends TestCase

## Projectile.select_nearest_target picks the closest group member, excluding
## the shooter, and returns null when no valid targets remain (#21).
##
## Exercised as a pure static helper so it needs no live scene tree: the headless
## `--script` runner executes inside `_initialize()` before the tree is live, so
## nodes added to `root` are not yet in-tree and `get_tree()` is unavailable.
## `_find_nearest_target` simply feeds this helper the live group members.


func _test_select_nearest_target() -> void:
	var shooter := Node2D.new()
	var far := Node2D.new()
	far.position = Vector2(500.0, 0.0)
	var near := Node2D.new()
	near.position = Vector2(100.0, 0.0)
	var candidates: Array = [shooter, far, near]

	var found := Projectile.select_nearest_target(candidates, Vector2.ZERO, shooter)
	assert_true(found == near, "picks nearest group member")
	assert_true(found != shooter, "excludes the shooter even when closest")

	# With only the shooter in range there is no valid target.
	assert_true(
		Projectile.select_nearest_target([shooter], Vector2.ZERO, shooter) == null,
		"returns null when no valid targets remain")

	# Non-Node2D candidates are skipped rather than crashing.
	assert_true(
		Projectile.select_nearest_target([RefCounted.new()], Vector2.ZERO, shooter) == null,
		"ignores non-Node2D candidates")

	# Empty candidate set yields no target.
	assert_true(
		Projectile.select_nearest_target([], Vector2.ZERO, shooter) == null,
		"no candidates -> null")

	shooter.free()
	far.free()
	near.free()

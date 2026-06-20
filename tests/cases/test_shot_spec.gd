extends TestCase

## Unit tests for the mutable ShotSpec handed to pre-shoot effects (#68).
##
## ShotSpec is a plain, scene-free data structure, so these exercise it directly:
## the defaults a weapon seeds, the per-bullet stat carry, and the pure `fires()`
## predicate that decides whether any projectile spawns. The stacking of effects
## that mutate a shared spec is covered in `test_effect_engine.gd`.


func _test_default_spec_fires_one_bullet() -> void:
	var spec := ShotSpec.new()
	assert_eq(spec.bullet_count, 1, "defaults to a single bullet")
	assert_false(spec.cancelled, "defaults to not cancelled")
	assert_true(spec.fires(), "a default spec fires")


func _test_spec_carries_per_bullet_stats() -> void:
	var spec := ShotSpec.new(40.0, 1200.0, 2.0, 3, 0.5, 0.25, 100.0, 64.0)
	assert_almost_eq(spec.damage, 40.0, "damage carried")
	assert_almost_eq(spec.speed, 1200.0, "speed carried")
	assert_almost_eq(spec.scale, 2.0, "scale carried")
	assert_eq(spec.bounces, 3, "bounces carried")
	assert_almost_eq(spec.homing, 0.5, "homing carried")
	assert_almost_eq(spec.lifesteal, 0.25, "lifesteal carried")
	assert_almost_eq(spec.knockback, 100.0, "knockback carried")
	assert_almost_eq(spec.explosion_radius, 64.0, "explosion radius carried")


func _test_cancelled_spec_does_not_fire() -> void:
	var spec := ShotSpec.new()
	spec.cancelled = true
	assert_false(spec.fires(), "a cancelled spec fires nothing")


func _test_zero_count_spec_does_not_fire() -> void:
	var spec := ShotSpec.new()
	spec.bullet_count = 0
	assert_false(spec.fires(), "a zero-count spec fires nothing")

	spec.bullet_count = -2
	assert_false(spec.fires(), "a negative count fires nothing")


func _test_multi_bullet_spec_fires() -> void:
	var spec := ShotSpec.new()
	spec.bullet_count = 3
	assert_true(spec.fires(), "a multi-bullet spec fires")
	assert_eq(spec.bullet_count, 3, "the requested count is retained")

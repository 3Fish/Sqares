extends TestCase

## Unit tests for the pure ammo/reload maths (#113). AmmoModel has no scene-tree
## dependency, so the fire/deny/consume/reload decisions are exercised directly,
## mirroring the other pure combat/physics helpers.


# --- can_fire ----------------------------------------------------------------

func _test_can_fire_with_enough_rounds() -> void:
	assert_true(AmmoModel.can_fire(3, 1), "a full magazine covers a single round")
	assert_true(AmmoModel.can_fire(2, 2), "exactly enough rounds still fires")


func _test_cannot_fire_when_cost_exceeds_magazine() -> void:
	assert_false(AmmoModel.can_fire(1, 2), "an over-cost shot is denied (A3)")
	assert_false(AmmoModel.can_fire(0, 1), "an empty magazine can't fire a paid shot")


func _test_zero_or_negative_cost_never_gates() -> void:
	assert_true(AmmoModel.can_fire(0, 0), "a free shot fires from an empty magazine")
	assert_true(AmmoModel.can_fire(0, -1), "a negative cost is treated as free")


# --- consume -----------------------------------------------------------------

func _test_consume_draws_down_the_magazine() -> void:
	assert_eq(AmmoModel.consume(3, 1), 2, "one round consumed")
	assert_eq(AmmoModel.consume(5, 3), 2, "a multi-round cost draws down by the cost")


func _test_consume_clamps_at_zero() -> void:
	assert_eq(AmmoModel.consume(1, 5), 0, "consumption never drives the count negative")


func _test_consume_ignores_non_positive_cost() -> void:
	assert_eq(AmmoModel.consume(3, 0), 3, "a zero cost leaves the magazine untouched")
	assert_eq(AmmoModel.consume(3, -2), 3, "a negative cost leaves the magazine untouched")


# --- reloaded ----------------------------------------------------------------

func _test_no_reload_before_idle_duration() -> void:
	assert_eq(AmmoModel.reloaded(1, 3, 0.5, 1.0), 1, "still draining: not idle long enough")


func _test_full_reload_once_idle_duration_reached() -> void:
	assert_eq(AmmoModel.reloaded(1, 3, 1.0, 1.0), 3, "idle exactly reload_time snaps to full")
	assert_eq(AmmoModel.reloaded(0, 3, 2.5, 1.0), 3, "an empty magazine refills instantly when idle")


func _test_reload_is_a_full_refill_even_when_partly_full() -> void:
	# The reload is not per-round trickle: a partly-full magazine jumps straight
	# to full once the idle duration elapses (maintainer's answer on #113).
	assert_eq(AmmoModel.reloaded(2, 3, 1.0, 1.0), 3, "partly-full magazine refills fully")


func _test_full_magazine_is_left_alone() -> void:
	assert_eq(AmmoModel.reloaded(3, 3, 5.0, 1.0), 3, "an already-full magazine is unchanged")
	assert_eq(AmmoModel.reloaded(4, 3, 5.0, 1.0), 4, "an over-full magazine is not trimmed")


func _test_non_positive_reload_time_is_always_reloaded() -> void:
	assert_eq(AmmoModel.reloaded(0, 3, 0.0, 0.0), 3, "a zero reload_time reloads immediately")

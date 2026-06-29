extends TestCase

## Reflecting shield model (#138): the shield is a manually-raised, timed reflect
## window backed by a recharging charge clip. These cover the Health-side state
## machine — activation/charge spend, the duration window, charge regeneration,
## and that the shield no longer blocks HP damage (it deflects at the projectile
## layer instead). Health is a plain Node, instantiated directly like the rest of
## the combat unit tests.

const HealthScript = preload("res://scripts/combat/health.gd")

var h: Health


func before_each() -> void:
	h = HealthScript.new()


func after_each() -> void:
	if h:
		h.free()
		h = null


func _stats(charges: float, duration := 0.5, recharge := 2.0) -> Dictionary:
	return {
		"max_health": 100.0,
		"shield_charges": charges,
		"shield_duration": duration,
		"shield_recharge": recharge,
	}


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

func _test_initialize_starts_with_a_full_charge_clip_and_no_window() -> void:
	h.initialize(_stats(2.0))
	assert_eq(h.shield_charges, 2, "initialize seeds the charge clip from the stat (the max)")
	assert_false(h.is_shielded(), "a fresh life starts with the shield down")


# ---------------------------------------------------------------------------
# Activation
# ---------------------------------------------------------------------------

func _test_activate_spends_a_charge_and_raises_the_shield() -> void:
	h.initialize(_stats(1.0))
	assert_true(h.activate_shield(), "activation succeeds with a charge available")
	assert_eq(h.shield_charges, 0, "raising the shield spends one charge")
	assert_true(h.is_shielded(), "the reflect window is open after activation")


func _test_activate_with_no_charges_is_refused() -> void:
	h.initialize(_stats(0.0))
	assert_false(h.activate_shield(), "no charge -> no activation")
	assert_false(h.is_shielded(), "the shield stays down")


func _test_activate_while_already_up_does_not_double_spend() -> void:
	h.initialize(_stats(2.0))
	assert_true(h.activate_shield(), "first activation raises the shield")
	assert_false(h.activate_shield(), "a second activation while up is refused")
	assert_eq(h.shield_charges, 1, "the second (refused) activation spends no charge")


func _test_shield_raised_signal_fires_on_activation() -> void:
	h.initialize(_stats(1.0))
	var fired := [false]
	h.shield_raised.connect(func() -> void: fired[0] = true)
	h.activate_shield()
	assert_true(fired[0], "a successful activation emits shield_raised")


# ---------------------------------------------------------------------------
# Duration window
# ---------------------------------------------------------------------------

func _test_window_closes_after_its_duration() -> void:
	h.initialize(_stats(1.0, 0.5))
	h.activate_shield()
	h.advance_shield(0.3)
	assert_true(h.is_shielded(), "the shield is still up partway through its duration")
	h.advance_shield(0.2)
	assert_false(h.is_shielded(), "the shield drops once its duration lapses")


# ---------------------------------------------------------------------------
# Charge regeneration
# ---------------------------------------------------------------------------

func _test_charge_regenerates_after_the_recharge_interval() -> void:
	h.initialize(_stats(2.0, 0.5, 2.0))
	h.activate_shield()  # 2 -> 1, now below the max of 2
	h.advance_shield(1.0)
	assert_eq(h.shield_charges, 1, "no charge back before the full recharge interval")
	h.advance_shield(1.0)
	assert_eq(h.shield_charges, 2, "one charge regenerates after recharge seconds")


func _test_charges_do_not_regenerate_past_the_max() -> void:
	h.initialize(_stats(1.0, 0.5, 2.0))  # max 1, already full
	h.advance_shield(10.0)
	assert_eq(h.shield_charges, 1, "a full clip never overfills")


# ---------------------------------------------------------------------------
# The shield no longer blocks HP damage (it deflects at the projectile layer)
# ---------------------------------------------------------------------------

func _test_take_damage_is_not_blocked_by_a_raised_shield() -> void:
	h.initialize(_stats(1.0))
	h.activate_shield()
	h.take_damage(40.0)
	assert_almost_eq(h.current_hp, 60.0, "take_damage applies to HP even while shielded (#138)")


# ---------------------------------------------------------------------------
# Reset / mid-match stat changes
# ---------------------------------------------------------------------------

func _test_reset_restores_a_full_clip_and_drops_the_window() -> void:
	h.initialize(_stats(2.0))
	h.activate_shield()  # spend one and raise
	h.reset()
	assert_eq(h.shield_charges, 2, "reset refills the charge clip for the new life")
	assert_false(h.is_shielded(), "reset drops any open reflect window")


func _test_apply_stats_grants_a_raised_max_immediately() -> void:
	h.initialize(_stats(1.0))
	h.apply_stats(_stats(3.0))
	assert_eq(h.shield_charges, 3, "raising the max mid-match grants the extra charges now")


func _test_apply_stats_clamps_live_charges_to_a_lowered_max() -> void:
	h.initialize(_stats(3.0))
	h.apply_stats(_stats(1.0))
	assert_eq(h.shield_charges, 1, "lowering the max clamps the live charge count down")

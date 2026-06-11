extends TestCase

## shield_charges: shields are granted from stats and consumed (one per hit,
## fully blocking it) before HP is touched (#22).


func _test_shield_granted_from_initialize() -> void:
	var h := Health.new()
	h.initialize({"max_health": 100.0, "shield_charges": 2.0})
	assert_eq(h.shield_charges, 2, "initialize reads shield_charges from stats")
	h.free()


func _test_shield_blocks_hit_without_losing_hp() -> void:
	var h := Health.new()
	h.initialize({"max_health": 100.0, "shield_charges": 1.0})
	h.take_damage(40.0)
	assert_eq(h.shield_charges, 0, "a hit consumes one shield charge")
	assert_true(is_equal_approx(h.current_hp, 100.0), "the shielded hit deals no HP damage")
	assert_false(h.is_dead(), "a shielded player is not dead")
	h.free()


func _test_damage_applies_once_shields_depleted() -> void:
	var h := Health.new()
	h.initialize({"max_health": 100.0, "shield_charges": 1.0})
	h.take_damage(40.0)  # consumes the only shield
	h.take_damage(40.0)  # now lands on HP
	assert_eq(h.shield_charges, 0, "shields stay at zero once depleted")
	assert_true(is_equal_approx(h.current_hp, 60.0), "damage applies normally after shields run out")
	h.free()


func _test_shield_broken_signal_emitted_on_consume() -> void:
	var h := Health.new()
	h.initialize({"max_health": 100.0, "shield_charges": 1.0})
	var fired := [false]
	h.shield_broken.connect(func() -> void: fired[0] = true)
	h.take_damage(10.0)
	assert_true(fired[0], "consuming a shield emits shield_broken")
	h.free()


func _test_apply_stats_updates_shield_charges() -> void:
	var h := Health.new()
	h.initialize({"max_health": 100.0, "shield_charges": 0.0})
	h.apply_stats({"max_health": 100.0, "shield_charges": 3.0})
	assert_eq(h.shield_charges, 3, "apply_stats grants additional shields mid-match")
	h.free()

extends TestCase

## Stat plumbing for bullet_homing + knockback_force (#21) and explosion_radius
## (#22) through Weapon.apply_stats.


func _test_weapon_reads_new_stats() -> void:
	var w := Weapon.new()
	w.apply_stats({"bullet_homing": 0.6, "knockback_force": 420.0, "explosion_radius": 96.0})
	assert_true(is_equal_approx(w.bullet_homing, 0.6), "Weapon reads bullet_homing from stats")
	assert_true(is_equal_approx(w.knockback_force, 420.0), "Weapon reads knockback_force from stats")
	assert_true(is_equal_approx(w.explosion_radius, 96.0), "Weapon reads explosion_radius from stats")
	w.free()


func _test_weapon_defaults_preserved_when_keys_absent() -> void:
	var w := Weapon.new()
	w.apply_stats({"damage": 50.0})
	assert_true(is_equal_approx(w.bullet_homing, 0.0), "bullet_homing default preserved when absent")
	assert_true(is_equal_approx(w.knockback_force, 0.0), "knockback_force default preserved when absent")
	assert_true(is_equal_approx(w.explosion_radius, 0.0), "explosion_radius default preserved when absent")
	w.free()

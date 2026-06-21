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


# --- ammo / reload wiring (#113) ---------------------------------------------

func _test_weapon_reads_ammo_stats() -> void:
	var w := Weapon.new()
	w.apply_stats({"magazine_size": 5.0, "reload_time": 2.5})
	assert_eq(w.magazine_size, 5, "Weapon reads magazine_size (as an int round count)")
	assert_true(is_equal_approx(w.reload_time, 2.5), "Weapon reads reload_time")
	w.free()


func _test_reset_ammo_fills_the_magazine() -> void:
	var w := Weapon.new()
	w.apply_stats({"magazine_size": 4.0})
	w.reset_ammo()
	assert_eq(w.get_ammo(), 4, "reset_ammo refills to the magazine size")
	w.free()


func _test_idle_reload_refills_after_reload_time() -> void:
	var w := Weapon.new()
	w.apply_stats({"magazine_size": 3.0, "reload_time": 1.0})
	w.reset_ammo()
	w._ammo = 1  # simulate two rounds already spent this magazine
	# Not idle long enough yet.
	w._tick_reload(0.5)
	assert_eq(w.get_ammo(), 1, "no reload before the idle duration elapses")
	# Crossing the reload_time threshold snaps the magazine back to full.
	w._tick_reload(0.6)
	assert_eq(w.get_ammo(), 3, "magazine refills fully once idle for reload_time")
	w.free()

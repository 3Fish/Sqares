extends Node

## Dependency-free headless test harness, run as a real scene so global
## `class_name` identifiers and autoloads resolve and added nodes get a live
## tree (`get_tree()`). Run with:
##   godot --headless --path . res://tests/run_tests.tscn
## Exits 0 when all assertions pass, 1 otherwise.
##
## Covers issue #21: bullet_homing (steering) + knockback_force (impulse on hit),
## plus the stat plumbing that feeds them through Weapon / Projectile / Player.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_weapon_reads_new_stats()
	_test_weapon_defaults_preserved()
	_test_projectile_setup_stores_stats()
	_test_homing_noop_cases()
	_test_homing_small_angle_unclamped()
	_test_homing_clamped_to_turn_budget()
	_test_homing_preserves_speed()
	_test_player_knockback()
	_test_find_nearest_target()

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Stat plumbing
# ---------------------------------------------------------------------------

func _test_weapon_reads_new_stats() -> void:
	var w := Weapon.new()
	w.apply_stats({"bullet_homing": 0.6, "knockback_force": 420.0})
	_check(is_equal_approx(w.bullet_homing, 0.6), "Weapon reads bullet_homing from stats")
	_check(is_equal_approx(w.knockback_force, 420.0), "Weapon reads knockback_force from stats")
	w.free()


func _test_weapon_defaults_preserved() -> void:
	var w := Weapon.new()
	# Stats dict without the new keys must leave the defaults (0.0) untouched.
	w.apply_stats({"damage": 50.0})
	_check(is_equal_approx(w.bullet_homing, 0.0), "bullet_homing default preserved when absent")
	_check(is_equal_approx(w.knockback_force, 0.0), "knockback_force default preserved when absent")
	w.free()


func _test_projectile_setup_stores_stats() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null, 0.7, 250.0)
	_check(is_equal_approx(proj.homing, 0.7), "Projectile.setup stores homing")
	_check(is_equal_approx(proj.knockback_force, 250.0), "Projectile.setup stores knockback_force")
	# Defaults keep older call sites (test scenes) working.
	var proj2 := Projectile.new()
	proj2.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null)
	_check(is_equal_approx(proj2.homing, 0.0), "Projectile.setup homing defaults to 0")
	_check(is_equal_approx(proj2.knockback_force, 0.0), "Projectile.setup knockback defaults to 0")
	proj.free()
	proj2.free()


# ---------------------------------------------------------------------------
# Homing steering math (pure function)
# ---------------------------------------------------------------------------

func _test_homing_noop_cases() -> void:
	var v := Vector2(100.0, 0.0)
	# homing == 0 → unchanged
	_check(
		Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, 999), 0.0, 0.1) == v,
		"homing=0 leaves velocity unchanged"
	)
	# zero velocity → unchanged (no direction to steer)
	_check(
		Projectile.compute_homing_velocity(Vector2.ZERO, Vector2.ZERO, Vector2(0, 999), 1.0, 0.1) == Vector2.ZERO,
		"zero velocity stays zero"
	)
	# target exactly ahead → no rotation
	var ahead := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(500, 0), 1.0, 0.1)
	_check(ahead.is_equal_approx(v), "target dead ahead → no course change")


func _test_homing_small_angle_unclamped() -> void:
	# Target only slightly off-axis: turn budget (0.6 rad) exceeds the needed
	# angle, so the bullet should point straight at the target this frame.
	var v := Vector2(100.0, 0.0)
	var target := Vector2(100.0, 10.0)
	var needed := v.angle_to(target - Vector2.ZERO)
	_check(absf(needed) < 0.6, "precondition: needed angle within turn budget")
	var out := Projectile.compute_homing_velocity(v, Vector2.ZERO, target, 1.0, 0.1)
	_check(is_equal_approx(v.angle_to(out), needed), "small angle rotates fully toward target")


func _test_homing_clamped_to_turn_budget() -> void:
	# Target 90° away with a large delta: rotation must clamp to the budget.
	var v := Vector2(100.0, 0.0)
	var budget := Projectile.HOMING_TURN_RATE * 1.0 * 0.1  # 0.6 rad
	var out := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, -100), 1.0, 0.1)
	_check(is_equal_approx(v.angle_to(out), -budget), "perpendicular target clamps to -budget")
	# Half homing strength → half the turn budget.
	var out_half := Projectile.compute_homing_velocity(v, Vector2.ZERO, Vector2(0, -100), 0.5, 0.1)
	_check(is_equal_approx(v.angle_to(out_half), -budget * 0.5), "homing strength scales turn budget")


func _test_homing_preserves_speed() -> void:
	var v := Vector2(623.0, -141.0)
	var out := Projectile.compute_homing_velocity(v, Vector2(10, 10), Vector2(-300, 400), 1.0, 0.05)
	_check(is_equal_approx(v.length(), out.length()), "homing preserves speed magnitude")


# ---------------------------------------------------------------------------
# Knockback impulse
# ---------------------------------------------------------------------------

func _test_player_knockback() -> void:
	# Instantiated (not added to the tree) so apply_knockback is exercised without
	# triggering the scene's full _ready wiring.
	var p: Player = PLAYER_SCENE.instantiate()
	p.velocity = Vector2(10.0, 0.0)
	p.apply_knockback(Vector2(100.0, -50.0))
	_check(p.velocity.is_equal_approx(Vector2(110.0, -50.0)), "knockback adds impulse to velocity")
	# A dead player is not knocked around.
	p._dead = true
	p.apply_knockback(Vector2(500.0, 0.0))
	_check(p.velocity.is_equal_approx(Vector2(110.0, -50.0)), "dead player ignores knockback")
	p.free()


# ---------------------------------------------------------------------------
# Target selection (integration: needs the scene tree + group)
# ---------------------------------------------------------------------------

func _test_find_nearest_target() -> void:
	var shooter := Node2D.new()
	add_child(shooter)
	shooter.add_to_group(Projectile.TARGET_GROUP)  # shooter is in-group but must be skipped

	var far := Node2D.new()
	far.position = Vector2(500.0, 0.0)
	add_child(far)
	far.add_to_group(Projectile.TARGET_GROUP)

	var near := Node2D.new()
	near.position = Vector2(100.0, 0.0)
	add_child(near)
	near.add_to_group(Projectile.TARGET_GROUP)

	var proj := Projectile.new()
	add_child(proj)
	proj.global_position = Vector2.ZERO
	proj.shooter = shooter

	var found := proj._find_nearest_target()
	_check(found == near, "picks nearest group member")
	_check(found != shooter, "excludes the shooter even when closest")

	# With no other targets, returns null.
	near.remove_from_group(Projectile.TARGET_GROUP)
	far.remove_from_group(Projectile.TARGET_GROUP)
	_check(proj._find_nearest_target() == null, "returns null when no valid targets")

	proj.free()
	shooter.free()
	far.free()
	near.free()


# ---------------------------------------------------------------------------
# Harness helpers
# ---------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok   - %s" % label)
	else:
		_failed += 1
		printerr("  FAIL - %s" % label)

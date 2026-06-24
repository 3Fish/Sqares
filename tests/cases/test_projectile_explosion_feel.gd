extends TestCase

## Explosion "feel" (#52): splash damage is a fraction of the bullet damage (A1),
## a knocking-back bullet's blast shoves splash victims radially (A2), and the
## blast pushes physics blocks in range (A3). The maths lives in the pure, scene-
## free helpers `Projectile.explosion_damage` / `Projectile.explosion_impulse`;
## the dispatch helpers (`splash_combatants`, `push_blocks_in_blast`) are tested
## with lightweight stubs so no live scene tree / RigidBody2D stepping is needed,
## matching the rest of the combat-helper tests (`CLAUDE.md`).


# A combatant that records the damage and knockback impulse it receives.
class CombatantSpy extends Node2D:
	var taken: float = 0.0
	var hits: int = 0
	var last_impulse: Vector2 = Vector2.ZERO
	var knockbacks: int = 0
	func take_damage(amount: float, _source: Node = null) -> void:
		taken += amount
		hits += 1
	func apply_knockback(impulse: Vector2) -> void:
		last_impulse = impulse
		knockbacks += 1


# A physics block that records the push impulse it receives.
class BlockSpy extends Node2D:
	var last_impulse: Vector2 = Vector2.ZERO
	var pushes: int = 0
	func receive_push(impulse: Vector2) -> void:
		last_impulse = impulse
		pushes += 1


# --- Pure helper: explosion_damage (A1) -------------------------------------

func _test_explosion_damage_is_a_fraction_of_bullet_damage() -> void:
	assert_almost_eq(Projectile.explosion_damage(100.0, 0.5), 50.0,
		"a 0.5 factor halves the bullet damage")
	assert_almost_eq(Projectile.explosion_damage(100.0, 0.25), 25.0,
		"a 0.25 factor is a quarter of the bullet damage")
	assert_almost_eq(Projectile.explosion_damage(100.0, 1.0), 100.0,
		"a 1.0 factor matches a direct hit")


func _test_explosion_damage_clamps_negative_factor_to_zero() -> void:
	assert_almost_eq(Projectile.explosion_damage(100.0, -2.0), 0.0,
		"a negative factor cannot heal a victim — clamped to no damage")


# --- Pure helper: explosion_impulse (A2/A3) ---------------------------------

func _test_explosion_impulse_points_radially_outward() -> void:
	var imp := Projectile.explosion_impulse(Vector2.ZERO, Vector2(10.0, 0.0), 200.0, 0.5)
	assert_almost_eq(imp.x, 100.0, "magnitude is base_force × factor along the radial")
	assert_almost_eq(imp.y, 0.0, "no off-axis component for an on-axis target")


func _test_explosion_impulse_direction_is_away_from_center() -> void:
	var imp := Projectile.explosion_impulse(Vector2(5.0, 5.0), Vector2(5.0, 25.0), 100.0, 1.0)
	assert_true(imp.x == 0.0 and imp.y > 0.0, "pushes a below-centre target downward, away from the blast")
	assert_almost_eq(imp.length(), 100.0, "length equals base_force × factor")


func _test_explosion_impulse_zero_without_knockback() -> void:
	assert_eq(Projectile.explosion_impulse(Vector2.ZERO, Vector2(10.0, 0.0), 0.0, 0.5), Vector2.ZERO,
		"a non-knockback bullet (base_force 0) imparts no impulse")
	assert_eq(Projectile.explosion_impulse(Vector2.ZERO, Vector2(10.0, 0.0), 200.0, 0.0), Vector2.ZERO,
		"a zero factor imparts no impulse")


func _test_explosion_impulse_zero_at_exact_center() -> void:
	assert_eq(Projectile.explosion_impulse(Vector2(7.0, 7.0), Vector2(7.0, 7.0), 200.0, 0.5), Vector2.ZERO,
		"a target exactly on the blast centre has no defined direction — no impulse")


func _test_explosion_impulse_clamps_negative_factor() -> void:
	assert_eq(Projectile.explosion_impulse(Vector2.ZERO, Vector2(10.0, 0.0), 200.0, -1.0), Vector2.ZERO,
		"a negative factor is clamped — no inward suck")


# --- setup stores the new factors -------------------------------------------

func _test_setup_stores_explosion_factors() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null, 0.0, 0.0, 120.0, 0.25, 0.75)
	assert_almost_eq(proj.explosion_damage_factor, 0.25, "setup stores explosion_damage_factor")
	assert_almost_eq(proj.explosion_knockback_factor, 0.75, "setup stores explosion_knockback_factor")
	proj.free()


func _test_setup_explosion_factors_default_to_half() -> void:
	var proj := Projectile.new()
	proj.setup(Vector2.RIGHT, 800.0, 25.0, 1.0, 0, 0.0, null)
	assert_almost_eq(proj.explosion_damage_factor, 0.5, "damage factor defaults to 0.5 for old call sites")
	assert_almost_eq(proj.explosion_knockback_factor, 0.5, "knockback factor defaults to 0.5 for old call sites")
	proj.free()


# --- splash_combatants: damage (A1) -----------------------------------------

func _test_splash_deals_factored_damage_to_in_range_victims() -> void:
	var victim := CombatantSpy.new()
	victim.position = Vector2(50.0, 0.0)
	var proj := Projectile.new()
	proj.damage = 100.0
	proj.explosion_radius = 150.0
	proj.explosion_damage_factor = 0.5
	proj.splash_combatants([victim], Vector2.ZERO, null)
	assert_eq(victim.hits, 1, "an in-range victim is hit once by the splash")
	assert_almost_eq(victim.taken, 50.0, "splash damage is factor × bullet damage, not the full 100")
	proj.free()
	victim.free()


func _test_splash_spares_out_of_range_and_the_direct_target() -> void:
	var far := CombatantSpy.new()
	far.position = Vector2(500.0, 0.0)
	var direct := CombatantSpy.new()
	direct.position = Vector2(10.0, 0.0)
	var proj := Projectile.new()
	proj.damage = 100.0
	proj.explosion_radius = 150.0
	proj.splash_combatants([far, direct], Vector2.ZERO, direct)
	assert_eq(far.hits, 0, "a victim past the radius takes no splash")
	assert_eq(direct.hits, 0, "the directly-hit target is not double-damaged by its own blast")
	proj.free()
	far.free()
	direct.free()


# --- splash_combatants: knockback (A2) --------------------------------------

func _test_splash_knockback_only_when_the_bullet_knocks_back() -> void:
	var victim := CombatantSpy.new()
	victim.position = Vector2(0.0, 40.0)  # directly below the blast
	var proj := Projectile.new()
	proj.damage = 100.0
	proj.explosion_radius = 150.0
	proj.knockback_force = 0.0  # this bullet does not knock back
	proj.splash_combatants([victim], Vector2.ZERO, null)
	assert_eq(victim.knockbacks, 0, "a non-knockback bullet's blast imparts no knockback")

	var victim2 := CombatantSpy.new()
	victim2.position = Vector2(0.0, 40.0)
	var proj2 := Projectile.new()
	proj2.damage = 100.0
	proj2.explosion_radius = 150.0
	proj2.knockback_force = 300.0
	proj2.explosion_knockback_factor = 0.5
	proj2.splash_combatants([victim2], Vector2.ZERO, null)
	assert_eq(victim2.knockbacks, 1, "a knockback bullet's blast knocks splash victims back")
	assert_almost_eq(victim2.last_impulse.y, 150.0, "impulse is knockback_force × factor, radially outward (downward)")
	assert_almost_eq(victim2.last_impulse.x, 0.0, "no off-axis component for a straight-below victim")
	proj.free()
	victim.free()
	proj2.free()
	victim2.free()


# --- push_blocks_in_blast: physics-block push (A3) --------------------------

func _test_blast_pushes_in_range_physics_blocks() -> void:
	var near := BlockSpy.new()
	near.position = Vector2(60.0, 0.0)
	var far := BlockSpy.new()
	far.position = Vector2(400.0, 0.0)
	var proj := Projectile.new()
	proj.explosion_radius = 150.0
	proj.knockback_force = 200.0
	proj.explosion_knockback_factor = 0.5
	proj.push_blocks_in_blast([near, far], Vector2.ZERO)
	assert_eq(near.pushes, 1, "an in-range physics block is pushed by the blast")
	assert_almost_eq(near.last_impulse.x, 100.0, "block push is knockback_force × factor, radially outward")
	assert_eq(far.pushes, 0, "an out-of-range physics block is not pushed")
	proj.free()
	near.free()
	far.free()


func _test_blast_does_not_push_blocks_without_knockback() -> void:
	var block := BlockSpy.new()
	block.position = Vector2(60.0, 0.0)
	var proj := Projectile.new()
	proj.explosion_radius = 150.0
	proj.knockback_force = 0.0  # non-knockback bullet
	proj.push_blocks_in_blast([block], Vector2.ZERO)
	assert_eq(block.pushes, 0, "a non-knockback bullet's blast does not shove physics blocks")
	proj.free()
	block.free()

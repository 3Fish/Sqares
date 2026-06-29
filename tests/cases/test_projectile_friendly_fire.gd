extends TestCase

## Friendly-fire / team target filtering (#62).
##
## A shot may damage a target only when they are hostile. With friendly fire on
## (the default, and the only setting that matters in Free-for-all) every target
## is hostile, preserving the historical behaviour; with it off, a target on the
## shooter's own team — including the shooter itself on a bounce-back — is
## friendly and is skipped (direct hit consumed, homing / splash filtered).
##
## Exercised through the pure static helpers (`Projectile.is_hostile`,
## `combatant_id`, `filter_hostile`) so it needs no live scene tree, mirroring
## the existing `test_projectile_target_selection` approach. The homing case
## additionally composes `filter_hostile` with `select_nearest_target` to show a
## bullet steers past a nearer teammate toward a farther enemy.


## Minimal combatant stub: a positioned node carrying a `player_id`, like a real
## Player, so the team helpers can read it without standing up the player scene.
class _Combatant extends Node2D:
	var player_id: int = 0


# A 2v2 layout: players 0 and 2 on team A, players 1 and 3 on team B.
const _TEAMS := {0: 0, 1: 1, 2: 0, 3: 1}


func _test_friendly_fire_on_is_always_hostile() -> void:
	# With FF on, team membership is irrelevant — every target is damageable.
	assert_true(Projectile.is_hostile(0, 2, true, _TEAMS), "teammate is hostile when FF on")
	assert_true(Projectile.is_hostile(0, 1, true, _TEAMS), "enemy is hostile when FF on")
	assert_true(Projectile.is_hostile(0, 0, true, _TEAMS), "self is hostile when FF on (bounce-back self-damage)")


func _test_friendly_fire_off_spares_teammates_and_self() -> void:
	assert_false(Projectile.is_hostile(0, 2, false, _TEAMS), "teammate is friendly when FF off")
	assert_false(Projectile.is_hostile(0, 0, false, _TEAMS), "self is friendly when FF off (no bounce-back self-damage)")
	assert_true(Projectile.is_hostile(0, 1, false, _TEAMS), "opposing team stays hostile when FF off")
	assert_true(Projectile.is_hostile(0, 3, false, _TEAMS), "the other opposing player stays hostile")


func _test_ffa_off_distinct_players_are_enemies() -> void:
	# Empty / partial team map = Free-for-all: each id is its own team, so distinct
	# players are mutual enemies even with FF off; only a self-hit is friendly.
	assert_true(Projectile.is_hostile(0, 1, false, {}), "distinct FFA players are enemies")
	assert_false(Projectile.is_hostile(0, 0, false, {}), "an FFA player never hits itself when FF off")


func _test_noncombatant_target_is_always_hostile() -> void:
	# A target with no team identity (id -1) is damageable regardless of the rule,
	# so non-player combatants are never accidentally shielded.
	assert_true(Projectile.is_hostile(0, -1, false, _TEAMS), "a non-combatant target is hostile")
	assert_true(Projectile.is_hostile(-1, 2, false, _TEAMS), "a shooter with no id deals damage normally")


func _test_combatant_id_reads_player_id() -> void:
	var c := _Combatant.new()
	c.player_id = 3
	assert_eq(Projectile.combatant_id(c), 3, "reads player_id off a combatant")

	var plain := Node2D.new()
	assert_eq(Projectile.combatant_id(plain), -1, "a node without player_id is a non-combatant")
	assert_eq(Projectile.combatant_id(null), -1, "null is a non-combatant")

	c.free()
	plain.free()


func _test_filter_hostile_on_keeps_every_candidate() -> void:
	var a := _make(0, Vector2.ZERO)   # team A (shooter's team)
	var b := _make(1, Vector2.ZERO)   # team B
	var candidates: Array = [a, b]
	var kept := Projectile.filter_hostile(candidates, 0, true, _TEAMS)
	assert_eq(kept.size(), 2, "FF on keeps both the teammate and the enemy")
	_free_all([a, b])


func _test_filter_hostile_off_drops_teammates_only() -> void:
	var mate := _make(2, Vector2.ZERO)     # team A — shooter (0) teammate
	var enemy := _make(1, Vector2.ZERO)    # team B — enemy
	var stray := Node2D.new()              # no player_id — non-combatant, kept
	var kept := Projectile.filter_hostile([mate, enemy, stray], 0, false, _TEAMS)
	assert_eq(kept.size(), 2, "the teammate is dropped, the enemy and non-combatant remain")
	assert_true(kept.has(enemy), "enemy retained")
	assert_true(kept.has(stray), "non-combatant retained")
	assert_false(kept.has(mate), "teammate filtered out")
	mate.free()
	enemy.free()
	stray.free()


func _test_homing_steers_past_a_nearer_teammate_to_a_farther_enemy() -> void:
	# Shooter (id 0, team A) with a teammate 8px away and an enemy 200px away.
	# With FF on, homing locks the nearer teammate; with FF off it must skip the
	# teammate and pick the farther enemy.
	var shooter := _make(0, Vector2.ZERO)
	var mate := _make(2, Vector2(8.0, 0.0))     # team A, nearest
	var enemy := _make(1, Vector2(200.0, 0.0))  # team B, farther
	var group: Array = [shooter, mate, enemy]

	var ff_on := Projectile.filter_hostile(group, 0, true, _TEAMS)
	assert_true(
		Projectile.select_nearest_target(ff_on, shooter.global_position, shooter) == mate,
		"FF on: homing locks the nearer teammate (historical behaviour)")

	var ff_off := Projectile.filter_hostile(group, 0, false, _TEAMS)
	assert_true(
		Projectile.select_nearest_target(ff_off, shooter.global_position, shooter) == enemy,
		"FF off: homing skips the teammate and steers to the enemy")

	_free_all(group)


# --- Friendly-fire damage multiplier (#112) ---------------------------------
# The direct-hit path no longer fizzles a friendly shot: a same-team target takes
# `base_damage × friendly_fire` (clamped >= 0), seeded 1.0 (FF on) / 0.0 (FF off)
# and reshaped by pre-shoot effects. `is_friendly_target` answers the team-
# membership question independent of the toggle; `friendly_hit_damage` does the
# clamped scaling. Both are pure statics, exercised here without a scene.


func _test_is_friendly_target_is_toggle_independent() -> void:
	# Same team (incl. a self-hit) is friendly; opposing teams and non-combatants
	# are not — regardless of the match FF toggle, which only seeds the multiplier.
	assert_true(Projectile.is_friendly_target(0, 2, _TEAMS), "a teammate is a friendly target")
	assert_true(Projectile.is_friendly_target(0, 0, _TEAMS), "a self-hit (bounce-back) is friendly")
	assert_false(Projectile.is_friendly_target(0, 1, _TEAMS), "an opponent is not friendly")
	assert_false(Projectile.is_friendly_target(0, -1, _TEAMS), "a non-combatant target is never friendly")
	assert_false(Projectile.is_friendly_target(-1, 2, _TEAMS), "a shooter with no id has no friends")


func _test_is_friendly_target_ffa_only_self() -> void:
	# In Free-for-all (empty/partial team map) every distinct player is an enemy, so
	# only a self-hit is friendly.
	assert_false(Projectile.is_friendly_target(0, 1, {}), "distinct FFA players are not friendly")
	assert_true(Projectile.is_friendly_target(0, 0, {}), "an FFA player is friendly to itself")


func _test_friendly_hit_damage_scales_and_clamps() -> void:
	# FF on (1.0) deals full friendly damage; FF off (0.0) deals none; a card value
	# in between scales linearly, and >1 amplifies.
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, 1.0), 25.0, "x1 is the full hit (FF on default)")
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, 0.0), 0.0, "x0 deals no friendly damage (FF off default)")
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, 0.5), 12.5, "x0.5 halves the friendly damage")
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, 2.0), 50.0, "x2 amplifies the friendly damage")


func _test_friendly_hit_damage_clamps_negative_to_zero() -> void:
	# A negative multiplier (e.g. the stacked FF-off example (0 - 0.1) * 1.1 = -0.11)
	# never heals a teammate — it clamps to no damage, not negative damage (#112).
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, -0.11), 0.0, "a negative multiplier deals zero, never heals")
	assert_almost_eq(Projectile.friendly_hit_damage(25.0, -5.0), 0.0, "a large negative multiplier still clamps to zero")


func _test_friendly_hit_damage_preserves_base_sign() -> void:
	# The clamp is on the multiplier, not the base: a shield-penetration heal-through
	# bullet (#138, negative base) still heals a teammate at full multiplier rather
	# than being zeroed.
	assert_almost_eq(Projectile.friendly_hit_damage(-10.0, 1.0), -10.0, "a negative base (heal-through) is preserved at x1")


# --- helpers ----------------------------------------------------------------

func _make(player_id: int, pos: Vector2) -> _Combatant:
	var c := _Combatant.new()
	c.player_id = player_id
	c.position = pos
	return c


func _free_all(nodes: Array) -> void:
	for n in nodes:
		n.free()

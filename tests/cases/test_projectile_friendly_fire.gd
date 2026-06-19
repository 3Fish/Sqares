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


# --- helpers ----------------------------------------------------------------

func _make(player_id: int, pos: Vector2) -> _Combatant:
	var c := _Combatant.new()
	c.player_id = player_id
	c.position = pos
	return c


func _free_all(nodes: Array) -> void:
	for n in nodes:
		n.free()

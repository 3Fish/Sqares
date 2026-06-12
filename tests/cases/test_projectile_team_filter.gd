extends TestCase

## Team / friendly-fire filtering on the projectile target paths (#62, deferred
## from #26). The homing, explosion-splash, and direct-hit paths all funnel
## through `Projectile.is_hostile`, the pure id-based decision tested here; the
## `_gui_input`-style live collision/scene wiring is boot-verified (the same
## limitation noted for `test_projectile_target_selection`).


# ---------------------------------------------------------------------------
# Free-for-all: every distinct player is hostile, so behaviour is unchanged.
# ---------------------------------------------------------------------------

func _test_is_hostile_ffa_distinct_players() -> void:
	GameManager.setup_match("crossroads", 4, 5)  # FFA
	assert_true(Projectile.is_hostile(0, 1), "FFA: a shot hits a different player")
	assert_true(Projectile.is_hostile(3, 0), "FFA: a shot hits a different player")


func _test_is_hostile_self_is_friendly() -> void:
	GameManager.setup_match("crossroads", 4, 5)  # FFA
	assert_false(Projectile.is_hostile(2, 2), "a bullet never damages its own shooter")


# ---------------------------------------------------------------------------
# Teams: teammates are friendly, opponents hostile.
# ---------------------------------------------------------------------------

func _test_is_hostile_teams_friendly_fire_off() -> void:
	var teams := TeamsMode.new().assign_teams(4)  # {0:0,1:1,2:0,3:1}
	GameManager.setup_match("crossroads", 4, 5, teams, &"teams")
	assert_false(Projectile.is_hostile(0, 2), "teammates do not damage each other")
	assert_false(Projectile.is_hostile(3, 1), "teammates do not damage each other")
	assert_true(Projectile.is_hostile(0, 1), "opponents are still hit")
	assert_true(Projectile.is_hostile(2, 3), "opponents are still hit")


# ---------------------------------------------------------------------------
# Unresolved combatants (non-player target, sourceless / freed shooter) are
# treated as hostile so non-team contexts behave exactly as before teams.
# ---------------------------------------------------------------------------

func _test_is_hostile_null_ids_are_hostile() -> void:
	var teams := TeamsMode.new().assign_teams(4)
	GameManager.setup_match("crossroads", 4, 5, teams, &"teams")
	assert_true(Projectile.is_hostile(null, 0), "a sourceless shot hits anything")
	assert_true(Projectile.is_hostile(0, null), "a non-player target is always hittable")
	assert_true(Projectile.is_hostile(null, null), "two unresolved combatants are hostile")

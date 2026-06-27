extends TestCase

## Integration test for GameManager.setup_match against the live autoload,
## across the local 2-4 player range (#25).


func _test_setup_match_tracks_every_player() -> void:
	for count in [2, 3, 4]:
		GameManager.setup_match("crossroads", count, 5)
		assert_eq(GameManager.win_counts.size(), count, "setup_match(%d) tracks %d players" % [count, count])
		var all_zero := true
		for i in count:
			if GameManager.win_counts.get(i, -1) != 0:
				all_zero = false
		assert_true(all_zero, "setup_match(%d) zeroes every win count" % count)


## setup_match carries the per-match friendly-fire rule (#62): it defaults to on
## so existing callers keep the historical behaviour, and an explicit value is
## stored for the hit adjudication to read.
func _test_setup_match_sets_friendly_fire() -> void:
	GameManager.setup_match("crossroads", 2, 5)
	assert_true(GameManager.friendly_fire, "friendly fire defaults to on when unspecified")

	GameManager.setup_match("crossroads", 2, 5, {0: 0, 1: 0}, &"teams", false)
	assert_false(GameManager.friendly_fire, "friendly fire reflects the value passed to setup_match")

	GameManager.setup_match("crossroads", 2, 5, {0: 0, 1: 1}, &"teams", true)
	assert_true(GameManager.friendly_fire, "friendly fire can be re-enabled by a later setup")


## setup_match carries the smaller-team card-draw handicap toggle (#147): it
## defaults off so existing callers keep the historical behaviour.
func _test_setup_match_sets_team_handicap() -> void:
	GameManager.setup_match("crossroads", 2, 5)
	assert_false(GameManager.team_handicap, "handicap defaults off when unspecified")

	GameManager.setup_match("crossroads", 4, 5, {0: 0, 1: 0, 2: 1, 3: 1}, &"teams", true, true)
	assert_true(GameManager.team_handicap, "handicap reflects the value passed to setup_match")

	GameManager.setup_match("crossroads", 2, 5, {0: 0, 1: 1}, &"teams", true, false)
	assert_false(GameManager.team_handicap, "handicap can be turned off by a later setup")

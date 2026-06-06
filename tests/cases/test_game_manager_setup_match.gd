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

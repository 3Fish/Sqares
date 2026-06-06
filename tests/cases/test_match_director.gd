extends TestCase

## Unit tests for MatchDirector's pure local-multiplayer helpers (#25).


func _test_clamp_player_count() -> void:
	assert_eq(MatchDirector.clamp_player_count(0), 2, "clamp 0 -> min 2")
	assert_eq(MatchDirector.clamp_player_count(1), 2, "clamp 1 -> min 2")
	assert_eq(MatchDirector.clamp_player_count(2), 2, "clamp 2 -> 2")
	assert_eq(MatchDirector.clamp_player_count(3), 3, "clamp 3 -> 3")
	assert_eq(MatchDirector.clamp_player_count(4), 4, "clamp 4 -> 4")
	assert_eq(MatchDirector.clamp_player_count(5), 4, "clamp 5 -> max 4")
	assert_eq(MatchDirector.clamp_player_count(-3), 2, "clamp negative -> min 2")


func _test_resolve_spawn_positions() -> void:
	var two: Array[Vector2] = [Vector2(-400, 0), Vector2(400, 0)]

	# Enough spawns: first `count` are returned verbatim.
	var p2 := MatchDirector.resolve_spawn_positions(2, two)
	assert_eq(p2.size(), 2, "2 players -> 2 positions")
	assert_true(p2[0] == two[0] and p2[1] == two[1], "2 players reuse exact spawns")

	# Fewer spawns than players: real spawns kept, extras nudged, none overlap.
	var p4 := MatchDirector.resolve_spawn_positions(4, two)
	assert_eq(p4.size(), 4, "4 players -> 4 positions")
	assert_true(p4[0] == two[0] and p4[1] == two[1], "first 2 positions are the real spawns")
	assert_true(_all_unique(p4), "4 positions are all unique (no stacking)")

	# No spawn metadata at all: players fan out symmetrically around origin.
	var p3 := MatchDirector.resolve_spawn_positions(3, [] as Array[Vector2])
	assert_eq(p3.size(), 3, "no-spawn fallback -> 3 positions")
	assert_true(_all_unique(p3), "no-spawn fallback positions are unique")
	var sum_x := p3[0].x + p3[1].x + p3[2].x
	assert_true(absf(sum_x) < 0.001, "no-spawn fallback is symmetric around origin")

	# Degenerate input.
	assert_eq(MatchDirector.resolve_spawn_positions(0, two).size(), 0, "0 players -> 0 positions")


func _all_unique(points: Array) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i] == points[j]:
				return false
	return true

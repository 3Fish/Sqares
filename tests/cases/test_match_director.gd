extends TestCase

## Unit tests for MatchDirector's pure local-multiplayer helpers (#25) and the
## colour-derived team-assignment / announcement glue (#134).


func before_each() -> void:
	MatchConfig.reset()


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


func _test_resolve_arena_id() -> void:
	# A pending playtest arena (#36) overrides the configured fallback.
	assert_eq(MatchDirector.resolve_arena_id("my_arena", "crossroads"), "my_arena",
		"pending id wins over the export")
	# No pending arena: fall back to the export (normal "Play" from the menu).
	assert_eq(MatchDirector.resolve_arena_id("", "crossroads"), "crossroads",
		"empty pending -> fallback")
	assert_eq(MatchDirector.resolve_arena_id("   ", "crossroads"), "crossroads",
		"whitespace-only pending -> fallback")


func _all_unique(points: Array) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i] == points[j]:
				return false
	return true


# ---------------------------------------------------------------------------
# Colour-derived team assignment + announcement glue (#134)
# ---------------------------------------------------------------------------
# `_team_assignment` and `_team_label` are thin instance glue that read the staged
# colours + active mode; they don't touch the @onready scene siblings, so they run
# on a bare MatchDirector node without the full match scene.

func _make_director(mode: GameMode) -> MatchDirector:
	var d := MatchDirector.new()
	d.player_count = 4
	d._mode = mode
	return d


func _test_local_teams_derives_assignment_from_colours_and_names_by_colour() -> void:
	# P1+P3 share colour 0, P2+P4 share colour 1 -> a 2v2 keyed by the colour index,
	# and the announcement names a team by its colour (#134 / #132 A4).
	MatchConfig.configure("teams", 4, 5, "crossroads", true, [], [0, 1, 0, 1])
	var d := _make_director(TeamsMode.new())
	assert_eq(d._team_assignment(), {0: 0, 1: 1, 2: 0, 3: 1}, "local Teams derives teams from colours")
	assert_true(d._colors_drive_teams, "colour-derived flag set")
	assert_eq(d._team_label(0), "Team %s" % PlayerPalette.name_at(0), "team labelled by its colour")
	d.free()


func _test_ffa_keeps_per_player_teams_even_with_shared_colours() -> void:
	# A4: in FFA, the same colour does NOT mean the same team — every player stays solo.
	MatchConfig.configure("ffa", 4, 5, "crossroads", true, [], [0, 0, 0, 0])
	var d := _make_director(GameMode.new())
	assert_eq(d._team_assignment(), {0: 0, 1: 1, 2: 2, 3: 3}, "FFA stays per-player despite shared colours")
	assert_false(d._colors_drive_teams, "colour-derived flag clear in FFA")
	assert_eq(d._team_label(2), "Player 3", "FFA keeps its player labels")
	d.free()


func _test_teams_without_staged_colours_falls_back_to_round_robin() -> void:
	# Direct match load / editor playtest (#36): nothing staged -> the existing
	# round-robin split is unchanged, and labels stay "Team N".
	var d := _make_director(TeamsMode.new())
	assert_eq(d._team_assignment(), {0: 0, 1: 1, 2: 0, 3: 1}, "no staged colours -> round-robin 2v2")
	assert_false(d._colors_drive_teams, "colour-derived flag clear without staged colours")
	assert_eq(d._team_label(1), "Team 2", "round-robin Teams keeps numbered labels")
	d.free()

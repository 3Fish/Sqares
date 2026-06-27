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


func _test_resolve_team_spawn_positions() -> void:
	# Two clear spatial clusters: a left pair and a right pair.
	var quad: Array[Vector2] = [
		Vector2(-400, -50), Vector2(400, -50), Vector2(-400, 50), Vector2(400, 50)]

	# 2v2 (players 0,2 vs 1,3): each pair must land on the same side, and the two
	# teams must end up on opposite sides.
	var pos := MatchDirector.resolve_team_spawn_positions([0, 1, 0, 1], quad)
	assert_eq(pos.size(), 4, "2v2 -> 4 positions")
	assert_true(_all_unique(pos), "2v2 clustered positions are unique (no stacking)")
	assert_true(_same_set(pos, quad), "2v2 clustering is a permutation of the spawn slots")
	assert_almost_eq(pos[0].x, pos[2].x, "team 0 (players 0,2) share a side")
	assert_almost_eq(pos[1].x, pos[3].x, "team 1 (players 1,3) share a side")
	assert_true(absf(pos[0].x - pos[1].x) > 0.001, "opposing teams are on different sides")

	# Deterministic: identical inputs yield identical placement (host/client agree).
	var again := MatchDirector.resolve_team_spawn_positions([0, 1, 0, 1], quad)
	assert_true(pos[0] == again[0] and pos[1] == again[1] \
		and pos[2] == again[2] and pos[3] == again[3], "clustering is deterministic")

	# FFA (every player on their own team): falls back to the plain spawn order,
	# so non-team placement is byte-for-byte unchanged.
	var ffa := MatchDirector.resolve_team_spawn_positions([0, 1, 2, 3], quad)
	var plain := MatchDirector.resolve_spawn_positions(4, quad)
	assert_true(ffa[0] == plain[0] and ffa[1] == plain[1] \
		and ffa[2] == plain[2] and ffa[3] == plain[3], "FFA keeps the plain spawn order")

	# 1v1: distinct teams == player count, so the plain order is preserved.
	var two: Array[Vector2] = [Vector2(-400, 0), Vector2(400, 0)]
	var duel := MatchDirector.resolve_team_spawn_positions([0, 1], two)
	assert_true(duel[0] == two[0] and duel[1] == two[1], "1v1 placement unchanged")

	# 2v1 on a line: the two teammates take adjacent spots; the lone enemy is set
	# apart at the far end.
	var line: Array[Vector2] = [Vector2(-400, 0), Vector2(0, 0), Vector2(400, 0)]
	var trio := MatchDirector.resolve_team_spawn_positions([0, 1, 0], line)
	assert_eq(trio.size(), 3, "2v1 -> 3 positions")
	assert_true(_all_unique(trio), "2v1 clustered positions are unique")
	assert_true(_same_set(trio, line), "2v1 clustering is a permutation of the spawn slots")
	assert_true(_same_set([trio[0], trio[2]], [Vector2(-400, 0), Vector2(0, 0)]),
		"2v1 teammates cluster on the adjacent left/centre spawns")
	assert_true(trio[1] == Vector2(400, 0), "2v1 lone enemy is seeded apart at the far end")

	# Degenerate inputs degrade gracefully.
	assert_eq(MatchDirector.resolve_team_spawn_positions([], quad).size(), 0,
		"no players -> no positions")
	var solo := MatchDirector.resolve_team_spawn_positions([0], two)
	assert_eq(solo.size(), 1, "single player -> single position")


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


## True when `a` and `b` hold the same points regardless of order (the spawn
## slots are unique, so a same-size mutual-containment check suffices).
func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for p in a:
		if not b.has(p):
			return false
	return true


# ---------------------------------------------------------------------------
# Smaller-team card-draw handicap (#147) — resolve_draw_counts
# ---------------------------------------------------------------------------

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _test_draw_counts_losers_are_team_based() -> void:
	# A2: a player draws iff its *team* lost — a member of the winning team draws
	# nothing even though it may have been killed. Here team 0 (players 0,2) wins;
	# only the losing team 1 (players 1,3) draws, and only the base count off-handicap.
	var team_of := {0: 0, 1: 1, 2: 0, 3: 1}
	var counts := MatchDirector.resolve_draw_counts(team_of, 0, 2, false, _rng(1))
	assert_eq(counts.size(), 2, "only the losing team's two players draw")
	assert_false(counts.has(0), "winning-team player 0 draws nothing")
	assert_false(counts.has(2), "winning-team player 2 (even if killed) draws nothing")
	assert_eq(int(counts[1]), 2, "loser draws the base count")
	assert_eq(int(counts[3]), 2, "loser draws the base count")


func _test_draw_counts_ffa_is_base_for_every_loser() -> void:
	# FFA: each player is their own one-person team, so no team trails the winner —
	# every loser draws exactly the base count, handicap on or off (A3).
	var ffa := {0: 0, 1: 1, 2: 2, 3: 3}
	var off := MatchDirector.resolve_draw_counts(ffa, 0, 3, false, _rng(2))
	var on := MatchDirector.resolve_draw_counts(ffa, 0, 3, true, _rng(2))
	assert_eq(off, {1: 3, 2: 3, 3: 3}, "FFA handicap-off: base for every loser, winner absent")
	assert_eq(on, {1: 3, 2: 3, 3: 3}, "FFA handicap-on changes nothing (every team size 1)")


func _test_draw_counts_equal_teams_get_no_extra() -> void:
	# 2v2 with the handicap on: the losing team is the same size as the winner, so
	# max(0, win - own) == 0 and only the base count is drawn.
	var counts := MatchDirector.resolve_draw_counts({0: 0, 1: 1, 2: 0, 3: 1}, 0, 2, true, _rng(3))
	assert_eq(counts, {1: 2, 3: 2}, "equal-size losing team draws only the base")


func _test_draw_counts_solo_team_gets_full_deficit() -> void:
	# 1v2: the lone loser (team 0) trails the 2-player winner by one, so it draws
	# base + 1. The whole deficit lands on the single member (per = 1, no remainder).
	var counts := MatchDirector.resolve_draw_counts({0: 0, 1: 1, 2: 1}, 1, 2, true, _rng(4))
	assert_eq(counts, {0: 3}, "solo losing team draws base + (winner - 1)")


func _test_draw_counts_remainder_is_split_across_team() -> void:
	# 2v3 with the handicap on: deficit is 1 extra draw across a 2-player losing
	# team, so exactly one (random) member gets +1 and the other gets the base only.
	var counts := MatchDirector.resolve_draw_counts(
		{0: 0, 1: 0, 2: 1, 3: 1, 4: 1}, 1, 2, true, _rng(7))
	assert_eq(counts.size(), 2, "only the 2-player losing team draws")
	assert_false(counts.has(2), "winning-team members draw nothing")
	var total: int = int(counts[0]) + int(counts[1])
	assert_eq(total, 5, "base*2 + 1 extra distributed across the team")
	var bumped := 1 if int(counts[0]) == 3 else 0
	bumped += 1 if int(counts[1]) == 3 else 0
	assert_eq(bumped, 1, "exactly one member gets the single extra draw")
	assert_true(int(counts[0]) >= 2 and int(counts[1]) >= 2, "no member drops below the base")


func _test_draw_counts_multi_team_measures_each_loser_vs_winner() -> void:
	# A1's worked example: team A=1 player, team B=2, team C=3; team C wins. Each
	# losing team's extra is measured against the winner: A trails by 2, B by 1.
	var team_of := {0: 10, 1: 20, 2: 20, 3: 30, 4: 30, 5: 30}
	var counts := MatchDirector.resolve_draw_counts(team_of, 30, 2, true, _rng(11))
	assert_eq(counts.size(), 3, "all three losing players draw; the winners do not")
	assert_false(counts.has(3) or counts.has(4) or counts.has(5), "winning team draws nothing")
	assert_eq(int(counts[0]), 4, "solo team A trails the 3-player winner by 2 -> base + 2")
	var team_b: int = int(counts[1]) + int(counts[2])
	assert_eq(team_b, 5, "team B (2 players) shares 1 extra: base*2 + 1")


func _test_draw_counts_never_negative_when_loser_is_larger() -> void:
	# A losing team larger than the winner gets no extra (max(0, ...)), never fewer
	# than the base.
	var counts := MatchDirector.resolve_draw_counts({0: 0, 1: 1, 2: 1, 3: 1}, 0, 2, true, _rng(5))
	assert_eq(counts, {1: 2, 2: 2, 3: 2}, "bigger losing team still draws only the base")


func _test_draw_counts_draw_round_has_no_handicap() -> void:
	# A mutual-elimination draw (winning_team == -1) has no reference team, so every
	# player draws the base regardless of the handicap toggle.
	var counts := MatchDirector.resolve_draw_counts({0: 0, 1: 1}, -1, 2, true, _rng(6))
	assert_eq(counts, {0: 2, 1: 2}, "a draw yields the base for everyone")


func _test_draw_counts_is_deterministic_for_a_seed() -> void:
	# Same seed + inputs -> identical split, the property host/offline play relies on.
	var team_of := {0: 0, 1: 0, 2: 1, 3: 1, 4: 1}
	var a := MatchDirector.resolve_draw_counts(team_of, 1, 2, true, _rng(99))
	var b := MatchDirector.resolve_draw_counts(team_of, 1, 2, true, _rng(99))
	assert_eq(a, b, "identical seed yields identical handicap split")


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

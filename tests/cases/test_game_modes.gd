extends TestCase

## Unit + integration tests for game modes (#26): the GameMode / TeamsMode team
## assignment, GameManager's team-aware win tracking, and MatchDirector's mode
## resolution. All pure logic — no scene tree required.


# ---------------------------------------------------------------------------
# GameMode (Free-for-all base)
# ---------------------------------------------------------------------------

func _test_ffa_each_player_is_own_team() -> void:
	var ffa := GameMode.new()
	assert_eq(ffa.id, &"ffa", "base mode id is ffa")
	for count in [2, 3, 4]:
		var teams := ffa.assign_teams(count)
		assert_eq(teams.size(), count, "ffa(%d) assigns every player" % count)
		var distinct := {}
		for pid: int in teams:
			assert_eq(teams[pid], pid, "ffa player %d is on its own team" % pid)
			distinct[teams[pid]] = true
		assert_eq(distinct.size(), count, "ffa(%d) has %d distinct teams" % [count, count])


func _test_ffa_team_label_is_player() -> void:
	var ffa := GameMode.new()
	assert_eq(ffa.team_label(0), "Player 1", "ffa team label is 1-based player")
	assert_eq(ffa.team_label(3), "Player 4", "ffa team label is 1-based player")


# ---------------------------------------------------------------------------
# TeamsMode
# ---------------------------------------------------------------------------

func _test_teams_round_robin_two_teams() -> void:
	var mode := TeamsMode.new()  # default 2 teams
	assert_eq(mode.id, &"teams", "teams mode id")
	assert_eq(mode.team_count, 2, "default team_count is 2")

	# 4 players -> 2v2 ({0,2} vs {1,3})
	var t4 := mode.assign_teams(4)
	assert_eq(t4, {0: 0, 1: 1, 2: 0, 3: 1}, "4 players split 2v2 round-robin")

	# 3 players -> 2v1 ({0,2} vs {1})
	var t3 := mode.assign_teams(3)
	assert_eq(t3, {0: 0, 1: 1, 2: 0}, "3 players split 2v1 round-robin")

	# 2 players -> 1v1
	var t2 := mode.assign_teams(2)
	assert_eq(t2, {0: 0, 1: 1}, "2 players split 1v1")


func _test_teams_custom_team_count() -> void:
	var mode := TeamsMode.new(3)
	assert_eq(mode.team_count, 3, "custom team_count honoured")
	var t4 := mode.assign_teams(4)
	assert_eq(t4, {0: 0, 1: 1, 2: 2, 3: 0}, "4 players across 3 teams round-robin")


func _test_teams_team_label() -> void:
	var mode := TeamsMode.new()
	assert_eq(mode.team_label(0), "Team 1", "teams label is 1-based team")
	assert_eq(mode.team_label(1), "Team 2", "teams label is 1-based team")


# ---------------------------------------------------------------------------
# GameManager.setup_match — FFA default (regression) + teams
# ---------------------------------------------------------------------------

func _test_setup_match_ffa_default_tracks_per_player() -> void:
	# No team_assignment -> Free-for-all, identical to the pre-#26 behaviour.
	for count in [2, 3, 4]:
		GameManager.setup_match("crossroads", count, 5)
		assert_eq(GameManager.mode_id, &"ffa", "default mode is ffa")
		assert_eq(GameManager.win_counts.size(), count, "ffa(%d) tracks %d teams" % [count, count])
		for i in count:
			assert_eq(GameManager.win_counts.get(i, -1), 0, "ffa win count zeroed for %d" % i)
			assert_eq(GameManager.team_for(i), i, "ffa player %d maps to own team" % i)


func _test_setup_match_teams_tracks_per_team() -> void:
	var teams := TeamsMode.new().assign_teams(4)  # {0:0,1:1,2:0,3:1}
	GameManager.setup_match("crossroads", 4, 5, teams, &"teams")
	assert_eq(GameManager.mode_id, &"teams", "mode id stored")
	assert_eq(GameManager.win_counts.size(), 2, "4 players / 2 teams -> 2 win counters")
	assert_eq(GameManager.win_counts.get(0, -1), 0, "team 0 zeroed")
	assert_eq(GameManager.win_counts.get(1, -1), 0, "team 1 zeroed")
	assert_eq(GameManager.team_for(2), 0, "player 2 on team 0")
	assert_eq(GameManager.team_for(3), 1, "player 3 on team 1")


# ---------------------------------------------------------------------------
# GameManager.record_win — team aware
# ---------------------------------------------------------------------------

func _test_record_win_increments_whole_team() -> void:
	var teams := TeamsMode.new().assign_teams(4)  # {0:0,1:1,2:0,3:1}
	GameManager.setup_match("crossroads", 4, 2, teams, &"teams")

	# Player 2 (team 0) wins a round; teammate player 0 sees the same tally.
	var over := GameManager.record_win(2)
	assert_false(over, "1 of 2 wins does not end the match")
	assert_eq(GameManager.wins_for_player(0), 1, "teammate shares the team win")
	assert_eq(GameManager.wins_for_player(2), 1, "winner's team has 1 win")
	assert_eq(GameManager.wins_for_player(1), 0, "opposing team unaffected")


func _test_record_win_ends_match_and_emits_team() -> void:
	var teams := TeamsMode.new().assign_teams(4)
	GameManager.setup_match("crossroads", 4, 2, teams, &"teams")

	var emitted: Array = []
	var cb := func(team_id: int): emitted.append(team_id)
	GameManager.match_ended.connect(cb)

	GameManager.record_win(0)            # team 0 -> 1
	var over := GameManager.record_win(2)  # team 0 -> 2 == threshold
	GameManager.match_ended.disconnect(cb)

	assert_true(over, "reaching the threshold ends the match")
	assert_eq(GameManager.state, GameManager.State.MATCH_END, "state is MATCH_END")
	assert_eq(emitted, [0], "match_ended emits the winning TEAM id once")


func _test_record_win_ffa_is_per_player() -> void:
	GameManager.setup_match("crossroads", 3, 2)  # FFA
	var over := GameManager.record_win(1)
	assert_false(over, "1 of 2 FFA wins does not end")
	assert_eq(GameManager.wins_for_player(1), 1, "FFA win counts for that player only")
	assert_eq(GameManager.wins_for_player(0), 0, "other FFA players unaffected")
	assert_eq(GameManager.wins_for_player(2), 0, "other FFA players unaffected")


# ---------------------------------------------------------------------------
# GameManager.are_enemies — combat friendly-fire / target filtering (#62)
# ---------------------------------------------------------------------------

func _test_are_enemies_ffa_distinct_players_are_enemies() -> void:
	GameManager.setup_match("crossroads", 4, 5)  # FFA: each player own team
	assert_true(GameManager.are_enemies(0, 1), "FFA: distinct players are enemies")
	assert_true(GameManager.are_enemies(2, 3), "FFA: distinct players are enemies")
	assert_false(GameManager.are_enemies(1, 1), "a player is never its own enemy")


func _test_are_enemies_teams_respects_assignment() -> void:
	var teams := TeamsMode.new().assign_teams(4)  # {0:0,1:1,2:0,3:1}
	GameManager.setup_match("crossroads", 4, 5, teams, &"teams")
	assert_false(GameManager.are_enemies(0, 2), "teammates (0 & 2) are not enemies")
	assert_false(GameManager.are_enemies(1, 3), "teammates (1 & 3) are not enemies")
	assert_true(GameManager.are_enemies(0, 1), "opposing players are enemies")
	assert_true(GameManager.are_enemies(2, 3), "opposing players are enemies")
	assert_false(GameManager.are_enemies(2, 2), "a player is never its own enemy")


# ---------------------------------------------------------------------------
# GameManager.teams_remaining — round-end detection helper
# ---------------------------------------------------------------------------

func _test_teams_remaining() -> void:
	var team_map := {0: 0, 1: 1, 2: 0, 3: 1}  # 2v2

	# Both teams have a survivor -> round continues.
	assert_eq(GameManager.teams_remaining([0, 1, 2, 3], team_map).size(), 2, "both teams alive")
	assert_eq(GameManager.teams_remaining([0, 3], team_map).size(), 2, "one each alive")

	# Only team 0 has survivors -> round over.
	assert_eq(GameManager.teams_remaining([0, 2], team_map).size(), 1, "team 0 last standing")

	# Nobody alive -> draw (zero teams).
	assert_eq(GameManager.teams_remaining([], team_map).size(), 0, "draw -> no teams")

	# Unmapped ids fall back to their own id (FFA semantics).
	assert_eq(GameManager.teams_remaining([5, 6], {}).size(), 2, "unmapped ids are own teams")


# ---------------------------------------------------------------------------
# MatchDirector.resolve_mode
# ---------------------------------------------------------------------------

func _test_resolve_mode_falls_back_to_ffa() -> void:
	# Unknown id (and an empty registry in the headless harness) -> FFA.
	var mode := MatchDirector.resolve_mode("does_not_exist")
	assert_not_null(mode, "resolve_mode always returns a mode")
	assert_eq(mode.id, &"ffa", "unknown mode resolves to FFA")


func _test_resolve_mode_uses_registry() -> void:
	# Register the built-in teams script directly and confirm resolution wires
	# it up (the base-game mod does this at load; the harness does not run mods).
	GameModeRegistry.register("teams", preload("res://scripts/modes/teams_mode.gd"))
	var mode := MatchDirector.resolve_mode("teams")
	assert_true(mode is TeamsMode, "registered id resolves to its TeamsMode")
	assert_eq(mode.id, &"teams", "resolved mode carries its id")

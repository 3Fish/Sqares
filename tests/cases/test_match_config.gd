extends TestCase

## Unit + integration tests for MatchConfig (#26): the pure normalisation helpers
## and the one-shot match-setup hand-off against the live autoload.


func before_each() -> void:
	MatchConfig.reset()


# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func _test_clamp_wins() -> void:
	assert_eq(MatchConfig.clamp_wins(0), MatchConfig.MIN_WINS, "0 clamps up to MIN_WINS")
	assert_eq(MatchConfig.clamp_wins(MatchConfig.MIN_WINS), MatchConfig.MIN_WINS, "min stays")
	assert_eq(MatchConfig.clamp_wins(5), 5, "in-range stays")
	assert_eq(MatchConfig.clamp_wins(MatchConfig.MAX_WINS), MatchConfig.MAX_WINS, "max stays")
	assert_eq(MatchConfig.clamp_wins(999), MatchConfig.MAX_WINS, "too-high clamps down to MAX_WINS")


func _test_resolve_choice_prefers_request_then_fallback_then_first() -> void:
	var avail := ["ffa", "teams"]
	assert_eq(MatchConfig.resolve_choice("teams", avail, "ffa"), "teams", "registered request is kept")
	assert_eq(MatchConfig.resolve_choice("bogus", avail, "ffa"), "ffa", "unknown request -> fallback when available")
	assert_eq(MatchConfig.resolve_choice("bogus", ["a", "b"], "ffa"), "a", "unknown request + unavailable fallback -> first option")
	assert_eq(MatchConfig.resolve_choice("bogus", [], "ffa"), "ffa", "empty registry -> fallback verbatim")


# ---------------------------------------------------------------------------
# One-shot hand-off
# ---------------------------------------------------------------------------

func _test_configure_normalises_and_marks_pending() -> void:
	assert_false(MatchConfig.pending, "starts not pending after reset")
	MatchConfig.configure("teams", 9, 999, "highrise", false)
	assert_true(MatchConfig.pending, "configure marks pending")
	assert_eq(MatchConfig.game_mode, "teams", "mode stored verbatim")
	assert_eq(MatchConfig.player_count, MatchDirector.MAX_PLAYERS, "player count clamped to range")
	assert_eq(MatchConfig.wins_needed, MatchConfig.MAX_WINS, "wins clamped to range")
	assert_eq(MatchConfig.arena_id, "highrise", "arena stored verbatim")
	assert_false(MatchConfig.friendly_fire, "friendly fire stored")


func _test_configure_clamps_low_player_count() -> void:
	MatchConfig.configure("ffa", 1, 3, "crossroads")
	assert_eq(MatchConfig.player_count, MatchDirector.MIN_PLAYERS, "player count clamped up to min")
	assert_eq(MatchConfig.wins_needed, 3, "in-range wins kept")
	assert_true(MatchConfig.friendly_fire, "friendly fire defaults on when unspecified")


func _test_consume_is_one_shot() -> void:
	MatchConfig.configure("teams", 3, 4, "crossroads")
	assert_true(MatchConfig.consume(), "first consume sees the staged config")
	assert_false(MatchConfig.pending, "pending cleared after consume")
	assert_false(MatchConfig.consume(), "second consume returns false (no double-adopt)")
	# Fields stay readable after consuming so the director can copy them out.
	assert_eq(MatchConfig.game_mode, "teams", "fields stay readable post-consume")
	assert_eq(MatchConfig.player_count, 3, "player count stays readable post-consume")


func _test_reset_restores_defaults() -> void:
	MatchConfig.configure("teams", 4, 8, "highrise", false)
	MatchConfig.reset()
	assert_false(MatchConfig.pending, "reset drops pending")
	assert_eq(MatchConfig.game_mode, MatchConfig.DEFAULT_MODE, "reset restores default mode")
	assert_eq(MatchConfig.player_count, MatchDirector.MIN_PLAYERS, "reset restores default player count")
	assert_eq(MatchConfig.wins_needed, MatchConfig.DEFAULT_WINS, "reset restores default wins")
	assert_eq(MatchConfig.arena_id, MatchConfig.DEFAULT_ARENA, "reset restores default arena")
	assert_true(MatchConfig.friendly_fire, "reset restores friendly fire on")
	assert_eq(MatchConfig.player_names.size(), 0, "reset clears staged names")
	assert_eq(MatchConfig.player_colors.size(), 0, "reset clears staged colours")


# ---------------------------------------------------------------------------
# Per-player name + colour (#132)
# ---------------------------------------------------------------------------

func _test_sanitize_name_falls_back_trims_and_truncates() -> void:
	assert_eq(MatchConfig.sanitize_name("", 0), "Player 1", "blank name falls back to default")
	assert_eq(MatchConfig.sanitize_name("   ", 2), "Player 3", "whitespace-only name falls back to default")
	assert_eq(MatchConfig.sanitize_name("  Ace  ", 0), "Ace", "surrounding whitespace is trimmed")
	var long := "X".repeat(MatchConfig.MAX_NAME_LENGTH + 10)
	assert_eq(MatchConfig.sanitize_name(long, 0).length(), MatchConfig.MAX_NAME_LENGTH, "over-long name truncates to the cap")
	var exact := "Y".repeat(MatchConfig.MAX_NAME_LENGTH)
	assert_eq(MatchConfig.sanitize_name(exact, 0), exact, "a name at the cap is kept verbatim")


func _test_default_player_name_is_one_indexed() -> void:
	assert_eq(MatchConfig.default_player_name(0), "Player 1", "slot 0 -> Player 1")
	assert_eq(MatchConfig.default_player_name(3), "Player 4", "slot 3 -> Player 4")


func _test_normalize_names_fills_to_count() -> void:
	var out := MatchConfig.normalize_names(["Ace"], 3)
	assert_eq(out.size(), 3, "normalises to exactly the player count")
	assert_eq(out[0], "Ace", "provided name kept")
	assert_eq(out[1], "Player 2", "missing slot filled with default")
	assert_eq(out[2], "Player 3", "missing slot filled with default")


func _test_normalize_colors_fills_and_clamps_to_count() -> void:
	var out := MatchConfig.normalize_colors([2, 999], 3)
	assert_eq(out.size(), 3, "normalises to exactly the player count")
	assert_eq(out[0], 2, "valid index kept")
	assert_eq(out[1], PlayerPalette.count() - 1, "out-of-range index clamped to last palette slot")
	assert_eq(out[2], PlayerPalette.default_index(2), "missing slot filled with the per-player default")


func _test_color_index_and_name_for_resolve_with_fallback() -> void:
	# Reading a short/empty array (an unconfigured match) falls back per-slot.
	assert_eq(MatchConfig.color_index_for([], 1), PlayerPalette.default_index(1), "empty colours -> default index")
	assert_eq(MatchConfig.color_index_for([5], 0), 5, "present index resolved")
	assert_eq(MatchConfig.color_index_for([999], 0), PlayerPalette.count() - 1, "present-but-wild index clamped")
	assert_eq(MatchConfig.name_for([], 0), "Player 1", "empty names -> default name")
	assert_eq(MatchConfig.name_for(["  Bo  "], 0), "Bo", "present name is sanitised")


func _test_configure_normalises_names_and_colours_to_player_count() -> void:
	# 9 players requested clamps to MAX_PLAYERS; names/colours normalise to match.
	MatchConfig.configure("ffa", 9, 5, "crossroads", true, ["A", "B"], [1])
	assert_eq(MatchConfig.player_names.size(), MatchDirector.MAX_PLAYERS, "names sized to the clamped player count")
	assert_eq(MatchConfig.player_colors.size(), MatchDirector.MAX_PLAYERS, "colours sized to the clamped player count")
	assert_eq(MatchConfig.player_names[0], "A", "provided name kept")
	assert_eq(MatchConfig.player_names[2], "Player 3", "unprovided slot defaulted")
	assert_eq(MatchConfig.player_colors[0], 1, "provided colour kept")
	assert_eq(MatchConfig.player_colors[1], PlayerPalette.default_index(1), "unprovided colour defaulted")


func _test_configure_defaults_identity_when_omitted() -> void:
	# The pre-#132 call shape (no names/colours) still yields a full, sane roster.
	MatchConfig.configure("ffa", 2, 3, "crossroads")
	assert_eq(MatchConfig.player_names, ["Player 1", "Player 2"], "names default per slot")
	assert_eq(MatchConfig.player_colors, [PlayerPalette.default_index(0), PlayerPalette.default_index(1)], "colours default per slot")


# ---------------------------------------------------------------------------
# Colour-derived teams (#134)
# ---------------------------------------------------------------------------

func _test_teams_from_colors_groups_matching_colours() -> void:
	# P1+P3 share colour 0, P2+P4 share colour 1 -> two 2-player teams keyed by the
	# palette index, so the team id can name the team by its colour (#132 A4).
	var teams := MatchConfig.teams_from_colors([0, 1, 0, 1], 4)
	assert_eq(teams, {0: 0, 1: 1, 2: 0, 3: 1}, "matching colours form shared teams (team id == colour index)")
	assert_eq(MatchConfig.distinct_team_count([0, 1, 0, 1], 4), 2, "two distinct colours -> two teams")


func _test_teams_from_colors_distinct_colours_are_solo_teams() -> void:
	# Distinct colours per player -> every player on their own team (the N-team / ~FFA
	# end of the 2..N range, #134 A2).
	var teams := MatchConfig.teams_from_colors([2, 5, 9], 3)
	assert_eq(teams, {0: 2, 1: 5, 2: 9}, "distinct colours -> distinct teams")
	assert_eq(MatchConfig.distinct_team_count([2, 5, 9], 3), 3, "three distinct colours -> three teams")


func _test_teams_from_colors_all_same_colour_is_one_team() -> void:
	# The degenerate input (host left every colour equal): a single team. Faithful to
	# the colour-extrapolation model; below the intended 2..N range, but tolerated by
	# GameManager rather than crashing (validation deferred — see PR).
	assert_eq(MatchConfig.teams_from_colors([3, 3], 2), {0: 3, 1: 3}, "all same colour -> one shared team")
	assert_eq(MatchConfig.distinct_team_count([3, 3], 2), 1, "one distinct colour -> one team")


func _test_teams_from_colors_handles_short_and_wild_arrays() -> void:
	# A short/empty array resolves each slot through the same per-slot fallback the
	# spawn path uses (default_index), and out-of-range indices clamp to a real colour.
	var teams := MatchConfig.teams_from_colors([], 2)
	assert_eq(teams, {0: PlayerPalette.default_index(0), 1: PlayerPalette.default_index(1)},
		"empty colours -> per-slot default teams")
	assert_eq(MatchConfig.teams_from_colors([999], 1), {0: PlayerPalette.count() - 1},
		"a wild index clamps to a real palette colour")


func _test_teams_from_colors_feeds_game_manager_team_tracking() -> void:
	# End-to-end: a colour-derived assignment plugs straight into the existing
	# GameManager pipeline and tracks wins per (colour) team.
	var teams := MatchConfig.teams_from_colors([0, 1, 0, 1], 4)  # P1,P3 = team 0; P2,P4 = team 1
	GameManager.setup_match("crossroads", 4, 2, teams, &"teams")
	assert_eq(GameManager.win_counts.size(), 2, "two colour teams -> two win counters")
	assert_eq(GameManager.team_for(2), 0, "P3 shares P1's colour team")
	assert_eq(GameManager.team_for(3), 1, "P4 shares P2's colour team")
	var over := GameManager.record_win(2)  # P3 wins for colour team 0
	assert_false(over, "1 of 2 wins does not end the match")
	assert_eq(GameManager.wins_for_player(0), 1, "P1 shares the colour-team win with P3")
	assert_eq(GameManager.wins_for_player(1), 0, "the other colour team is unaffected")

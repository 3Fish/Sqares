extends TestCase

## Unit tests for the match-setup screen's pure mode-specific-options logic
## (#133): `mode_groups_players` decides whether a game mode has team-mates, and
## therefore whether team-only options (e.g. friendly fire) are meaningful and the
## Mode Options submenu should be enabled.

const MatchSetup := preload("res://scripts/ui/match_setup.gd")
const FFAMode := preload("res://scripts/modes/game_mode.gd")
const TeamsModeScript := preload("res://scripts/modes/teams_mode.gd")
const NonMode := preload("res://scripts/effects/effect.gd")


func _test_ffa_does_not_group_players() -> void:
	# FFA assigns every player their own team -> no team-mates at any roster.
	assert_false(MatchSetup.mode_groups_players(FFAMode, 4), "FFA never groups players (4p)")
	assert_false(MatchSetup.mode_groups_players(FFAMode, 2), "FFA never groups players (2p)")


func _test_teams_groups_players_at_full_roster() -> void:
	# Teams (2 teams, round-robin) shares teams once there are more players than
	# teams. At the max roster used by the UI gate this is true.
	assert_true(MatchSetup.mode_groups_players(TeamsModeScript, 4), "4p Teams -> 2v2 (grouped)")
	assert_true(MatchSetup.mode_groups_players(TeamsModeScript, 3), "3p Teams -> 2v1 (grouped)")


func _test_teams_is_not_grouped_at_two_players() -> void:
	# A 2-player Teams match is 1v1: each player is alone on their team, so there
	# are no team-mates. The UI evaluates at MAX_PLAYERS so the toggle still shows
	# for Teams, but the helper itself reports the roster-accurate answer.
	assert_false(MatchSetup.mode_groups_players(TeamsModeScript, 2), "2p Teams -> 1v1 (no team-mates)")


func _test_null_and_non_mode_scripts_do_not_group() -> void:
	assert_false(MatchSetup.mode_groups_players(null, 4), "null script -> no teams")
	assert_false(MatchSetup.mode_groups_players(NonMode, 4), "non-GameMode script -> no teams")


# ---------------------------------------------------------------------------
# Per-player name + colour rows (#132)
# ---------------------------------------------------------------------------

func _test_active_player_count_maps_picker_index_to_count() -> void:
	# Player picker item index 0 -> 2 players, 1 -> 3, 2 -> 4 (MIN_PLAYERS-based).
	assert_eq(MatchSetup.active_player_count(0), MatchDirector.MIN_PLAYERS, "index 0 -> min players (2)")
	assert_eq(MatchSetup.active_player_count(1), 3, "index 1 -> 3 players")
	assert_eq(MatchSetup.active_player_count(2), MatchDirector.MAX_PLAYERS, "index 2 -> max players (4)")
	# A -1 "nothing selected" guards to the minimum rather than going below it.
	assert_eq(MatchSetup.active_player_count(-1), MatchDirector.MIN_PLAYERS, "no selection -> min players")


# ---------------------------------------------------------------------------
# Teams-from-colours preview (#134)
# ---------------------------------------------------------------------------

func _test_teams_preview_groups_players_by_colour() -> void:
	# P1+P3 on Sky (palette 0), P2+P4 on Orange (palette 1) -> two named groups, in
	# palette order, each listing its players.
	var text := MatchSetup.teams_preview_text([0, 1, 0, 1], 4)
	assert_true(text.contains("2 team(s)"), "reports two teams: %s" % text)
	assert_true(text.contains("%s (P1, P3)" % PlayerPalette.name_at(0)), "first colour group lists P1, P3: %s" % text)
	assert_true(text.contains("%s (P2, P4)" % PlayerPalette.name_at(1)), "second colour group lists P2, P4: %s" % text)


func _test_teams_preview_distinct_colours_report_solo_teams() -> void:
	var text := MatchSetup.teams_preview_text([0, 1, 2], 3)
	assert_true(text.contains("3 team(s)"), "three distinct colours -> three teams: %s" % text)


func _test_teams_preview_all_same_colour_is_one_team() -> void:
	var text := MatchSetup.teams_preview_text([4, 4], 2)
	assert_true(text.contains("1 team(s)"), "one shared colour -> one team: %s" % text)
	assert_true(text.contains("%s (P1, P2)" % PlayerPalette.name_at(4)), "both players in one group: %s" % text)


func _test_teams_preview_resolves_short_array_per_slot() -> void:
	# An empty colours array falls back to the per-slot default colours (distinct for
	# the first four slots), matching the spawn-path resolution.
	var text := MatchSetup.teams_preview_text([], 2)
	assert_true(text.contains("2 team(s)"), "empty colours -> per-slot default (distinct) teams: %s" % text)

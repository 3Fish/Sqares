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

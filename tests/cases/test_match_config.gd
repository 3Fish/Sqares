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

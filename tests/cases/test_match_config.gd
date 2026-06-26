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


# ---------------------------------------------------------------------------
# Saved-config serialisation (#135)
# ---------------------------------------------------------------------------

func _test_to_dict_serialises_template_fields_and_clamps_wins() -> void:
	var d := MatchConfig.to_dict("teams", 999, "highrise", false)
	assert_eq(d["version"], MatchConfig.CONFIG_VERSION, "schema version stamped")
	assert_eq(d["game_mode"], "teams", "mode serialised")
	assert_eq(d["wins_needed"], MatchConfig.MAX_WINS, "wins clamped on the way out")
	assert_eq(d["arena_id"], "highrise", "arena serialised")
	assert_false(d["friendly_fire"], "friendly fire serialised")
	# A saved config is a match *template*: the roster is deliberately excluded.
	assert_false(d.has("player_count"), "player count is not persisted (A2)")
	assert_false(d.has("player_names"), "per-player info is not persisted (A2)")


func _test_normalize_dict_resolves_ids_and_clamps() -> void:
	var modes := ["ffa", "teams"]
	var arenas := ["crossroads", "highrise"]
	var norm := MatchConfig.normalize_dict(
		{"game_mode": "teams", "wins_needed": 999, "arena_id": "highrise", "friendly_fire": false},
		modes, arenas)
	assert_eq(norm["game_mode"], "teams", "registered mode kept")
	assert_eq(norm["arena_id"], "highrise", "registered arena kept")
	assert_eq(norm["wins_needed"], MatchConfig.MAX_WINS, "wins clamped on load")
	assert_false(norm["friendly_fire"], "friendly fire coerced through")


func _test_normalize_dict_falls_back_on_stale_or_missing_ids() -> void:
	var modes := ["ffa", "teams"]
	var arenas := ["crossroads"]
	# A config naming an unregistered mode/arena falls back rather than erroring.
	var stale := MatchConfig.normalize_dict(
		{"game_mode": "gone", "arena_id": "deleted", "wins_needed": 3, "friendly_fire": true},
		modes, arenas)
	assert_eq(stale["game_mode"], MatchConfig.DEFAULT_MODE, "stale mode falls back to default")
	assert_eq(stale["arena_id"], "crossroads", "stale arena falls back to an available id")
	# Missing keys default rather than crash (older schema / hand-edited file).
	var empty := MatchConfig.normalize_dict({}, modes, arenas)
	assert_eq(empty["game_mode"], MatchConfig.DEFAULT_MODE, "missing mode -> default")
	assert_eq(empty["arena_id"], MatchConfig.DEFAULT_ARENA, "missing arena -> default")
	assert_eq(empty["wins_needed"], MatchConfig.DEFAULT_WINS, "missing wins -> default")
	assert_true(empty["friendly_fire"], "missing friendly fire -> on")


func _test_to_dict_round_trips_through_normalize() -> void:
	var modes := ["ffa", "teams"]
	var arenas := ["crossroads", "highrise"]
	var d := MatchConfig.to_dict("teams", 4, "highrise", false)
	var norm := MatchConfig.normalize_dict(d, modes, arenas)
	assert_eq(norm["game_mode"], "teams", "mode survives round trip")
	assert_eq(norm["wins_needed"], 4, "wins survive round trip")
	assert_eq(norm["arena_id"], "highrise", "arena survives round trip")
	assert_false(norm["friendly_fire"], "friendly fire survives round trip")


func _test_default_config_name_picks_lowest_free_slot() -> void:
	assert_eq(MatchConfig.default_config_name([]), "Config 1", "first default is Config 1")
	assert_eq(MatchConfig.default_config_name(["Config 1", "Config 2"]), "Config 3", "skips taken slots")
	assert_eq(MatchConfig.default_config_name(["Config 1", "Config 3"]), "Config 2", "fills the lowest gap")

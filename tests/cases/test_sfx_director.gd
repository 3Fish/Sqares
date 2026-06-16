extends TestCase

## Tests for the gameplay SFX director (#30).
##
## Like EffectEngine's tests, these drive the dispatch logic directly rather than
## through the autoload's signal wiring (the headless `--script` harness doesn't
## run autoload `_ready`). The `play()` seam and the lifecycle handlers are
## exercised against the live `SfxDirector` / `AudioManager` singletons, so they
## also confirm the AudioManager integration doesn't crash. Placeholder streams
## are registered so playback takes the real (non-warning) path.


func before_each() -> void:
	# Register a stream for every cue so play()/play_ui() hit the real playback
	# path instead of the "sound not registered" warning branch.
	for cue: String in SfxDirector.ALL_CUES:
		AudioManager.register_sound(cue, AudioStreamGenerator.new())
	for cue: String in SfxDirector.ALL_UI_CUES:
		AudioManager.register_sound(cue, AudioStreamGenerator.new())


func _test_cues_distinct_and_non_empty() -> void:
	var seen: Dictionary = {}
	for cue: String in SfxDirector.ALL_CUES:
		assert_false(cue.is_empty(), "cue name is non-empty")
		assert_false(seen.has(cue), "cue name '%s' is unique" % cue)
		seen[cue] = true
	assert_eq(SfxDirector.ALL_CUES.size(), seen.size(), "no duplicate cue names")


func _test_play_records_and_returns_cue() -> void:
	var played := SfxDirector.play(SfxDirector.SHOOT)
	assert_eq(played, SfxDirector.SHOOT, "play returns the requested cue")
	assert_eq(SfxDirector.last_cue(), SfxDirector.SHOOT, "play records the last cue")


func _test_play_empty_is_noop() -> void:
	SfxDirector.play(SfxDirector.HIT)  # establish a known prior cue
	var played := SfxDirector.play("")
	assert_eq(played, "", "empty cue is a no-op and returns empty")
	assert_eq(SfxDirector.last_cue(), SfxDirector.HIT, "empty cue leaves the last cue untouched")


func _test_play_unregistered_cue_is_safe() -> void:
	# Mirrors AudioManager's "unknown sound warns but doesn't crash" case; the
	# director must still record the request. Warning here is expected.
	var played := SfxDirector.play("never_registered_cue")
	assert_eq(played, "never_registered_cue", "unregistered cue is still requested")
	assert_eq(SfxDirector.last_cue(), "never_registered_cue", "unregistered cue is recorded")


func _test_round_started_handler_plays_start_stinger() -> void:
	SfxDirector._on_round_started(3)
	assert_eq(SfxDirector.last_cue(), SfxDirector.ROUND_START, "round_started → round-start stinger")


func _test_round_ended_handler_plays_end_stinger() -> void:
	SfxDirector._on_round_ended([1, 2])
	assert_eq(SfxDirector.last_cue(), SfxDirector.ROUND_END, "round_ended → round-end stinger")


func _test_match_ended_handler_plays_win_stinger() -> void:
	SfxDirector._on_match_ended(0)
	assert_eq(SfxDirector.last_cue(), SfxDirector.MATCH_WIN, "match_ended → match-win stinger")


# --- UI cues (#58) ---------------------------------------------------------

func _test_ui_cues_distinct_and_non_empty() -> void:
	var seen: Dictionary = {}
	for cue: String in SfxDirector.ALL_UI_CUES:
		assert_false(cue.is_empty(), "ui cue name is non-empty")
		assert_false(seen.has(cue), "ui cue name '%s' is unique" % cue)
		seen[cue] = true
	assert_eq(SfxDirector.ALL_UI_CUES.size(), seen.size(), "no duplicate ui cue names")


func _test_ui_and_sfx_cue_names_are_disjoint() -> void:
	# UI cues play on a different bus, so their names must not collide with the
	# SFX cues (a shared name would let one bus's volume affect the other's cue).
	for cue: String in SfxDirector.ALL_UI_CUES:
		assert_false(SfxDirector.ALL_CUES.has(cue), "ui cue '%s' is not also an SFX cue" % cue)


func _test_play_ui_records_and_returns_cue() -> void:
	var played := SfxDirector.play_ui(SfxDirector.CARD_DRAW)
	assert_eq(played, SfxDirector.CARD_DRAW, "play_ui returns the requested cue")
	assert_eq(SfxDirector.last_ui_cue(), SfxDirector.CARD_DRAW, "play_ui records the last ui cue")


func _test_play_ui_empty_is_noop() -> void:
	SfxDirector.play_ui(SfxDirector.CARD_PICK)  # establish a known prior ui cue
	var played := SfxDirector.play_ui("")
	assert_eq(played, "", "empty ui cue is a no-op and returns empty")
	assert_eq(SfxDirector.last_ui_cue(), SfxDirector.CARD_PICK, "empty ui cue leaves the last ui cue untouched")


func _test_play_and_play_ui_track_independently() -> void:
	# The SFX and UI "last cue" seams must not bleed into each other so each bus
	# can be introspected on its own.
	SfxDirector.play(SfxDirector.SHOOT)
	SfxDirector.play_ui(SfxDirector.CARD_DRAW)
	assert_eq(SfxDirector.last_cue(), SfxDirector.SHOOT, "play_ui does not disturb the last SFX cue")
	assert_eq(SfxDirector.last_ui_cue(), SfxDirector.CARD_DRAW, "play does not disturb the last UI cue")

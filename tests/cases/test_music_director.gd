extends TestCase

## Tests for the MusicDirector (#31): the GameManager.State -> music-track
## mapping and the apply path that crossfades via AudioManager.
##
## track_for_state is a pure static helper and is the substance of this issue;
## it is tested exhaustively and in isolation. apply_state is exercised through
## the live MusicDirector autoload singleton. Like EffectEngine's round_started
## wiring (#50) and the AudioManager bus setup (#47), the autoload's _ready —
## which connects GameManager.state_changed and builds AudioManager's music
## players — does not run under the headless `--script` harness; the decision
## logic is verified directly instead. The one mapped-state playback case mirrors
## test_audio_manager's accepted pattern (get_current_track reflects the request
## even though the players were not built headlessly).

const MENU := "menu"
const MATCH := "match"


func before_each() -> void:
	# Register placeholder streams so a mapped state has a registered track to
	# switch to (mods / a future assets PR supply the real streams).
	AudioManager.register_music(MENU, AudioStreamGenerator.new())
	AudioManager.register_music(MATCH, AudioStreamGenerator.new())


# --- track_for_state (pure mapping, the core of #31) -----------------------

func _test_menu_state_maps_to_menu_track() -> void:
	assert_eq(MusicDirector.track_for_state(GameManager.State.MENU),
		MusicDirector.TRACK_MENU, "MENU plays the menu track")


func _test_match_end_maps_to_menu_track() -> void:
	assert_eq(MusicDirector.track_for_state(GameManager.State.MATCH_END),
		MusicDirector.TRACK_MENU, "MATCH_END returns to the menu track")


func _test_in_match_states_map_to_match_track() -> void:
	var in_match := [
		GameManager.State.ROUND_INTRO,
		GameManager.State.ROUND,
		GameManager.State.ROUND_END,
		GameManager.State.CARD_SELECTION,
	]
	for state in in_match:
		assert_eq(MusicDirector.track_for_state(state),
			MusicDirector.TRACK_MATCH, "in-match state %d plays the match track" % state)


func _test_all_in_match_states_share_one_track() -> void:
	# All in-match states resolving to one track is what lets the menu->match
	# crossfade fire once rather than restarting on each round sub-state.
	var tracks := {}
	for state in [GameManager.State.ROUND_INTRO, GameManager.State.ROUND,
			GameManager.State.ROUND_END, GameManager.State.CARD_SELECTION]:
		tracks[MusicDirector.track_for_state(state)] = true
	assert_eq(tracks.size(), 1, "the in-match states map to a single shared track")


func _test_menu_and_match_tracks_differ() -> void:
	assert_true(MusicDirector.TRACK_MENU != MusicDirector.TRACK_MATCH,
		"menu and match use distinct tracks so a transition actually crossfades")


func _test_unknown_state_maps_to_no_track() -> void:
	# A state outside the enum (defensive) yields no track change.
	assert_eq(MusicDirector.track_for_state(-1), "", "unknown state changes no track")


# --- apply_state (drives AudioManager) -------------------------------------

func _test_apply_state_unmapped_leaves_track_untouched() -> void:
	# An unmapped state must short-circuit before touching AudioManager — this
	# branch is clean headlessly because it never calls play_music.
	var before := AudioManager.get_current_track()
	MusicDirector.apply_state(-1)
	assert_eq(AudioManager.get_current_track(), before,
		"an unmapped state does not change the current track")


func _test_apply_state_mapped_requests_the_track() -> void:
	# Mirrors test_audio_manager's playback case: play_music sets the current
	# track even though the headless harness did not build the music players
	# (the resulting out-of-bounds notice is the documented #47 limitation).
	MusicDirector.apply_state(GameManager.State.ROUND)
	assert_eq(AudioManager.get_current_track(), MusicDirector.TRACK_MATCH,
		"applying an in-match state requests the match track")

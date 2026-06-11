extends Node

## Drives background music across the game's lifecycle (#31). It watches the
## GameManager state machine and crossfades between a menu track and an in-match
## track on state transitions.
##
## The crossfade itself lives in AudioManager (#29); this director only decides
## *which* track should play for the current GameManager.State and hands it to
## AudioManager.play_music. Mirrors the EffectEngine autoload pattern: the signal
## hookup lives in _ready, but the decision logic is a pure static helper
## (track_for_state) and the apply path (apply_state) is public, so both can be
## unit-tested without standing up the autoload's signal wiring.
##
## Mods (and a future audio-assets PR) supply the actual streams via
## AudioManager.register_music using these track names. If a track is not
## registered, AudioManager.play_music warns and no-ops, so the director is safe
## to run before any music assets ship.

## Track name for menu-like states (registered via AudioManager.register_music).
const TRACK_MENU := "menu"
## Track name for in-match states.
const TRACK_MATCH := "match"

## Crossfade duration (seconds) applied to music state transitions.
const CROSSFADE := 1.0


func _ready() -> void:
	if not GameManager.state_changed.is_connected(_on_state_changed):
		GameManager.state_changed.connect(_on_state_changed)
	# The initial state never re-emits state_changed, so prime the first track
	# for whatever state the game launches in (MENU at boot).
	apply_state(GameManager.state)


## Maps a GameManager.State to the music track that should play in it. Menu and
## post-match states use the menu track; every in-match state shares the match
## track so the menu->match fade happens once on entry, not on each round
## sub-state. Returns an empty string for states that should not change the
## track. Pure and static so the mapping is unit-testable without the autoload.
static func track_for_state(state: int) -> String:
	if state == GameManager.State.MENU or state == GameManager.State.MATCH_END:
		return TRACK_MENU
	if state == GameManager.State.ROUND_INTRO \
			or state == GameManager.State.ROUND \
			or state == GameManager.State.ROUND_END \
			or state == GameManager.State.CARD_SELECTION:
		return TRACK_MATCH
	return ""


## Crossfades to the track that corresponds to `state`. A state with no mapped
## track leaves the music untouched; re-requesting the already-playing track is
## a no-op inside AudioManager, so the in-match sub-states do not restart it.
func apply_state(state: int) -> void:
	var track := track_for_state(state)
	if track.is_empty():
		return
	AudioManager.play_music(track, CROSSFADE)


func _on_state_changed(new_state: int) -> void:
	apply_state(new_state)

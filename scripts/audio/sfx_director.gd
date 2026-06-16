extends Node

## Triggers gameplay SFX off existing combat and round-flow signals (#30).
##
## Sits on top of the audio foundation (#29): combat code (`Weapon`, `Projectile`,
## `Player`) calls the thin `play()` seam at its natural trigger sites — mirroring
## how those same sites already call `EffectEngine.notify_*` — and this director
## also connects to `GameManager`'s round/match lifecycle signals to fire the
## round-start / round-end / match-win stingers without combat code knowing about
## audio. Cue names are the single source of truth here; `AudioManager` looks the
## stream up by name and, until a mod registers the actual asset (no audio ships
## yet, per #47), `play_sfx` warns and no-ops, so this is safe to run today.

## Cue names requested from AudioManager. Mods register matching streams via
## `AudioManager.register_sound(<name>, stream)`.
const SHOOT := "shoot"
const BOUNCE := "bounce"
## Played when a projectile deals damage — covers both the attacker's "hit"
## feedback and the victim's "take damage" cue (one physical event).
const HIT := "hit"
const DEATH := "death"
const ROUND_START := "round_start"
const ROUND_END := "round_end"
const MATCH_WIN := "match_win"

## Every cue this director can request. Lets mods enumerate what to author and
## backs the "all names distinct / non-empty" sanity test.
const ALL_CUES: Array[String] = [
	SHOOT, BOUNCE, HIT, DEATH, ROUND_START, ROUND_END, MATCH_WIN,
]

## UI cue names requested on the UI bus, not the SFX bus (#58, deferred from #30).
## The card-selection screen (#17) plays CARD_DRAW when a hand is presented and
## CARD_PICK when a player locks in a card. Like the SFX cues above, these are
## just names; until a mod registers the matching stream they warn-and-no-op.
const CARD_DRAW := "card_draw"
const CARD_PICK := "card_pick"

## Every UI cue this director can request. Lets mods enumerate what to author and
## backs the "all names distinct / non-empty" sanity test.
const ALL_UI_CUES: Array[String] = [CARD_DRAW, CARD_PICK]

## Name of the most recently requested SFX cue ("" if none / a no-op). Test seam,
## since the headless `--script` harness doesn't run autoload `_ready`/playback.
var _last_cue: String = ""

## Name of the most recently requested UI cue ("" if none / a no-op). Tracked
## separately from `_last_cue` so SFX and UI playback can be introspected
## independently.
var _last_ui_cue: String = ""


func _ready() -> void:
	# Round/match stingers come from global GameManager signals; combat cues are
	# pushed in by the combat nodes themselves (see Weapon/Projectile/Player).
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)
	if not GameManager.round_ended.is_connected(_on_round_ended):
		GameManager.round_ended.connect(_on_round_ended)
	if not GameManager.match_ended.is_connected(_on_match_ended):
		GameManager.match_ended.connect(_on_match_ended)


# ---------------------------------------------------------------------------
# Playback seam (called from combat code & the signal handlers below)
# ---------------------------------------------------------------------------

## Requests a one-shot SFX cue by name on the SFX bus. An empty name is a no-op.
## Returns the cue actually requested ("" when skipped) so callers and tests can
## introspect without standing up the audio playback pool.
func play(cue: String) -> String:
	if cue.is_empty():
		return ""
	_last_cue = cue
	AudioManager.play_sfx(cue)
	return cue


## The cue requested by the most recent `play()` ("" if none yet).
func last_cue() -> String:
	return _last_cue


## Requests a one-shot interface cue by name on the UI bus. Mirrors `play()` but
## routes to the UI bus so interface sounds mix independently of gameplay SFX. An
## empty name is a no-op. Returns the cue actually requested ("" when skipped).
func play_ui(cue: String) -> String:
	if cue.is_empty():
		return ""
	_last_ui_cue = cue
	AudioManager.play_ui(cue)
	return cue


## The cue requested by the most recent `play_ui()` ("" if none yet).
func last_ui_cue() -> String:
	return _last_ui_cue


# ---------------------------------------------------------------------------
# GameManager lifecycle → stingers
# ---------------------------------------------------------------------------

func _on_round_started(_round_num: int) -> void:
	play(ROUND_START)


func _on_round_ended(_loser_ids: Array) -> void:
	play(ROUND_END)


func _on_match_ended(_winner_id: int) -> void:
	play(MATCH_WIN)

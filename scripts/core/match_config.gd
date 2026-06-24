extends Node

## Pending match configuration handed from the match-setup screen to the match
## (#26). The setup screen writes the chosen game mode, player count, number of
## rounds, and arena here, then loads `scenes/match.tscn`; the next MatchDirector
## consumes it one-shot in `_ready` (overriding its scene `@export` defaults) and
## clears the pending flag — so a direct load of `match.tscn` (the arena editor's
## playtest #36, or a test) keeps the export defaults instead.
##
## This mirrors the one-shot hand-off `MatchDirector.pending_arena_id` already
## uses for the editor playtest; centralising the full config in one autoload
## gives the deferred online lobby (#66/#82), the editor playtest (#36), and
## save/load configs (deferred) a single seam to write. Normalisation is exposed
## as pure static helpers so the clamp/validate logic is unit-tested without
## booting a match.

## Supported range for the number of rounds a team must win to take the match.
const MIN_WINS := 1
const MAX_WINS := 9
const DEFAULT_WINS := 5

const DEFAULT_MODE := "ffa"
const DEFAULT_ARENA := "crossroads"

## Whether a setup screen has staged a configuration the next match should adopt.
var pending: bool = false

var game_mode: String = DEFAULT_MODE
var player_count: int = MatchDirector.MIN_PLAYERS
var wins_needed: int = DEFAULT_WINS
var arena_id: String = DEFAULT_ARENA
var friendly_fire: bool = true


## Stages a configuration for the next match and marks it pending. Numeric values
## are normalised to the supported ranges so the match always receives a sane,
## in-range selection regardless of what a caller passes.
func configure(p_mode: String, p_player_count: int, p_wins: int, p_arena: String,
		p_friendly_fire: bool = true) -> void:
	game_mode = p_mode
	player_count = MatchDirector.clamp_player_count(p_player_count)
	wins_needed = clamp_wins(p_wins)
	arena_id = p_arena
	friendly_fire = p_friendly_fire
	pending = true


## One-shot consume: returns true exactly once per staged configuration, clearing
## the pending flag so a later direct match load falls back to the `@export`
## defaults. The fields stay readable after consuming.
func consume() -> bool:
	var was_pending := pending
	pending = false
	return was_pending


## Clears any staged configuration back to defaults (also drops the pending flag).
func reset() -> void:
	pending = false
	game_mode = DEFAULT_MODE
	player_count = MatchDirector.MIN_PLAYERS
	wins_needed = DEFAULT_WINS
	arena_id = DEFAULT_ARENA
	friendly_fire = true


# ---------------------------------------------------------------------------
# Pure helpers (no autoload state — covered by tests/)
# ---------------------------------------------------------------------------

## Clamps a requested round target into the supported range.
static func clamp_wins(wins: int) -> int:
	return clampi(wins, MIN_WINS, MAX_WINS)


## Picks a valid choice from `available`: the request if present, else `fallback`
## when it is available, else the first available option, else the fallback
## verbatim (so an empty registry still yields a sane id). Used to keep a staged
## mode/arena id pointing at something actually registered.
static func resolve_choice(requested: String, available: Array, fallback: String) -> String:
	if requested in available:
		return requested
	if fallback in available:
		return fallback
	if not available.is_empty():
		return String(available[0])
	return fallback

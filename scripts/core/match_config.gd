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

## Schema version stamped into a saved match configuration (#135). Bumped if the
## persisted field set ever changes incompatibly; `normalize_dict` reads defaults
## for any missing key so older files keep loading.
const CONFIG_VERSION := 1

## Max length of a per-player name chosen in setup (#132). Blank names fall back
## to the default "Player N"; longer entries are truncated.
const MAX_NAME_LENGTH := 30

## Whether a setup screen has staged a configuration the next match should adopt.
var pending: bool = false

var game_mode: String = DEFAULT_MODE
var player_count: int = MatchDirector.MIN_PLAYERS
var wins_needed: int = DEFAULT_WINS
var arena_id: String = DEFAULT_ARENA
var friendly_fire: bool = true
## Smaller-team card-draw handicap toggle (#147), a mode-specific option like
## `friendly_fire`. Off by default (historical behaviour); persisted in saved
## templates (#135).
var team_handicap: bool = false

## Per-player identity chosen in setup (#132), one entry per active player slot.
## `player_names` are sanitised strings; `player_colors` are palette indices into
## `PlayerPalette`. Local-only here — replicating a peer's chosen name/colour rides
## the online lobby work (#66/#82). MatchDirector applies the colour to each
## spawned player's character and records the name on it.
var player_names: Array = []
var player_colors: Array = []


## Stages a configuration for the next match and marks it pending. Numeric values
## are normalised to the supported ranges so the match always receives a sane,
## in-range selection regardless of what a caller passes.
func configure(p_mode: String, p_player_count: int, p_wins: int, p_arena: String,
		p_friendly_fire: bool = true, p_names: Array = [], p_colors: Array = [],
		p_team_handicap: bool = false) -> void:
	game_mode = p_mode
	player_count = MatchDirector.clamp_player_count(p_player_count)
	wins_needed = clamp_wins(p_wins)
	arena_id = p_arena
	friendly_fire = p_friendly_fire
	team_handicap = p_team_handicap
	# Normalise per-player identity to exactly `player_count` sane entries (#132) so
	# the match always reads a full, in-range name/colour list regardless of what
	# the setup screen passed.
	player_names = normalize_names(p_names, player_count)
	player_colors = normalize_colors(p_colors, player_count)
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
	team_handicap = false
	player_names = []
	player_colors = []


# ---------------------------------------------------------------------------
# Pure helpers (no autoload state — covered by tests/)
# ---------------------------------------------------------------------------

## Clamps a requested round target into the supported range.
static func clamp_wins(wins: int) -> int:
	return clampi(wins, MIN_WINS, MAX_WINS)


## The default display name for a player slot when none was chosen / a blank was
## entered (the maintainer disallows empty names, #132 A4).
static func default_player_name(player_id: int) -> String:
	return "Player %d" % (player_id + 1)


## Sanitises a chosen name (#132 A4): trims surrounding whitespace, falls back to
## the default when blank, and truncates to `MAX_NAME_LENGTH`.
static func sanitize_name(raw: String, player_id: int) -> String:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty():
		return default_player_name(player_id)
	if trimmed.length() > MAX_NAME_LENGTH:
		return trimmed.substr(0, MAX_NAME_LENGTH)
	return trimmed


## Builds exactly `count` sanitised names, filling missing slots with defaults.
static func normalize_names(raw_names: Array, count: int) -> Array:
	var out: Array = []
	for i in count:
		var raw := String(raw_names[i]) if i < raw_names.size() else ""
		out.append(sanitize_name(raw, i))
	return out


## Builds exactly `count` valid palette indices, filling/repairing missing or
## out-of-range slots with the per-player default colour.
static func normalize_colors(raw_colors: Array, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(color_index_for(raw_colors, i))
	return out


## Resolves the name for a slot from a (possibly short/empty) names array, falling
## back to the default. Used at spawn so an unconfigured match (editor playtest,
## client, tests) still gets sane names.
static func name_for(names: Array, player_id: int) -> String:
	if player_id >= 0 and player_id < names.size():
		return sanitize_name(String(names[player_id]), player_id)
	return default_player_name(player_id)


## Resolves the palette index for a slot from a (possibly short/empty) colours
## array, clamping to a real colour and falling back to the per-player default.
static func color_index_for(colors: Array, player_id: int) -> int:
	if player_id >= 0 and player_id < colors.size():
		return PlayerPalette.clamp_index(int(colors[player_id]))
	return PlayerPalette.default_index(player_id)


# ---------------------------------------------------------------------------
# Colour-derived teams (#134)
# ---------------------------------------------------------------------------
# In Teams mode the teams are *extrapolated from the per-player colours* chosen in
# setup (#134 A3 / #132 A4): players who pick the same palette colour share a team,
# so the host composes teams simply by assigning matching colours. The team id IS
# the palette colour index, which lets the win announcement name a team by its
# colour ("Team Babyblue wins!"). The distinct-team count naturally lands in
# [1, player_count]; the maintainer's intended range is 2..N (#134 A2), reached by
# assigning at least two distinct colours. FFA ignores this entirely — there the
# same colour does not mean the same team (#134 A4).

## Builds the `player_id -> team_id` assignment for a colour-derived Teams match
## (#134). Each active slot resolves through `color_index_for`, the same per-slot
## fallback the spawn path uses, so a short/empty colours array still yields a full
## map. The team id is the palette colour index, so two players on the same colour
## map to the same team. Pure so the derivation is unit-tested without a match.
static func teams_from_colors(colors: Array, player_count: int) -> Dictionary:
	var teams: Dictionary = {}
	for i in player_count:
		teams[i] = color_index_for(colors, i)
	return teams


## Number of distinct teams a colour-derived Teams match would produce: the count
## of distinct palette indices among the active players (#134). Pure so the setup
## preview can read it without booting a match.
static func distinct_team_count(colors: Array, player_count: int) -> int:
	var seen: Dictionary = {}
	for i in player_count:
		seen[color_index_for(colors, i)] = true
	return seen.size()


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


# ---------------------------------------------------------------------------
# Saved match configurations (#135) — serialisation helpers
# ---------------------------------------------------------------------------
# A saved config is a reusable match *template*: the game mode plus the general
# (rounds, arena) and mode-specific (friendly fire) options. Player count and
# per-player info are deliberately NOT persisted (maintainer A2) — a template is
# applied on top of whatever roster the host has selected. Mode-specific options
# beyond friendly fire (e.g. team assignment, #134) extend this dict additively.
# Pure helpers so the schema + load-time normalisation are unit-tested without a
# scene; the on-disk JSON side lives in `MatchConfigStore` (mirroring ArenaStore).

## Serialises the persisted match-template fields into a plain dictionary (#135).
## Wins are clamped on the way out so a saved file is always in-range.
static func to_dict(p_mode: String, p_wins: int, p_arena: String, p_friendly_fire: bool,
		p_team_handicap: bool = false) -> Dictionary:
	return {
		"version": CONFIG_VERSION,
		"game_mode": p_mode,
		"wins_needed": clamp_wins(p_wins),
		"arena_id": p_arena,
		"friendly_fire": p_friendly_fire,
		"team_handicap": p_team_handicap,
	}


## Reads a (possibly stale or hand-edited) saved dict back into a normalised set
## of selections (#135 A2). Mode and arena are resolved against the currently
## registered ids — a config naming an id no longer registered falls back to a
## sane choice rather than erroring (reusing `resolve_choice`, the same rule
## `configure` applies to a staged selection) — wins are clamped, and friendly
## fire is coerced to bool. Any missing key falls back to its default, so a config
## written by an older schema still loads.
static func normalize_dict(data: Dictionary, available_modes: Array, available_arenas: Array) -> Dictionary:
	return {
		"game_mode": resolve_choice(String(data.get("game_mode", DEFAULT_MODE)), available_modes, DEFAULT_MODE),
		"wins_needed": clamp_wins(int(data.get("wins_needed", DEFAULT_WINS))),
		"arena_id": resolve_choice(String(data.get("arena_id", DEFAULT_ARENA)), available_arenas, DEFAULT_ARENA),
		"friendly_fire": bool(data.get("friendly_fire", true)),
		"team_handicap": bool(data.get("team_handicap", false)),
	}


## An auto-generated default config name (#135 A3): the lowest `Config N` (N >= 1)
## not already in `existing`, so repeated saves never silently collide. Pure so
## the numbering is unit-tested without touching disk.
static func default_config_name(existing: Array) -> String:
	var n := 1
	while ("Config %d" % n) in existing:
		n += 1
	return "Config %d" % n

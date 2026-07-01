class_name CardPickMode

## Pure, scene-free helpers for the between-rounds card-pick presentation modes
## (#169). The card phase can be played SEQUENTIALLY ("One By One" — losing
## players pick in turn while the others watch) or in PARALLEL ("All At Once" —
## every loser picks simultaneously, today's flow). The mode is a global Options
## setting (stored by `GameplaySettings`); an AUTO setting resolves to a concrete
## mode from the player count via the maintainer's adaptive rule. An optional pick
## timeout auto-picks a random card for any player who runs out of time.
##
## All of the decision logic lives here as pure functions so it is unit-tested
## without a live card screen; `CardSelectionUI` drives the actual panels, input,
## status indicator, and timeout from these helpers.

## Global-setting values. AUTO defers to the adaptive default; SEQUENTIAL and
## PARALLEL force a mode. Stored as strings so the setting round-trips cleanly
## through `ConfigFile` (`GameplaySettings`) and reads clearly in the Options UI.
const AUTO := "auto"
const SEQUENTIAL := "sequential"
const PARALLEL := "parallel"

const ALL_SETTINGS: Array[String] = [AUTO, SEQUENTIAL, PARALLEL]

## Adaptive-default cutoff (maintainer, #169 Q1): a match of this many players or
## fewer defaults to SEQUENTIAL; a larger match defaults to PARALLEL. Local play
## caps at 4, so AUTO is sequential for every local match today; the parallel
## branch is reached by the larger online rosters (up to 16) the maintainer
## flagged as future work.
const ADAPTIVE_THRESHOLD := 4

## Default pick-timeout duration (seconds) applied when the match-setup timeout
## option is enabled (#169). A fixed value gated by an on/off toggle; making the
## length itself configurable at match creation is a deferred follow-up (the
## maintainer specified only that a timeout exists and auto-picks a random card,
## not the exact length).
const DEFAULT_TIMEOUT := 20.0


## Coerces a stored/raw setting string to a known value, falling back to AUTO for
## anything unrecognised (an older or hand-edited settings file, say).
static func normalize_setting(raw: String) -> String:
	return raw if raw in ALL_SETTINGS else AUTO


## The adaptive default mode for a match of `player_count` players (maintainer's
## rule): SEQUENTIAL at or below the threshold, PARALLEL above it.
static func default_mode_for(player_count: int) -> String:
	return SEQUENTIAL if player_count <= ADAPTIVE_THRESHOLD else PARALLEL


## Resolves a global setting to a concrete mode (SEQUENTIAL or PARALLEL) for a
## given player count: AUTO consults the adaptive default, an explicit setting is
## honoured as-is. Unknown settings normalise to AUTO first.
static func resolve_mode(setting: String, player_count: int) -> String:
	var s := normalize_setting(setting)
	if s == AUTO:
		return default_mode_for(player_count)
	return s


## A pick order for SEQUENTIAL mode: a fresh random permutation of `slots` each
## round (maintainer, #169 Q4), drawn from the seeded `rng` so a host and its
## clients agree. `slots` is sorted first so the permutation is a pure function of
## the rng stream regardless of the caller's key order. Returns a new array; the
## input is untouched. Mirrors `RNGService.shuffled` (Fisher-Yates over the synced
## stream) rather than `Array.shuffle`, which draws from the unsynced global RNG.
static func pick_order(slots: Array, rng: RandomNumberGenerator) -> Array:
	var ordered := slots.duplicate()
	ordered.sort()
	for i in range(ordered.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ordered[i]
		ordered[i] = ordered[j]
		ordered[j] = tmp
	return ordered


## The next slot in `order` that has not yet confirmed, or -1 when every slot in
## the order has confirmed (the phase is done). `confirmed` may be a Dictionary
## used as a set or an Array of slots. Drives the SEQUENTIAL hand-off from one
## picker to the next.
static func next_active(order: Array, confirmed) -> int:
	for slot in order:
		if not _contains(confirmed, slot):
			return int(slot)
	return -1


## The slots still waiting on a pick, in the given order — the "picked / still
## choosing" status indicator's source (#169): every `expected` slot not present
## in `confirmed`. Pure so the status read-out is unit-tested without the screen.
static func pending_slots(expected: Array, confirmed) -> Array:
	var out: Array = []
	for slot in expected:
		if not _contains(confirmed, slot):
			out.append(int(slot))
	return out


## A random index into a hand of `hand_size` cards for a timeout auto-pick
## (maintainer, #169 Q3), drawn from the seeded `rng`. Returns -1 for an empty
## hand (nothing to pick).
static func auto_pick_index(hand_size: int, rng: RandomNumberGenerator) -> int:
	if hand_size <= 0:
		return -1
	return rng.randi_range(0, hand_size - 1)


## True once `elapsed` seconds reaches the timeout `limit`. A non-positive limit
## means "no timeout" — the phase waits indefinitely (today's behaviour), so this
## always returns false.
static func timed_out(elapsed: float, limit: float) -> bool:
	if limit <= 0.0:
		return false
	return elapsed >= limit


# ---------------------------------------------------------------------------

## Membership test that accepts either a Dictionary-as-set or an Array for the
## `confirmed` collection, so callers can pass whichever they already hold.
static func _contains(collection, value) -> bool:
	if collection is Dictionary:
		return collection.has(value)
	return value in collection

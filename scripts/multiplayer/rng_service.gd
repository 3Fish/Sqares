extends Node

## Deterministic, seed-synced random number service (#24).
##
## A single shared RNG whose seed is agreed at match start and derived per round,
## so every client that consumes it draws the identical sequence. This is the
## randomness source all sync-sensitive gameplay — card draws (#17) and effect
## rolls (#20) — MUST use instead of a private `RandomNumberGenerator`, otherwise
## online play (#13) would desync.
##
## Seed transport is the only part that needs the netcode foundation (#23): the
## host calls `seed_match()` (which returns the chosen seed) and broadcasts it;
## clients adopt it with `apply_seed(seed)`. Today, in local couch play, the seed
## is simply set on the one machine. The draw API below is identical either way,
## so wiring the RPC later requires no change here.
##
## Per round, `seed_round(n)` re-derives the stream from the master seed + round
## number, so each round is independently reproducible even if earlier rounds
## drew a different number of values. This autoload connects to
## `GameManager.round_started` in `_ready` to do that automatically.
##
## The decision-bearing logic (`mix_seed`, `weighted_pick_index`) is pure/static
## so it can be unit-tested without standing up the autoload, matching the
## project's static-helper testing convention.

## 0 is reserved to mean "no master seed chosen yet".
const UNSEEDED: int = 0

## Master seed agreed for the whole match. 0 until `seed_match`/`apply_seed`.
var master_seed: int = UNSEEDED
## Round whose stream is currently loaded (0 = the pre-round/master stream).
var current_round: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# Round start re-derives the per-round stream from the master seed. Exposed
	# directly as `seed_round` too, so the derivation can be unit-tested without
	# the autoload's signal path (the headless harness does not run `_ready`).
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)


# ---------------------------------------------------------------------------
# Seeding
# ---------------------------------------------------------------------------

## Chooses (or adopts) the master seed for a match and resets the stream to it.
## Pass an explicit non-zero `new_seed` to reproduce a known match; pass 0 (the
## default) to pick a fresh entropy-based seed. Returns the seed actually used,
## so the host can broadcast it to clients.
func seed_match(new_seed: int = UNSEEDED) -> int:
	if new_seed == UNSEEDED:
		var entropy := RandomNumberGenerator.new()
		entropy.randomize()
		new_seed = entropy.randi()
		if new_seed == UNSEEDED:
			new_seed = 1  # keep 0 reserved for "unseeded"
	master_seed = new_seed
	current_round = 0
	_rng.seed = master_seed
	return master_seed


## Adopts a seed received from the host (client side of the sync seam). A 0 here
## would mean the host had no seed; we still funnel through `seed_match` so the
## stream is reset consistently.
func apply_seed(new_seed: int) -> void:
	seed_match(new_seed)


## Re-derives the random stream for round `round_number` from the master seed.
## If no master seed has been chosen yet, one is lazily picked so local play
## still varies between matches.
func seed_round(round_number: int) -> void:
	if master_seed == UNSEEDED:
		seed_match()
	current_round = round_number
	_rng.seed = mix_seed(master_seed, round_number)


func _on_round_started(round_number: int) -> void:
	seed_round(round_number)


# ---------------------------------------------------------------------------
# Draw API (consumed by card draws #17 and effects #20)
# ---------------------------------------------------------------------------

## The live seeded generator, for draw helpers that take a plain
## RandomNumberGenerator (e.g. `CardDraw.weighted_draw`). Consuming values
## through it advances the synced stream like any other draw.
func generator() -> RandomNumberGenerator:
	return _rng


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi() -> int:
	return _rng.randi()


## Inclusive integer in `[from, to]`.
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Returns a deterministically shuffled copy of `array` (the input is untouched).
## Uses the seeded stream rather than `Array.shuffle`, which draws from Godot's
## unsynced global RNG.
func shuffled(array: Array) -> Array:
	var result := array.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result


## Picks one element of `items`, where `weights[i]` is the relative weight of
## `items[i]`. Non-positive weights are skipped. Returns null if `items` is empty
## or no positive weight exists.
func weighted_pick(items: Array, weights: Array) -> Variant:
	if items.is_empty():
		return null
	var index := weighted_pick_index(weights, _rng.randf())
	if index < 0 or index >= items.size():
		return null
	return items[index]


## Draws up to `count` distinct elements from `items` (without replacement) in
## deterministic order. The natural primitive for the losers' card draw (#17).
func draw(items: Array, count: int) -> Array:
	var pool := items.duplicate()
	var result: Array = []
	var n: int = mini(count, pool.size())
	for _i in n:
		var index := _rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested directly)
# ---------------------------------------------------------------------------

## Derives a reproducible stream seed from a master seed and a salt (e.g. the
## round number). Uses Godot's PCG RNG so every peer on the same engine build
## derives the identical value; distinct salts give well-separated seeds.
static func mix_seed(base_seed: int, salt: int) -> int:
	var r := RandomNumberGenerator.new()
	# Knuth multiplicative constant (0x9E3779B1) spreads adjacent salts apart
	# before they collapse into the seed.
	r.seed = base_seed ^ (salt * 2654435761)
	return r.randi()


## Maps a roll in `[0, 1)` onto an index of `weights` by cumulative weight.
## Non-positive weights are skipped. Returns -1 when there is no positive weight
## (empty array or all weights <= 0). Pure, so the weighted-draw decision can be
## tested with explicit rolls.
static func weighted_pick_index(weights: Array, roll: float) -> int:
	var total: float = 0.0
	for w in weights:
		if w > 0.0:
			total += w
	if total <= 0.0:
		return -1
	var threshold: float = roll * total
	var cumulative: float = 0.0
	var last_positive: int = -1
	for i in weights.size():
		var w: float = weights[i]
		if w <= 0.0:
			continue
		last_positive = i
		cumulative += w
		if threshold < cumulative:
			return i
	# Float rounding can leave `threshold` fractionally at/over `total`; fall
	# back to the last positively-weighted bucket.
	return last_positive

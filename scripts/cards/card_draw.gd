class_name CardDraw extends RefCounted

## Pure, seeded weighted-random card drawing (#17).
##
## Between rounds, each losing player is shown N cards drawn from the registry
## and picks one. This class holds the *draw* logic only — no scene-tree or UI
## dependency — so it is fully unit-testable with a seeded
## `RandomNumberGenerator`.
##
## The RNG is always passed in rather than owned, which is the seam for the
## synced-RNG service (#24): local play hands in a plain `RandomNumberGenerator`
## (see `MatchDirector`), and online-fair draws will later hand in `RNGService`'s
## generator instead — the draw maths are identical either way.

## Number of cards offered to a losing player per round, unless overridden.
const DEFAULT_DRAW_COUNT := 3


## Draws up to `count` distinct cards from `cards`, weighted by each card's
## `get_weight()` (the per-card override or its rarity default), without
## replacement. Higher-weight (more common) cards are favoured.
##
## Returns fewer than `count` cards when the pool is smaller. Returns an empty
## array for a non-positive `count`, an empty pool, or a null `rng`. The input
## array is never mutated. Given the same seeded `rng` and pool, the result is
## deterministic — the property online sync relies on.
static func weighted_draw(cards: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	if count <= 0 or cards.is_empty() or rng == null:
		return result
	var pool: Array = cards.duplicate()
	var draws: int = mini(count, pool.size())
	for _i in draws:
		var index := _pick_index(pool, rng)
		result.append(pool[index])
		pool.remove_at(index)
	return result


## Picks a single index into `pool` weighted by card weight. Falls back to a
## uniform pick when every remaining card has zero (or negative) weight, so a
## degenerate weighting still yields a valid card rather than nothing.
static func _pick_index(pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for card in pool:
		total += _weight_of(card)
	if total <= 0.0:
		return rng.randi_range(0, pool.size() - 1)
	var roll := rng.randf() * total
	var acc := 0.0
	for i in pool.size():
		acc += _weight_of(pool[i])
		if roll < acc:
			return i
	# Floating-point guard: roll == total falls through to the last card.
	return pool.size() - 1


## Effective draw weight of a card, clamped to be non-negative. Tolerant of
## plain stubs used in tests: anything exposing `get_weight()` is honoured,
## otherwise the card contributes a neutral weight of 1.0.
static func _weight_of(card) -> float:
	if card == null:
		return 0.0
	if card.has_method("get_weight"):
		return maxf(0.0, float(card.get_weight()))
	return 1.0

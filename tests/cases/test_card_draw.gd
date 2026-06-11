extends TestCase

## Unit tests for CardDraw — the pure, seeded weighted-random card draw (#17).
## A seeded RandomNumberGenerator makes every case deterministic and non-flaky.


func _make_card(id: String, rarity: Card.Rarity, weight: float = -1.0) -> Card:
	var c := Card.new()
	c.id = id
	c.rarity = rarity
	c.weight = weight
	return c


func _seeded(seed_value: int = 12345) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out


func _test_draws_requested_count() -> void:
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON),
		_make_card("b", Card.Rarity.COMMON),
		_make_card("c", Card.Rarity.COMMON),
		_make_card("d", Card.Rarity.COMMON),
	]
	var hand := CardDraw.weighted_draw(pool, 3, _seeded())
	assert_eq(hand.size(), 3, "draws exactly the requested count")


func _test_no_duplicates_within_a_hand() -> void:
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON),
		_make_card("b", Card.Rarity.COMMON),
		_make_card("c", Card.Rarity.COMMON),
		_make_card("d", Card.Rarity.COMMON),
		_make_card("e", Card.Rarity.COMMON),
	]
	var hand := CardDraw.weighted_draw(pool, 4, _seeded())
	var seen := {}
	for c in hand:
		seen[c.id] = true
	assert_eq(seen.size(), hand.size(), "a hand contains no duplicate cards (drawn without replacement)")


func _test_deterministic_for_equal_seeds() -> void:
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON),
		_make_card("b", Card.Rarity.UNCOMMON),
		_make_card("c", Card.Rarity.RARE),
		_make_card("d", Card.Rarity.EPIC),
	]
	var first := CardDraw.weighted_draw(pool, 3, _seeded(999))
	var second := CardDraw.weighted_draw(pool, 3, _seeded(999))
	assert_eq(_ids(first), _ids(second), "same seed + pool yields the same hand (sync-safe)")


func _test_favours_higher_weight_cards() -> void:
	# One very common card vs one very rare card. Over many single-draws with a
	# fixed seed, the common card is picked far more often. Deterministic, so the
	# inequality is stable run-to-run.
	var pool: Array = [
		_make_card("common", Card.Rarity.COMMON),     # weight 100
		_make_card("legendary", Card.Rarity.LEGENDARY), # weight 3
	]
	var rng := _seeded(7)
	var common := 0
	var legendary := 0
	for _i in 400:
		var hand := CardDraw.weighted_draw(pool, 1, rng)
		if hand[0].id == "common":
			common += 1
		else:
			legendary += 1
	assert_true(common > legendary, "higher-weight card is drawn more often (%d vs %d)" % [common, legendary])
	assert_true(legendary > 0, "rare card is still reachable, not impossible")


func _test_per_card_weight_override_beats_rarity() -> void:
	# A COMMON card with weight 0 should essentially never win against a normal one.
	var pool: Array = [
		_make_card("muted", Card.Rarity.COMMON, 0.0),
		_make_card("normal", Card.Rarity.COMMON),
	]
	var rng := _seeded(3)
	var muted := 0
	for _i in 100:
		var hand := CardDraw.weighted_draw(pool, 1, rng)
		if hand[0].id == "muted":
			muted += 1
	assert_eq(muted, 0, "a zero-weight card is never picked while a weighted alternative exists")


func _test_count_clamped_to_pool_size() -> void:
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON),
		_make_card("b", Card.Rarity.COMMON),
	]
	var hand := CardDraw.weighted_draw(pool, 5, _seeded())
	assert_eq(hand.size(), 2, "asking for more than the pool returns the whole pool")
	assert_eq(_ids(hand).size(), 2, "and still without duplicates")


func _test_degenerate_inputs_return_empty() -> void:
	var pool: Array = [_make_card("a", Card.Rarity.COMMON)]
	assert_eq(CardDraw.weighted_draw(pool, 0, _seeded()).size(), 0, "count 0 -> empty")
	assert_eq(CardDraw.weighted_draw(pool, -2, _seeded()).size(), 0, "negative count -> empty")
	assert_eq(CardDraw.weighted_draw([], 3, _seeded()).size(), 0, "empty pool -> empty")
	assert_eq(CardDraw.weighted_draw(pool, 3, null).size(), 0, "null rng -> empty")


func _test_all_zero_weight_pool_still_draws() -> void:
	# Falls back to a uniform pick rather than returning nothing.
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON, 0.0),
		_make_card("b", Card.Rarity.COMMON, 0.0),
	]
	var hand := CardDraw.weighted_draw(pool, 2, _seeded())
	assert_eq(hand.size(), 2, "an all-zero-weight pool still yields cards (uniform fallback)")


func _test_does_not_mutate_input_pool() -> void:
	var pool: Array = [
		_make_card("a", Card.Rarity.COMMON),
		_make_card("b", Card.Rarity.COMMON),
		_make_card("c", Card.Rarity.COMMON),
	]
	var before := pool.size()
	CardDraw.weighted_draw(pool, 2, _seeded())
	assert_eq(pool.size(), before, "the source pool is left untouched")

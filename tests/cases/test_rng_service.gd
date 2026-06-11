extends TestCase

## Coverage for the deterministic / synced RNG service (#24).
##
## The seeding + draw API is verified through fresh, isolated instances (each
## stands in for a network peer) so determinism is proven without depending on
## the autoload's `_ready` signal wiring — the same pattern other suites use for
## logic that would otherwise need the live scene tree. One case also exercises
## the live `RNGService` autoload singleton. The decision-bearing static helpers
## (`mix_seed`, `weighted_pick_index`) are tested directly.


## A standalone service instance acting as one "peer". It is never added to the
## tree, so `_ready` (and its GameManager signal hookup) does not run. Returned
## untyped so the instance's own methods resolve via dynamic dispatch (the script
## has no `class_name`).
func _make():
	return load("res://scripts/multiplayer/rng_service.gd").new()


# --- Seeding & cross-peer determinism --------------------------------------

func _test_autoload_singleton_is_seedable() -> void:
	var used: int = RNGService.seed_match(999)
	assert_eq(used, 999, "seed_match returns the explicit seed")
	assert_eq(RNGService.master_seed, 999, "master seed is stored on the singleton")

	var first: Array = []
	for _i in 5:
		first.append(RNGService.randi())
	RNGService.seed_match(999)
	var second: Array = []
	for _i in 5:
		second.append(RNGService.randi())
	assert_eq(first, second, "re-seeding the singleton reproduces the stream")


func _test_two_peers_same_seed_agree() -> void:
	var p1 = _make()
	var p2 = _make()
	p1.seed_match(42)
	p2.seed_match(42)
	var s1: Array = []
	var s2: Array = []
	for _i in 10:
		s1.append(p1.randi())
		s2.append(p2.randi())
	assert_eq(s1, s2, "two peers with the same seed draw identical sequences")


func _test_random_seed_is_reproducible_via_returned_value() -> void:
	var host = _make()
	var picked: int = host.seed_match()  # 0 default → entropy-based pick
	assert_true(picked != RNGService.UNSEEDED, "a freshly chosen master seed is non-zero")

	var client = _make()
	client.apply_seed(picked)
	var h: Array = []
	var c: Array = []
	for _i in 8:
		h.append(host.randf())
		c.append(client.randf())
	assert_eq(h, c, "a client that adopts the host's broadcast seed matches the host")


func _test_seed_round_is_reproducible_and_round_specific() -> void:
	var a = _make()
	var b = _make()
	a.seed_match(7)
	b.seed_match(7)
	a.seed_round(3)
	b.seed_round(3)
	var ra: Array = []
	var rb: Array = []
	for _i in 6:
		ra.append(a.randi())
		rb.append(b.randi())
	assert_eq(ra, rb, "same master + round derives an identical stream across peers")
	assert_eq(a.current_round, 3, "current_round tracks the active round")
	assert_true(RNGService.mix_seed(7, 3) != RNGService.mix_seed(7, 4),
		"different round numbers derive different stream seeds")


func _test_seed_round_lazily_picks_master() -> void:
	var s = _make()
	assert_eq(s.master_seed, RNGService.UNSEEDED, "a fresh service starts unseeded")
	s.seed_round(1)
	assert_true(s.master_seed != RNGService.UNSEEDED,
		"seed_round picks a master seed when none has been set")


# --- Pure static helpers ----------------------------------------------------

func _test_mix_seed_is_deterministic() -> void:
	assert_eq(RNGService.mix_seed(123, 5), RNGService.mix_seed(123, 5),
		"mix_seed is a pure function of its inputs")
	assert_true(RNGService.mix_seed(123, 5) != RNGService.mix_seed(124, 5),
		"a different master seed derives a different stream seed")
	assert_true(RNGService.mix_seed(123, 5) != RNGService.mix_seed(123, 6),
		"a different salt derives a different stream seed")


func _test_weighted_pick_index_boundaries() -> void:
	assert_eq(RNGService.weighted_pick_index([], 0.5), -1, "empty weights → -1")
	assert_eq(RNGService.weighted_pick_index([0.0, 0.0], 0.5), -1, "no positive weight → -1")
	assert_eq(RNGService.weighted_pick_index([1.0, 1.0, 1.0], 0.0), 0, "roll 0 picks the first bucket")
	assert_eq(RNGService.weighted_pick_index([1.0, 1.0, 1.0], 0.999), 2, "roll near 1 picks the last bucket")
	# weights [1, 3] → total 4: roll 0.1 → threshold 0.4 (bucket 0); roll 0.5 → 2.0 (bucket 1).
	assert_eq(RNGService.weighted_pick_index([1.0, 3.0], 0.1), 0, "low roll lands in the small bucket")
	assert_eq(RNGService.weighted_pick_index([1.0, 3.0], 0.5), 1, "high roll lands in the large bucket")


func _test_weighted_pick_index_skips_zero_buckets() -> void:
	var weights := [0.0, 2.0, 0.0, 3.0]
	for r in [0.0, 0.25, 0.5, 0.75, 0.999]:
		var idx: int = RNGService.weighted_pick_index(weights, r)
		assert_true(idx == 1 or idx == 3,
			"zero-weight buckets are never selected (roll=%s → %d)" % [r, idx])


# --- Draw API ---------------------------------------------------------------

func _test_weighted_pick_respects_weights_and_emptiness() -> void:
	var s = _make()
	s.seed_match(1)
	assert_eq(s.weighted_pick([], []), null, "empty items → null")
	assert_eq(s.weighted_pick(["a", "b"], [0.0, 0.0]), null, "all-zero weights → null")
	for _i in 20:
		assert_eq(s.weighted_pick(["a", "b"], [1.0, 0.0]), "a",
			"a zero-weight item is never drawn")


func _test_shuffled_is_permutation_and_deterministic() -> void:
	var source := [1, 2, 3, 4, 5, 6]
	var a = _make()
	a.seed_match(2024)
	var out: Array = a.shuffled(source)
	assert_eq(source, [1, 2, 3, 4, 5, 6], "shuffled does not mutate the input")
	assert_eq(out.size(), source.size(), "shuffle preserves length")
	var sorted_out := out.duplicate()
	sorted_out.sort()
	assert_eq(sorted_out, [1, 2, 3, 4, 5, 6], "shuffle is a permutation of the input")
	var b = _make()
	b.seed_match(2024)
	assert_eq(b.shuffled(source), out, "same seed → identical shuffle across peers")


func _test_draw_distinct_clamped_deterministic() -> void:
	var pool := ["a", "b", "c", "d"]
	var a = _make()
	a.seed_match(55)
	var hand: Array = a.draw(pool, 3)
	assert_eq(hand.size(), 3, "draws the requested count")
	assert_eq(pool.size(), 4, "draw does not mutate the source pool")

	var seen := {}
	var distinct := true
	for x in hand:
		if seen.has(x):
			distinct = false
		seen[x] = true
	assert_true(distinct, "drawn elements are distinct (drawn without replacement)")

	var b = _make()
	b.seed_match(55)
	assert_eq(b.draw(pool, 99).size(), 4, "count is clamped to the pool size")
	assert_eq(b.draw(pool, 0), [], "drawing zero yields an empty hand")

	var c = _make()
	c.seed_match(55)
	assert_eq(c.draw(pool, 3), hand, "same seed → identical draw across peers")

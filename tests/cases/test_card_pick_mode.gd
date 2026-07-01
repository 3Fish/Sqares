extends TestCase

## Tests for the pure card-pick-mode helpers (#169) that drive the between-rounds
## presentation: the adaptive default + setting resolution, the sequential pick
## order + hand-off, the timeout gate, and the auto-pick index. All are scene-free
## static functions, so they are asserted directly (the UI wiring that consumes
## them is covered in test_card_selection.gd / boot-verified).


func _seeded_rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _test_normalize_setting_coerces_unknown_to_auto() -> void:
	assert_eq(CardPickMode.normalize_setting(CardPickMode.SEQUENTIAL), CardPickMode.SEQUENTIAL, "known value passes through")
	assert_eq(CardPickMode.normalize_setting(CardPickMode.PARALLEL), CardPickMode.PARALLEL, "known value passes through")
	assert_eq(CardPickMode.normalize_setting(CardPickMode.AUTO), CardPickMode.AUTO, "auto passes through")
	assert_eq(CardPickMode.normalize_setting("nonsense"), CardPickMode.AUTO, "unknown -> auto")
	assert_eq(CardPickMode.normalize_setting(""), CardPickMode.AUTO, "empty -> auto")


func _test_default_mode_for_uses_adaptive_threshold() -> void:
	# Maintainer #169 Q1: players <= 4 -> sequential, > 4 -> parallel.
	assert_eq(CardPickMode.default_mode_for(2), CardPickMode.SEQUENTIAL, "2 players -> sequential")
	assert_eq(CardPickMode.default_mode_for(4), CardPickMode.SEQUENTIAL, "4 players (boundary) -> sequential")
	assert_eq(CardPickMode.default_mode_for(5), CardPickMode.PARALLEL, "5 players -> parallel")
	assert_eq(CardPickMode.default_mode_for(16), CardPickMode.PARALLEL, "16 players -> parallel")


func _test_resolve_mode_auto_vs_explicit() -> void:
	# AUTO consults the adaptive default by player count...
	assert_eq(CardPickMode.resolve_mode(CardPickMode.AUTO, 4), CardPickMode.SEQUENTIAL, "auto @4 -> sequential")
	assert_eq(CardPickMode.resolve_mode(CardPickMode.AUTO, 8), CardPickMode.PARALLEL, "auto @8 -> parallel")
	# ...while an explicit setting is honoured regardless of the count.
	assert_eq(CardPickMode.resolve_mode(CardPickMode.PARALLEL, 2), CardPickMode.PARALLEL, "explicit parallel @2 stays parallel")
	assert_eq(CardPickMode.resolve_mode(CardPickMode.SEQUENTIAL, 16), CardPickMode.SEQUENTIAL, "explicit sequential @16 stays sequential")
	# An unrecognised setting normalises to auto first.
	assert_eq(CardPickMode.resolve_mode("bogus", 4), CardPickMode.SEQUENTIAL, "unknown setting -> auto -> adaptive")


func _test_pick_order_is_a_permutation_of_sorted_slots() -> void:
	var order := CardPickMode.pick_order([3, 1, 2, 0], _seeded_rng(42))
	assert_eq(order.size(), 4, "order covers every slot")
	var sorted_copy := order.duplicate()
	sorted_copy.sort()
	assert_eq(sorted_copy, [0, 1, 2, 3], "order is a permutation of the input slots")


func _test_pick_order_is_deterministic_for_a_seed() -> void:
	# Same seed -> same order (host/clients agree over the synced stream, #169 Q4).
	var a := CardPickMode.pick_order([0, 1, 2, 3], _seeded_rng(7))
	var b := CardPickMode.pick_order([0, 1, 2, 3], _seeded_rng(7))
	assert_eq(a, b, "identical seeds produce identical orders")


func _test_pick_order_leaves_input_untouched() -> void:
	var slots := [2, 0, 1]
	CardPickMode.pick_order(slots, _seeded_rng(1))
	assert_eq(slots, [2, 0, 1], "the caller's array is not mutated")


func _test_next_active_walks_the_order() -> void:
	var order := [2, 0, 1]
	assert_eq(CardPickMode.next_active(order, {}), 2, "nothing confirmed -> first in order")
	assert_eq(CardPickMode.next_active(order, {2: true}), 0, "first confirmed -> next in order")
	assert_eq(CardPickMode.next_active(order, {2: true, 0: true}), 1, "two confirmed -> last in order")
	assert_eq(CardPickMode.next_active(order, {2: true, 0: true, 1: true}), -1, "all confirmed -> -1 (done)")


func _test_next_active_accepts_an_array_confirmed_set() -> void:
	# `confirmed` may be an Array as well as a Dictionary-as-set.
	assert_eq(CardPickMode.next_active([0, 1, 2], [0]), 1, "array set: skips confirmed slot 0")
	assert_eq(CardPickMode.next_active([0, 1, 2], [0, 1, 2]), -1, "array set: all confirmed -> -1")


func _test_pending_slots_reports_the_unconfirmed_in_order() -> void:
	assert_eq(CardPickMode.pending_slots([0, 1, 2], {1: true}), [0, 2], "pending = expected minus confirmed, in order")
	assert_eq(CardPickMode.pending_slots([0, 1], {0: true, 1: true}), [], "all confirmed -> none pending")
	assert_eq(CardPickMode.pending_slots([], {}), [], "no expected slots -> none pending")


func _test_auto_pick_index_stays_in_range() -> void:
	assert_eq(CardPickMode.auto_pick_index(0, _seeded_rng(1)), -1, "empty hand -> -1")
	var idx := CardPickMode.auto_pick_index(5, _seeded_rng(99))
	assert_true(idx >= 0 and idx < 5, "index falls within the hand")
	assert_eq(CardPickMode.auto_pick_index(1, _seeded_rng(3)), 0, "single-card hand -> only index")


func _test_timed_out_gate() -> void:
	assert_false(CardPickMode.timed_out(100.0, 0.0), "limit 0 disables the timeout")
	assert_false(CardPickMode.timed_out(100.0, -1.0), "negative limit disables the timeout")
	assert_false(CardPickMode.timed_out(4.9, 5.0), "under the limit -> not timed out")
	assert_true(CardPickMode.timed_out(5.0, 5.0), "reaching the limit -> timed out")
	assert_true(CardPickMode.timed_out(6.0, 5.0), "past the limit -> timed out")

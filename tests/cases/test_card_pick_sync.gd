extends TestCase

## Unit tests for the pure online card-selection helpers (#82): hand wire-shaping,
## the all-picked gate, and pick validation. The RPC fan-out and the per-peer pick
## UI are boot-verified (the single-process headless harness can't stand up a
## second peer), matching the netcode static-helper convention used elsewhere.


func _make_card(id_str: String) -> Card:
	return Card.create({"id": id_str, "display_name": id_str, "description": "d", "rarity": "common"})


func _test_serialize_hands_flattens_to_ids() -> void:
	var hands := {
		0: [_make_card("a"), _make_card("b")],
		2: [_make_card("c")],
	}
	var wire := CardPickSync.serialize_hands(hands)
	assert_eq(wire.size(), 2, "one entry per loser slot")
	assert_eq((wire[0] as Array), ["a", "b"], "slot 0 hand flattened to ids in order")
	assert_eq((wire[2] as Array), ["c"], "slot 2 hand flattened to ids")


func _test_serialize_hands_drops_idless_and_handles_empty() -> void:
	var idless := Card.new()  # empty id — not lookup-able on the receiver
	var wire := CardPickSync.serialize_hands({1: [idless, _make_card("ok")], 3: []})
	assert_eq((wire[1] as Array), ["ok"], "card without an id is dropped from the wire")
	assert_true((wire[3] as Array).is_empty(), "an empty hand serialises to an empty list")


func _test_all_picked_gate() -> void:
	assert_false(CardPickSync.all_picked([0, 1], {0: null}), "missing a loser's pick is not complete")
	assert_true(CardPickSync.all_picked([0, 1], {0: null, 1: _make_card("a")}), "every loser in → complete")
	assert_true(CardPickSync.all_picked([], {}), "no losers → trivially complete")
	assert_true(CardPickSync.all_picked([2], {2: null}), "a null (empty-hand) pick still counts as in")


func _test_is_valid_pick() -> void:
	var wire := {0: ["a", "b"], 1: []}
	assert_true(CardPickSync.is_valid_pick(0, "a", wire), "a card from the slot's own hand is valid")
	assert_true(CardPickSync.is_valid_pick(0, "b", wire), "any card from the hand is valid")
	assert_false(CardPickSync.is_valid_pick(0, "c", wire), "a card never dealt to the slot is rejected")
	assert_false(CardPickSync.is_valid_pick(9, "a", wire), "a slot with no hand is rejected")
	assert_true(CardPickSync.is_valid_pick(1, "", wire), "empty hand accepts the empty (no-pick) id")
	assert_false(CardPickSync.is_valid_pick(1, "a", wire), "empty hand rejects any real card id")


func _seeded_rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _test_auto_pick_unpicked_skips_already_picked() -> void:
	var wire := {0: ["a", "b"], 1: ["c", "d"]}
	# Slot 0 already chose; only the un-picked slot 1 should be auto-resolved.
	var auto := CardPickSync.auto_pick_unpicked([0, 1], {0: null}, wire, _seeded_rng(1))
	assert_false(auto.has(0), "a slot that already picked is left untouched")
	assert_true(auto.has(1), "an un-picked loser is auto-resolved")
	assert_true((wire[1] as Array).has(auto[1]), "the auto-pick is a card from that slot's own hand")


func _test_auto_pick_unpicked_empty_and_missing_hands() -> void:
	var wire := {0: [], 2: ["z"]}
	# Slot 0 was dealt an empty hand; slot 5 has no hand at all. Both resolve to the
	# "" no-pick id, matching is_valid_pick's empty-hand contract.
	var auto := CardPickSync.auto_pick_unpicked([0, 5], {}, wire, _seeded_rng(3))
	assert_eq(String(auto[0]), "", "an empty hand auto-resolves to the no-pick id")
	assert_eq(String(auto[5]), "", "a slot with no broadcast hand auto-resolves to the no-pick id")


func _test_auto_pick_unpicked_is_deterministic() -> void:
	var wire := {1: ["a", "b", "c", "d"]}
	# Same seeded stream -> same auto-pick, so a host resolution is reproducible.
	var a := CardPickSync.auto_pick_unpicked([1], {}, wire, _seeded_rng(9))
	var b := CardPickSync.auto_pick_unpicked([1], {}, wire, _seeded_rng(9))
	assert_eq(String(a[1]), String(b[1]), "the same seed yields the same auto-pick")


func _test_auto_pick_unpicked_resolves_every_open_loser() -> void:
	var wire := {0: ["a"], 1: ["b", "c"], 2: []}
	# With no prior picks, every listed loser gets an entry so the phase can settle.
	var auto := CardPickSync.auto_pick_unpicked([0, 1, 2], {}, wire, _seeded_rng(5))
	assert_eq(auto.size(), 3, "every un-picked loser is resolved")
	assert_eq(String(auto[0]), "a", "a single-card hand resolves to that card")
	assert_true((wire[1] as Array).has(auto[1]), "a multi-card hand resolves to one of its cards")
	assert_eq(String(auto[2]), "", "an empty hand resolves to the no-pick id")

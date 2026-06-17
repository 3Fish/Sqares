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

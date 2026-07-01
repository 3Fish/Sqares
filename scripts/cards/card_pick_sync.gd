class_name CardPickSync

## Pure, scene-free helpers for the online card-selection flow (#82, from #27).
##
## Between rounds the host draws each losing player's hand from the synced
## RNGService stream (#24), then broadcasts those hands to every peer so each
## remote loser can pick on its own screen and replicate the choice back. These
## helpers cover the wire-shaping and gating maths so they can be unit-tested
## without a live multiplayer peer; the RPC fan-out itself is boot-verified
## (the single-process headless harness can't stand up a second peer — the same
## limitation noted throughout the netcode deferred-questions issues).


## Flattens a drawn-hands map ({ slot:int -> Array[Card] }) into a wire-friendly
## map ({ slot:int -> Array[String card_id] }) for the host->client broadcast.
## Cards without an id are dropped (they can't be looked back up on the receiver).
static func serialize_hands(hands: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in hands:
		var ids: Array = []
		var hand = hands[slot]
		if hand is Array:
			for card in hand:
				if card != null and String(card.id) != "":
					ids.append(String(card.id))
		out[int(slot)] = ids
	return out


## True once every expected loser slot has a pick recorded. Picks may map a slot
## to a Card or to null (a loser whose hand was empty); either counts as "in".
static func all_picked(expected_slots: Array, picks: Dictionary) -> bool:
	for slot in expected_slots:
		if not picks.has(int(slot)):
			return false
	return true


## Validates a replicated pick against the broadcast hands: the slot must be one
## of the drawn hands, and the chosen card_id must belong to that slot's hand. An
## empty hand accepts only an empty card_id (the "nothing to pick" case). Used by
## the host to reject a peer that picks a card it was never dealt.
static func is_valid_pick(slot: int, card_id: String, serialized_hands: Dictionary) -> bool:
	if not serialized_hands.has(slot):
		return false
	var hand: Array = serialized_hands[slot]
	if hand.is_empty():
		return card_id == ""
	return hand.has(card_id)


## Host-side timeout resolution (#171, from #169). When the pick window elapses,
## the host auto-picks for every loser in `loser_ids` that hasn't chosen yet,
## drawing a random card from that slot's broadcast hand via the synced `rng`
## (the same seeded stream that dealt the hands, so the choice is deterministic
## and host-authoritative). Returns a { slot:int -> card_id:String } map of just
## the auto-picks to apply: a slot already present in `picks` is left untouched,
## and a slot with an empty (or missing) hand resolves to "" — the "nothing to
## pick" case, matching `is_valid_pick`. Pure so the host-enforced timeout is
## unit-tested without a live peer.
static func auto_pick_unpicked(loser_ids: Array, picks: Dictionary, serialized_hands: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	for slot in loser_ids:
		var s := int(slot)
		if picks.has(s):
			continue
		var hand: Array = serialized_hands[s] if serialized_hands.has(s) else []
		var idx := CardPickMode.auto_pick_index(hand.size(), rng)
		out[s] = String(hand[idx]) if idx >= 0 else ""
	return out

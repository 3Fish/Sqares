extends TestCase

## Unit tests for the mid-match reconnect / slot-hold model (#151): holding a
## dropped peer's slot for a grace window, reclaiming it by stable token, and
## expiring a lapsed grace into a "counted dead" slot that stays reserved.
##
## Pure host-authoritative roster bookkeeping on a fresh instance, matching the
## static-helper convention used by `test_network_roster`; the live RPC token
## transport (broadcast_roster / request_slot_reclaim) is boot/integration
## verified rather than unit-tested.

const NetworkManagerScript = preload("res://scripts/multiplayer/network_manager.gd")

var nm: Node


func before_each() -> void:
	nm = NetworkManagerScript.new()


func after_each() -> void:
	if nm:
		nm.free()
		nm = null


# ---------------------------------------------------------------------------
# Static helpers (no instance state)
# ---------------------------------------------------------------------------

func _test_is_hold_expired_thresholds() -> void:
	# A zero deadline means "not held / grace consumed" and never reads expired.
	assert_false(NetworkManagerScript.is_hold_expired(99999, 0), "deadline 0 -> never expired")
	assert_false(NetworkManagerScript.is_hold_expired(500, 1000), "now before deadline -> not expired")
	assert_true(NetworkManagerScript.is_hold_expired(1000, 1000), "now == deadline -> expired")
	assert_true(NetworkManagerScript.is_hold_expired(1500, 1000), "now past deadline -> expired")


func _test_reconnect_token_is_deterministic_and_distinct() -> void:
	assert_eq(NetworkManagerScript.reconnect_token(1, 7),
		NetworkManagerScript.reconnect_token(1, 7), "same slot+salt -> same token")
	assert_true(NetworkManagerScript.reconnect_token(1, 7)
		!= NetworkManagerScript.reconnect_token(1, 8), "a fresh salt yields a different token")
	assert_true(NetworkManagerScript.reconnect_token(0, 1)
		!= NetworkManagerScript.reconnect_token(1, 1), "different slots yield different tokens")


# ---------------------------------------------------------------------------
# Registration mints a stable token
# ---------------------------------------------------------------------------

func _test_register_assigns_token_and_connected() -> void:
	var slot: int = nm.register_peer(1)
	assert_eq(slot, 0, "host slot 0")
	assert_true(nm.token_of(1) != "", "registration mints a reconnect token")
	assert_false(nm.is_slot_held(0), "a connected slot is not held")
	assert_eq(nm.held_slots().size(), 0, "no held slots after a plain registration")


func _test_distinct_peers_get_distinct_tokens() -> void:
	nm.register_peer(1)
	nm.register_peer(2)
	assert_true(nm.token_of(1) != nm.token_of(2), "each peer gets its own token")


# ---------------------------------------------------------------------------
# Holding a slot
# ---------------------------------------------------------------------------

func _test_hold_reserves_slot_without_freeing_it() -> void:
	nm.register_peer(1)  # slot 0
	nm.register_peer(2)  # slot 1
	nm.hold_peer(2, 1000)
	assert_true(nm.is_slot_held(1), "slot 1 is held after its peer drops")
	assert_eq(nm.held_slots(), [1] as Array[int], "held_slots lists the reserved slot")
	# The held slot stays in use, so a fresh joiner can't be handed it.
	assert_true(nm.slots_in_use().has(1), "held slot is still in use")
	assert_eq(nm.register_peer(3), 2, "a new peer gets the next free slot, not the held one")


func _test_hold_unknown_peer_is_noop() -> void:
	nm.register_peer(1)
	nm.hold_peer(999, 1000)  # never registered
	assert_eq(nm.held_slots().size(), 0, "holding an unknown peer changes nothing")


# ---------------------------------------------------------------------------
# Reclaiming a held slot by token
# ---------------------------------------------------------------------------

func _test_reconnect_restores_original_slot_under_new_peer_id() -> void:
	nm.register_peer(1)         # slot 0
	var slot: int = nm.register_peer(2)  # slot 1
	var token: String = nm.token_of(2)
	nm.hold_peer(2, 1000)
	# Peer 2 reconnects with a brand-new ENet id (42) and presents its token.
	var restored: int = nm.register_peer(42, token)
	assert_eq(restored, slot, "reclaim restores the original slot")
	assert_eq(nm.slot_of(42), 1, "the new peer id now owns the restored slot")
	assert_eq(nm.slot_of(2), -1, "the old peer id is gone")
	assert_false(nm.is_slot_held(1), "the reclaimed slot is no longer held")
	assert_eq(nm.token_of(42), token, "the stable token carries across the reconnect")


func _test_reconnect_drops_speculative_fresh_slot() -> void:
	# On raw connect (before presenting a token) a reconnecting peer is given a
	# throwaway fresh slot; reclaiming with the token must drop that stray entry.
	nm.register_peer(1)              # slot 0
	var token: String = nm.token_of(1)
	nm.hold_peer(1, 1000)            # slot 0 held
	var fresh: int = nm.register_peer(2)  # speculative: peer 2 grabs slot 1
	assert_eq(fresh, 1, "speculative connect takes the next free slot")
	var restored: int = nm.register_peer(2, token)  # same peer now reclaims slot 0
	assert_eq(restored, 0, "reclaim restores the held slot 0")
	assert_eq(nm.peer_count(), 1, "the throwaway slot-1 entry was dropped")
	assert_eq(nm.slot_of(2), 0, "peer 2 ends up on the reclaimed slot")


func _test_register_with_unknown_token_falls_back_to_fresh() -> void:
	nm.register_peer(1)  # slot 0
	var slot: int = nm.register_peer(2, "no-such-token")
	assert_eq(slot, 1, "an unmatched token registers a fresh slot")


# ---------------------------------------------------------------------------
# Expiring a lapsed grace
# ---------------------------------------------------------------------------

func _test_expire_emits_once_and_keeps_slot_reserved() -> void:
	nm.register_peer(1)  # slot 0
	nm.register_peer(2)  # slot 1
	nm.hold_peer(2, 1000)  # deadline 1000 + RECONNECT_WINDOW_MS
	var fired: Array[int] = []
	nm.slot_hold_expired.connect(func(s): fired.append(s))

	# Before the deadline: nothing expires.
	var early: Array = nm.expire_due_holds(1000 + NetworkManagerScript.RECONNECT_WINDOW_MS - 1)
	assert_eq(early.size(), 0, "no expiry before the deadline")
	assert_eq(fired.size(), 0, "no signal before the deadline")

	# At/after the deadline: the slot expires exactly once.
	var due: Array = nm.expire_due_holds(1000 + NetworkManagerScript.RECONNECT_WINDOW_MS)
	assert_eq(due, [1] as Array[int], "the lapsed slot is returned")
	assert_eq(fired, [1] as Array[int], "slot_hold_expired fires once for the slot")

	# Grace consumed: a later tick does not re-fire, and the slot stays reserved
	# so the peer can still rejoin from the next round.
	var again: Array = nm.expire_due_holds(9_000_000)
	assert_eq(again.size(), 0, "grace fires only once")
	assert_true(nm.is_slot_held(1), "the slot stays reserved after the grace lapses")


func _test_reclaim_after_grace_still_restores_slot() -> void:
	nm.register_peer(1)  # slot 0
	nm.register_peer(2)  # slot 1
	var token: String = nm.token_of(2)
	nm.hold_peer(2, 1000)
	nm.expire_due_holds(9_000_000)  # counted dead this round, slot still reserved
	var restored: int = nm.register_peer(7, token)
	assert_eq(restored, 1, "a peer can rejoin its slot even after being counted dead")
	assert_false(nm.is_slot_held(1), "the slot is live again after the late reconnect")


# ---------------------------------------------------------------------------
# Releasing holds / match flag
# ---------------------------------------------------------------------------

func _test_release_holds_frees_only_held_entries() -> void:
	nm.register_peer(1)  # slot 0 (stays connected)
	nm.register_peer(2)  # slot 1
	nm.hold_peer(2, 1000)
	nm.release_holds()
	assert_eq(nm.peer_count(), 1, "the held entry is dropped")
	assert_eq(nm.slot_of(1), 0, "the connected peer is untouched")
	assert_eq(nm.register_peer(3), 1, "the freed slot is available again")


func _test_set_match_in_progress_off_releases_holds() -> void:
	nm.register_peer(1)
	nm.register_peer(2)
	nm.hold_peer(2, 1000)
	nm.set_match_in_progress(true)
	assert_true(nm.match_in_progress, "flag is set")
	nm.set_match_in_progress(false)
	assert_false(nm.match_in_progress, "flag is cleared")
	assert_eq(nm.held_slots().size(), 0, "ending the match releases held slots")


# ---------------------------------------------------------------------------
# Slot identity is the anchor for team + win_counts (live autoload)
# ---------------------------------------------------------------------------

func _test_reclaim_preserves_team_and_win_counts() -> void:
	# Reconnect restores the *slot*; team and win_counts already key off the slot
	# (GameManager.team_of / win_counts), so restoring the slot restores them with
	# no extra bookkeeping. Verified against the live GameManager autoload.
	GameManager.setup_match("crossroads", 2, 5, {0: 0, 1: 1}, &"teams")
	GameManager.record_win(1)  # slot 1's team banks a round win
	assert_eq(GameManager.wins_for_player(1), 1, "slot 1 has a win banked")

	nm.register_peer(1)  # slot 0
	nm.register_peer(2)  # slot 1
	var token: String = nm.token_of(2)
	nm.hold_peer(2, 1000)
	var restored: int = nm.register_peer(99, token)
	assert_eq(restored, 1, "the reconnecting peer is back on slot 1")
	# Because the slot is restored, the win that keys off slot 1's team is intact.
	assert_eq(GameManager.wins_for_player(restored), 1, "win_counts survive the reconnect via the slot")

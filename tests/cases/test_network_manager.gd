extends TestCase

## Unit tests for NetworkManager's pure lobby/slot logic (#23).
##
## The connection lifecycle (host_game / join_game) needs the live multiplayer
## peer, so it's verified by a headless boot smoke test rather than here; the
## roster bookkeeping it drives is plain dictionary logic and is tested directly
## on a fresh instance, matching the static-helper convention.

const NetworkManagerScript = preload("res://scripts/multiplayer/network_manager.gd")

var nm


func before_each() -> void:
	nm = NetworkManagerScript.new()


func after_each() -> void:
	if nm:
		nm.free()
		nm = null


func _test_next_player_slot() -> void:
	# Pure static helper: lowest free 0-based slot in [0, MAX_PLAYERS).
	assert_eq(NetworkManagerScript.next_player_slot([]), 0, "empty -> slot 0")
	assert_eq(NetworkManagerScript.next_player_slot([0]), 1, "0 taken -> 1")
	assert_eq(NetworkManagerScript.next_player_slot([0, 1, 2]), 3, "0/1/2 taken -> 3")
	# Reuses the lowest gap, not just the next-highest.
	assert_eq(NetworkManagerScript.next_player_slot([0, 2, 3]), 1, "gap at 1 -> 1")
	# Full lobby (MAX_PLAYERS == 4) -> -1.
	assert_eq(NetworkManagerScript.next_player_slot([0, 1, 2, 3]), -1, "full -> -1")


func _test_default_role_is_offline() -> void:
	assert_true(nm.role == NetworkManagerScript.Role.OFFLINE, "starts OFFLINE")
	assert_false(nm.is_host(), "not host by default")
	assert_false(nm.is_client(), "not client by default")
	assert_false(nm.is_networked(), "not networked by default")
	assert_eq(nm.peer_count(), 0, "empty roster by default")


func _test_register_peer_assigns_sequential_slots() -> void:
	assert_eq(nm.register_peer(1), 0, "first peer -> slot 0")
	assert_eq(nm.register_peer(20), 1, "second peer -> slot 1")
	assert_eq(nm.register_peer(33), 2, "third peer -> slot 2")
	assert_eq(nm.register_peer(47), 3, "fourth peer -> slot 3")
	assert_eq(nm.peer_count(), 4, "four peers registered")
	assert_eq(nm.slot_of(20), 1, "slot_of returns assigned slot")
	assert_eq(nm.slot_of(999), -1, "unknown peer -> -1")


func _test_register_peer_rejects_when_full() -> void:
	nm.register_peer(1)
	nm.register_peer(2)
	nm.register_peer(3)
	nm.register_peer(4)
	assert_eq(nm.register_peer(5), -1, "fifth peer rejected (lobby full)")
	assert_eq(nm.peer_count(), 4, "rejected peer not stored")


func _test_register_peer_is_idempotent() -> void:
	assert_eq(nm.register_peer(7), 0, "first register -> slot 0")
	assert_eq(nm.register_peer(7), 0, "re-register same peer -> same slot")
	assert_eq(nm.peer_count(), 1, "no duplicate roster entry")


func _test_unregister_frees_lowest_slot_for_reuse() -> void:
	nm.register_peer(1)   # slot 0
	nm.register_peer(2)   # slot 1
	nm.register_peer(3)   # slot 2
	nm.unregister_peer(2) # frees slot 1
	assert_eq(nm.peer_count(), 2, "peer removed from roster")
	assert_eq(nm.slot_of(2), -1, "removed peer no longer mapped")
	# A new peer reclaims the lowest free slot (1), not slot 3.
	assert_eq(nm.register_peer(9), 1, "new peer reuses freed slot 1")


func _test_unregister_unknown_peer_is_noop() -> void:
	nm.register_peer(1)
	nm.unregister_peer(404)  # never registered
	assert_eq(nm.peer_count(), 1, "roster unchanged for unknown peer")


func _test_slots_in_use() -> void:
	nm.register_peer(1)
	nm.register_peer(2)
	# `nm` is an untyped instance, so the call's return type can't be inferred;
	# annotate explicitly rather than using `:=`.
	var taken: Array = nm.slots_in_use()
	assert_eq(taken.size(), 2, "two slots in use")
	assert_true(taken.has(0) and taken.has(1), "slots 0 and 1 reported")


func _test_reset_lobby() -> void:
	nm.register_peer(1)
	nm.register_peer(2)
	nm.reset_lobby()
	assert_eq(nm.peer_count(), 0, "roster cleared")
	assert_true(nm.role == NetworkManagerScript.Role.OFFLINE, "role back to OFFLINE")


func _test_lobby_changed_signal_fires() -> void:
	var fired := [0]
	nm.lobby_changed.connect(func(): fired[0] += 1)
	nm.register_peer(1)        # +1
	nm.register_peer(1)        # idempotent, no emit
	nm.unregister_peer(1)      # +1
	nm.unregister_peer(1)      # already gone, no emit
	assert_eq(fired[0], 2, "lobby_changed fires only on real roster changes")

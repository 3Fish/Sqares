extends TestCase

## Unit tests for the NetworkManager roster-mirror / local-slot helpers added
## for combat-state replication (#27): the client side of the lobby mirror
## (#66 parked this here) and the local player's slot lookup.
##
## Pure dictionary/role bookkeeping on a fresh instance, matching the
## static-helper convention; the live RPC push that feeds `adopt_roster` is
## boot-verified.

const NetworkManagerScript = preload("res://scripts/multiplayer/network_manager.gd")

var nm: Node


func before_each() -> void:
	nm = NetworkManagerScript.new()


func after_each() -> void:
	if nm:
		nm.free()
		nm = null


func _test_adopt_roster_replaces_local_view() -> void:
	# A client adopts the host's authoritative roster, dropping any stale view.
	nm.register_peer(1)  # a stale local entry
	nm.adopt_roster({5: {"slot": 0}, 6: {"slot": 1}})
	assert_eq(nm.peer_count(), 2, "adopted roster size")
	assert_eq(nm.slot_of(5), 0, "adopted slot for peer 5")
	assert_eq(nm.slot_of(6), 1, "adopted slot for peer 6")
	assert_eq(nm.slot_of(1), -1, "stale local entry dropped")


func _test_adopt_roster_coerces_wire_values() -> void:
	# Crossing the wire, keys/values may arrive as floats/strings.
	nm.adopt_roster({"7": {"slot": "2"}})
	assert_eq(nm.slot_of(7), 2, "string key + string slot coerced to ints")


func _test_adopt_roster_skips_malformed_entries() -> void:
	nm.adopt_roster({1: "nope", 2: {"slot": 0}})
	assert_eq(nm.peer_count(), 1, "non-dictionary entry skipped")
	assert_eq(nm.slot_of(2), 0, "valid entry adopted")


func _test_adopt_roster_emits_lobby_changed() -> void:
	var fired := [0]
	nm.lobby_changed.connect(func(): fired[0] += 1)
	nm.adopt_roster({9: {"slot": 0}})
	assert_eq(fired[0], 1, "adopting a roster notifies the lobby UI")


func _test_local_slot_offline_is_minus_one() -> void:
	# Offline (no multiplayer peer): there is no local network slot.
	assert_eq(nm.local_slot(), -1, "offline -> local_slot -1")

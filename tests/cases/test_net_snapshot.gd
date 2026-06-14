extends TestCase

## Unit tests for the NetSnapshot wire format (#27).

# Minimal duck-typed stand-ins for a live Player / Health (same shape as the
# NetPlayerState test stubs), so capture can run without a scene tree.
class _StubHealth extends RefCounted:
	var current_hp: float = 0.0

class _StubPlayer extends RefCounted:
	var player_id: int = 0
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var health = null


func _make_player(pid: int, pos: Vector2, hp: float) -> _StubPlayer:
	var h := _StubHealth.new()
	h.current_hp = hp
	var p := _StubPlayer.new()
	p.player_id = pid
	p.global_position = pos
	p.health = h
	return p


func _test_capture_packs_all_players_with_acks() -> void:
	var players := [_make_player(0, Vector2(10, 0), 100.0), _make_player(1, Vector2(-5, 8), 40.0)]
	var snap := NetSnapshot.capture(players, 120, {1: 33})
	assert_eq(snap.tick, 120, "captures the host tick")
	assert_eq(snap.players.size(), 2, "one state per player")
	assert_eq(snap.state_for(0).position, Vector2(10, 0), "player 0 position captured")
	assert_eq(snap.state_for(0).last_input_seq, 0, "no input stream -> ack 0")
	assert_eq(snap.state_for(1).last_input_seq, 33, "player 1 ack from last_seqs")
	assert_almost_eq(snap.state_for(1).health, 40.0, "player 1 health captured")


func _test_capture_skips_null_players() -> void:
	var snap := NetSnapshot.capture([null, _make_player(2, Vector2.ZERO, 1.0)], 1)
	assert_eq(snap.players.size(), 1, "null entries skipped")
	assert_eq(snap.players[0].player_id, 2, "real player kept")


func _test_dict_roundtrip() -> void:
	var snap := NetSnapshot.capture([_make_player(0, Vector2(3, 4), 80.0)], 77, {0: 5})
	var restored := NetSnapshot.from_dict(snap.to_dict())
	assert_eq(restored.tick, 77, "tick round-trips")
	assert_eq(restored.players.size(), 1, "players round-trip")
	assert_eq(restored.state_for(0).position, Vector2(3, 4), "position round-trips")
	assert_eq(restored.state_for(0).last_input_seq, 5, "ack round-trips")
	assert_almost_eq(restored.state_for(0).health, 80.0, "health round-trips")


func _test_from_dict_defaults_and_malformed() -> void:
	var empty := NetSnapshot.from_dict({})
	assert_eq(empty.tick, 0, "missing tick -> 0")
	assert_eq(empty.players.size(), 0, "missing players -> empty")
	# Non-dictionary player entries are skipped, not crashed on.
	var mixed := NetSnapshot.from_dict({"tick": 9, "players": ["junk", {"player_id": 3}]})
	assert_eq(mixed.players.size(), 1, "malformed entry skipped")
	assert_eq(mixed.players[0].player_id, 3, "valid entry kept")
	# A non-array players field is tolerated too.
	assert_eq(NetSnapshot.from_dict({"players": "nope"}).players.size(), 0, "non-array players -> empty")


func _test_state_for_missing_player() -> void:
	var snap := NetSnapshot.capture([_make_player(0, Vector2.ZERO, 1.0)], 1)
	assert_null(snap.state_for(9), "unknown player -> null")

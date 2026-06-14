extends TestCase

## Unit tests for the NetPlayerState basic-replication snapshot (#23).

# Minimal duck-typed stand-ins for a live Player / Health, so capture/apply can
# be exercised without a scene tree.
class _StubHealth extends RefCounted:
	var current_hp: float = 0.0

class _StubPlayer extends RefCounted:
	var player_id: int = 0
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var health = null


func _test_to_dict_flattens_vectors() -> void:
	var s := NetPlayerState.new()
	s.player_id = 2
	s.position = Vector2(12, -34)
	s.velocity = Vector2(5, 6)
	s.health = 73.5
	var d := s.to_dict()
	assert_eq(d["player_id"], 2, "player_id serialised")
	assert_eq(d["position"], [12.0, -34.0], "position flattened to [x, y]")
	assert_eq(d["velocity"], [5.0, 6.0], "velocity flattened to [x, y]")
	assert_eq(d["health"], 73.5, "health serialised")


func _test_from_dict_roundtrip() -> void:
	var original := NetPlayerState.new()
	original.player_id = 3
	original.position = Vector2(100, 200)
	original.velocity = Vector2(-7, 8)
	original.health = 42.0
	var restored := NetPlayerState.from_dict(original.to_dict())
	assert_eq(restored.player_id, 3, "player_id round-trips")
	assert_eq(restored.position, Vector2(100, 200), "position round-trips")
	assert_eq(restored.velocity, Vector2(-7, 8), "velocity round-trips")
	assert_almost_eq(restored.health, 42.0, "health round-trips")


func _test_from_dict_defaults_on_empty() -> void:
	var s := NetPlayerState.from_dict({})
	assert_eq(s.player_id, 0, "missing player_id -> 0")
	assert_eq(s.position, Vector2.ZERO, "missing position -> ZERO")
	assert_eq(s.velocity, Vector2.ZERO, "missing velocity -> ZERO")
	assert_almost_eq(s.health, 0.0, "missing health -> 0")


func _test_from_dict_tolerates_malformed_vectors() -> void:
	# Too-short array, wrong type, and a raw Vector2 are all handled.
	assert_eq(NetPlayerState.from_dict({"position": [1]}).position, Vector2.ZERO, "short array -> ZERO")
	assert_eq(NetPlayerState.from_dict({"position": "nope"}).position, Vector2.ZERO, "non-array -> ZERO")
	assert_eq(NetPlayerState.from_dict({"position": Vector2(3, 4)}).position, Vector2(3, 4), "raw Vector2 accepted")


func _test_capture_reads_from_player() -> void:
	var hp := _StubHealth.new()
	hp.current_hp = 55.0
	var p := _StubPlayer.new()
	p.player_id = 3
	p.global_position = Vector2(10, 20)
	p.velocity = Vector2(1, 2)
	p.health = hp
	var s := NetPlayerState.capture(p)
	assert_eq(s.player_id, 3, "captures player_id")
	assert_eq(s.position, Vector2(10, 20), "captures global_position")
	assert_eq(s.velocity, Vector2(1, 2), "captures velocity")
	assert_almost_eq(s.health, 55.0, "captures current_hp")


func _test_last_input_seq_roundtrips() -> void:
	# The ack field added for input reconciliation (#27) serialises and is
	# passed into capture (host bookkeeping, not read off the node).
	var s := NetPlayerState.new()
	s.last_input_seq = 88
	assert_eq(s.to_dict()["last_input_seq"], 88, "ack serialised")
	assert_eq(NetPlayerState.from_dict(s.to_dict()).last_input_seq, 88, "ack round-trips")
	assert_eq(NetPlayerState.from_dict({}).last_input_seq, 0, "missing ack -> 0")
	var hp := _StubHealth.new()
	var p := _StubPlayer.new()
	p.health = hp
	assert_eq(NetPlayerState.capture(p, 12).last_input_seq, 12, "capture stores the passed ack")
	assert_eq(NetPlayerState.capture(p).last_input_seq, 0, "default ack is 0")


func _test_capture_null_player_is_safe() -> void:
	var s := NetPlayerState.capture(null)
	assert_not_null(s, "returns a default snapshot, not null")
	assert_eq(s.player_id, 0, "default player_id")


func _test_capture_tolerates_missing_health() -> void:
	var p := _StubPlayer.new()
	p.player_id = 1
	p.health = null
	var s := NetPlayerState.capture(p)
	assert_almost_eq(s.health, 0.0, "no health node -> health stays 0")


func _test_apply_to_writes_onto_player() -> void:
	var s := NetPlayerState.new()
	s.position = Vector2(300, 400)
	s.velocity = Vector2(9, -9)
	s.health = 66.0
	var hp := _StubHealth.new()
	var p := _StubPlayer.new()
	p.health = hp
	s.apply_to(p)
	assert_eq(p.global_position, Vector2(300, 400), "applies position")
	assert_eq(p.velocity, Vector2(9, -9), "applies velocity")
	assert_almost_eq(hp.current_hp, 66.0, "applies health")


func _test_apply_to_null_player_is_safe() -> void:
	var s := NetPlayerState.new()
	s.apply_to(null)  # must not crash
	assert_true(true, "apply_to(null) is a no-op")

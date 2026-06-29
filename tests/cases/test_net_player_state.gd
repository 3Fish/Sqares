extends TestCase

## Unit tests for the NetPlayerState basic-replication snapshot (#23).

# Minimal duck-typed stand-ins for a live Player / Health, so capture/apply can
# be exercised without a scene tree.
class _StubHealth extends RefCounted:
	var current_hp: float = 0.0
	var _shielded: bool = false
	func is_shielded() -> bool: return _shielded
	func set_shielded(active: bool) -> void: _shielded = active

# A health stand-in WITHOUT the shield methods, to prove capture/apply guard on
# `has_method` and stay a no-op for an old-style or shieldless player.
class _BareHealth extends RefCounted:
	var current_hp: float = 0.0

class _StubWeapon extends RefCounted:
	var _ammo: int = 0
	var _reload_progress: float = -1.0
	func get_ammo() -> int: return _ammo
	func set_ammo(value: int) -> void: _ammo = value
	func get_reload_progress() -> float: return _reload_progress
	func set_reload_progress(value: float) -> void: _reload_progress = value

class _StubPlayer extends RefCounted:
	var player_id: int = 0
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var health = null
	var weapon = null


func _test_to_dict_flattens_vectors() -> void:
	var s := NetPlayerState.new()
	s.player_id = 2
	s.position = Vector2(12, -34)
	s.velocity = Vector2(5, 6)
	s.health = 73.5
	s.ammo = 4
	s.reload_progress = 0.25
	var d := s.to_dict()
	assert_eq(d["player_id"], 2, "player_id serialised")
	assert_eq(d["position"], [12.0, -34.0], "position flattened to [x, y]")
	assert_eq(d["velocity"], [5.0, 6.0], "velocity flattened to [x, y]")
	assert_eq(d["health"], 73.5, "health serialised")
	assert_eq(d["ammo"], 4, "ammo serialised")
	assert_eq(d["reload_progress"], 0.25, "reload_progress serialised")


func _test_from_dict_roundtrip() -> void:
	var original := NetPlayerState.new()
	original.player_id = 3
	original.position = Vector2(100, 200)
	original.velocity = Vector2(-7, 8)
	original.health = 42.0
	original.ammo = 2
	original.reload_progress = 0.5
	var restored := NetPlayerState.from_dict(original.to_dict())
	assert_eq(restored.player_id, 3, "player_id round-trips")
	assert_eq(restored.position, Vector2(100, 200), "position round-trips")
	assert_eq(restored.velocity, Vector2(-7, 8), "velocity round-trips")
	assert_almost_eq(restored.health, 42.0, "health round-trips")
	assert_eq(restored.ammo, 2, "ammo round-trips")
	assert_almost_eq(restored.reload_progress, 0.5, "reload_progress round-trips")


func _test_from_dict_defaults_on_empty() -> void:
	var s := NetPlayerState.from_dict({})
	assert_eq(s.player_id, 0, "missing player_id -> 0")
	assert_eq(s.position, Vector2.ZERO, "missing position -> ZERO")
	assert_eq(s.velocity, Vector2.ZERO, "missing velocity -> ZERO")
	assert_almost_eq(s.health, 0.0, "missing health -> 0")
	assert_eq(s.ammo, -1, "missing ammo -> -1 (not carried)")
	assert_almost_eq(s.reload_progress, -1.0, "missing reload_progress -> -1 (not carried)")


func _test_from_dict_tolerates_malformed_vectors() -> void:
	# Too-short array, wrong type, and a raw Vector2 are all handled.
	assert_eq(NetPlayerState.from_dict({"position": [1]}).position, Vector2.ZERO, "short array -> ZERO")
	assert_eq(NetPlayerState.from_dict({"position": "nope"}).position, Vector2.ZERO, "non-array -> ZERO")
	assert_eq(NetPlayerState.from_dict({"position": Vector2(3, 4)}).position, Vector2(3, 4), "raw Vector2 accepted")


func _test_capture_reads_from_player() -> void:
	var hp := _StubHealth.new()
	hp.current_hp = 55.0
	var wpn := _StubWeapon.new()
	wpn._ammo = 2
	wpn._reload_progress = 0.4
	var p := _StubPlayer.new()
	p.player_id = 3
	p.global_position = Vector2(10, 20)
	p.velocity = Vector2(1, 2)
	p.health = hp
	p.weapon = wpn
	var s := NetPlayerState.capture(p)
	assert_eq(s.player_id, 3, "captures player_id")
	assert_eq(s.position, Vector2(10, 20), "captures global_position")
	assert_eq(s.velocity, Vector2(1, 2), "captures velocity")
	assert_almost_eq(s.health, 55.0, "captures current_hp")
	assert_eq(s.ammo, 2, "captures the weapon's round count")
	assert_almost_eq(s.reload_progress, 0.4, "captures the weapon's reload progress")


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
	s.ammo = 1
	s.reload_progress = 0.75
	var hp := _StubHealth.new()
	var wpn := _StubWeapon.new()
	wpn._ammo = 5
	var p := _StubPlayer.new()
	p.health = hp
	p.weapon = wpn
	s.apply_to(p)
	assert_eq(p.global_position, Vector2(300, 400), "applies position")
	assert_eq(p.velocity, Vector2(9, -9), "applies velocity")
	assert_almost_eq(hp.current_hp, 66.0, "applies health")
	assert_eq(wpn._ammo, 1, "applies the authoritative ammo onto the weapon")
	assert_almost_eq(wpn._reload_progress, 0.75, "applies the authoritative reload progress onto the weapon")


func _test_apply_to_null_player_is_safe() -> void:
	var s := NetPlayerState.new()
	s.apply_to(null)  # must not crash
	assert_true(true, "apply_to(null) is a no-op")


# --- ammo + reload-progress replication (#117 / #123) ------------------------

func _test_capture_without_weapon_leaves_ammo_uncarried() -> void:
	var p := _StubPlayer.new()
	p.health = _StubHealth.new()
	p.weapon = null
	var s := NetPlayerState.capture(p)
	assert_eq(s.ammo, -1, "a weaponless player carries no ammo (-1)")
	assert_almost_eq(s.reload_progress, -1.0, "a weaponless player carries no reload progress (-1)")


func _test_apply_ammo_to_writes_only_ammo() -> void:
	var s := NetPlayerState.new()
	s.position = Vector2(10, 10)  # should be ignored by the ammo-only path
	s.ammo = 3
	s.reload_progress = 0.6
	var wpn := _StubWeapon.new()
	wpn._ammo = 0
	var p := _StubPlayer.new()
	p.weapon = wpn
	s.apply_ammo_to(p)
	assert_eq(wpn._ammo, 3, "apply_ammo_to adopts the count")
	assert_almost_eq(wpn._reload_progress, 0.6, "apply_ammo_to adopts the reload progress")
	assert_eq(p.global_position, Vector2.ZERO, "apply_ammo_to leaves the transform untouched")


func _test_apply_ammo_to_skips_uncarried_ammo() -> void:
	# A -1 (not carried) ammo / progress must never clear an existing magazine or
	# zero the reload readout.
	var s := NetPlayerState.new()  # ammo and reload_progress default to -1
	var wpn := _StubWeapon.new()
	wpn._ammo = 4
	wpn._reload_progress = 0.3
	var p := _StubPlayer.new()
	p.weapon = wpn
	s.apply_ammo_to(p)
	assert_eq(wpn._ammo, 4, "uncarried ammo (-1) leaves the magazine alone")
	assert_almost_eq(wpn._reload_progress, 0.3, "uncarried reload progress (-1) leaves the readout alone")


func _test_apply_ammo_to_adopts_zero_reload_progress() -> void:
	# A genuine 0.0 (just fired) is a carried value, distinct from the -1 "not
	# carried" sentinel, so it must be adopted rather than skipped.
	var s := NetPlayerState.new()
	s.ammo = 2
	s.reload_progress = 0.0
	var wpn := _StubWeapon.new()
	wpn._reload_progress = 0.9
	var p := _StubPlayer.new()
	p.weapon = wpn
	s.apply_ammo_to(p)
	assert_almost_eq(wpn._reload_progress, 0.0, "a carried 0.0 reload progress is adopted")


func _test_apply_ammo_to_weaponless_player_is_safe() -> void:
	var s := NetPlayerState.new()
	s.ammo = 2
	s.reload_progress = 0.5
	var p := _StubPlayer.new()
	p.weapon = null
	s.apply_ammo_to(p)  # must not crash
	assert_true(true, "apply_ammo_to with no weapon is a no-op")


# --- reflecting-shield-up replication (#158) ---------------------------------

func _test_shielded_serialises_and_roundtrips() -> void:
	var s := NetPlayerState.new()
	s.shielded = true
	assert_eq(s.to_dict()["shielded"], true, "shielded serialised")
	assert_eq(NetPlayerState.from_dict(s.to_dict()).shielded, true, "shielded round-trips")
	assert_eq(NetPlayerState.from_dict({}).shielded, false, "missing shielded -> false (no shield shown)")


func _test_capture_reads_shield_state() -> void:
	var hp := _StubHealth.new()
	hp._shielded = true
	var p := _StubPlayer.new()
	p.health = hp
	assert_eq(NetPlayerState.capture(p).shielded, true, "captures the host's is_shielded()")
	hp._shielded = false
	assert_eq(NetPlayerState.capture(p).shielded, false, "captures a lowered shield as false")


func _test_capture_tolerates_health_without_shield_api() -> void:
	# An old-style health node exposing no is_shielded() must not crash capture; the
	# flag simply stays at its safe default.
	var p := _StubPlayer.new()
	p.health = _BareHealth.new()
	assert_eq(NetPlayerState.capture(p).shielded, false, "no is_shielded() -> shielded stays false")


func _test_apply_shield_to_stamps_puppet_health() -> void:
	var s := NetPlayerState.new()
	s.position = Vector2(10, 10)  # should be ignored by the shield-only path
	s.shielded = true
	var hp := _StubHealth.new()
	var p := _StubPlayer.new()
	p.health = hp
	s.apply_shield_to(p)
	assert_eq(hp._shielded, true, "apply_shield_to adopts the host's shield-up state")
	assert_eq(p.global_position, Vector2.ZERO, "apply_shield_to leaves the transform untouched")
	# A lowered host shield clears a stale puppet shield.
	s.shielded = false
	s.apply_shield_to(p)
	assert_eq(hp._shielded, false, "apply_shield_to clears the shield when the host's is down")


func _test_apply_shield_to_tolerates_missing_api_and_null() -> void:
	# Healthless / null player and a health without set_shielded are all no-ops.
	var s := NetPlayerState.new()
	s.shielded = true
	s.apply_shield_to(null)  # must not crash
	var p := _StubPlayer.new()
	p.health = _BareHealth.new()
	s.apply_shield_to(p)  # must not crash (no set_shielded)
	var p2 := _StubPlayer.new()
	p2.health = null
	s.apply_shield_to(p2)  # must not crash
	assert_true(true, "apply_shield_to is a no-op without a shield-capable health")

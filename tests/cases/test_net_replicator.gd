extends TestCase

## Unit tests for NetReplicator's pure/scene-free transport logic (#27).
##
## The RPC plumbing needs a live multiplayer peer, so it's verified by a
## headless boot smoke test; the input-queue bookkeeping and the wire helpers
## are plain logic and are tested directly on a fresh instance / via statics,
## matching the static-helper convention used for NetworkManager.

const NetReplicatorScript = preload("res://scripts/multiplayer/net_replicator.gd")

# Duck-typed stand-in for a Projectile, so projectile_payload can be exercised
# without instancing the scene.
class _StubProjectile extends RefCounted:
	var net_id: String = "n1"
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var scale: Vector2 = Vector2.ONE
	var bounces_remaining: int = 0
	var homing: float = 0.0

var rep


func before_each() -> void:
	rep = NetReplicatorScript.new()


func after_each() -> void:
	if rep:
		rep.free()
		rep = null


func _make_input(seq: int) -> NetPlayerInput:
	var input := NetPlayerInput.new()
	input.seq = seq
	return input


# --- merge_input (pure static) --------------------------------------------

func _test_merge_input_appends_new() -> void:
	var q := NetReplicatorScript.merge_input([], _make_input(1), 0, 8)
	q = NetReplicatorScript.merge_input(q, _make_input(2), 0, 8)
	assert_eq(q.size(), 2, "two distinct inputs queued")
	assert_eq(int(q[0].seq), 1, "ordered oldest first")
	assert_eq(int(q[1].seq), 2, "newest last")


func _test_merge_input_drops_already_processed() -> void:
	# last_processed = 5: an input at seq 3 is stale and ignored.
	var q := NetReplicatorScript.merge_input([], _make_input(3), 5, 8)
	assert_eq(q.size(), 0, "stale seq below the ack is dropped")


func _test_merge_input_drops_duplicates_in_window() -> void:
	# Redundant overlapping windows re-send the same inputs; only new ones land.
	var q := NetReplicatorScript.merge_input([], _make_input(4), 0, 8)
	q = NetReplicatorScript.merge_input(q, _make_input(4), 0, 8)
	q = NetReplicatorScript.merge_input(q, _make_input(3), 0, 8)
	assert_eq(q.size(), 1, "duplicate and out-of-order seqs ignored")
	assert_eq(int(q[0].seq), 4, "only the first new seq retained")


func _test_merge_input_trims_to_backlog() -> void:
	var q: Array = []
	for i in range(1, 13):
		q = NetReplicatorScript.merge_input(q, _make_input(i), 0, 8)
	assert_eq(q.size(), 8, "queue trimmed to max backlog")
	assert_eq(int(q[0].seq), 5, "oldest entries dropped first")
	assert_eq(int(q.back().seq), 12, "newest entry retained")


func _test_merge_input_null_is_noop() -> void:
	assert_eq(NetReplicatorScript.merge_input([], null, 0, 8).size(), 0, "null input ignored")


# --- queue_inputs / pull_input (instance, no scene tree) -------------------

func _test_queue_and_pull_round_trip() -> void:
	rep.queue_inputs(0, [_make_input(1).to_dict(), _make_input(2).to_dict()])
	var first = rep.pull_input(0)
	assert_eq(first.seq, 1, "pull returns oldest queued input first")
	var second = rep.pull_input(0)
	assert_eq(second.seq, 2, "second pull returns next input")
	assert_null(rep.pull_input(0), "empty queue -> null")


func _test_pull_input_records_ack() -> void:
	rep.queue_inputs(0, [_make_input(7).to_dict()])
	rep.pull_input(0)
	# A subsequent stale window (seq <= 7) is now rejected by the recorded ack.
	rep.queue_inputs(0, [_make_input(5).to_dict()])
	assert_null(rep.pull_input(0), "input below the processed ack is not queued")


func _test_queue_inputs_ignores_malformed_payloads() -> void:
	rep.queue_inputs(0, ["junk", 42, _make_input(1).to_dict()])
	var pulled = rep.pull_input(0)
	assert_not_null(pulled, "valid payload still queued past malformed ones")
	assert_eq(pulled.seq, 1, "only the valid input is queued")


# --- projectile helpers (pure) --------------------------------------------

func _test_make_projectile_id_unique_per_peer_counter() -> void:
	assert_eq(NetReplicatorScript.make_projectile_id(2, 5), "2_5", "id is peer_counter")
	assert_true(
		NetReplicatorScript.make_projectile_id(2, 5) != NetReplicatorScript.make_projectile_id(3, 5),
		"different peers -> different ids"
	)


func _test_projectile_payload_flattens_render_state() -> void:
	var proj := _StubProjectile.new()
	proj.net_id = "9_1"
	proj.global_position = Vector2(12, 34)
	proj.velocity = Vector2(100, -50)
	proj.scale = Vector2(2, 2)
	proj.bounces_remaining = 3
	proj.homing = 0.5
	var payload := NetReplicatorScript.projectile_payload(proj, 1)
	assert_eq(payload["net_id"], "9_1", "net_id carried")
	assert_eq(payload["player_id"], 1, "shooter slot carried")
	assert_eq(payload["position"], [12.0, 34.0], "position flattened")
	assert_eq(payload["velocity"], [100.0, -50.0], "velocity flattened")
	assert_almost_eq(payload["scale"], 2.0, "uniform scale carried")
	assert_eq(payload["bounces"], 3, "bounces carried")
	assert_almost_eq(payload["homing"], 0.5, "homing carried")
	# Damage / lifesteal / knockback are deliberately absent: hits are host-only.
	assert_false(payload.has("damage"), "no damage on the wire (host-authoritative)")

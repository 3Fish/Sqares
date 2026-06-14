extends TestCase

## Unit tests for NetPrediction: the client-side input/reconciliation history (#27).


func _make_input(seq: int) -> NetPlayerInput:
	var input := NetPlayerInput.new()
	input.seq = seq
	return input


func _test_record_and_size() -> void:
	var hist := NetPrediction.new()
	hist.record(_make_input(1), Vector2(1, 0), Vector2.ZERO)
	hist.record(_make_input(2), Vector2(2, 0), Vector2.ZERO)
	assert_eq(hist.size(), 2, "two recorded entries")


func _test_state_at_returns_recorded_state() -> void:
	var hist := NetPrediction.new()
	hist.record(_make_input(5), Vector2(50, 7), Vector2(1, 2))
	var entry = hist.state_at(5)
	assert_not_null(entry, "entry exists for recorded seq")
	assert_eq(entry["position"], Vector2(50, 7), "position recorded")
	assert_eq(entry["velocity"], Vector2(1, 2), "velocity recorded")
	assert_null(hist.state_at(99), "unknown seq -> null")


func _test_ack_drops_acknowledged_entries() -> void:
	var hist := NetPrediction.new()
	for i in range(1, 6):
		hist.record(_make_input(i), Vector2(i, 0), Vector2.ZERO)
	hist.ack(3)
	assert_eq(hist.size(), 2, "entries up to seq 3 dropped")
	assert_null(hist.state_at(3), "acked seq no longer present")
	assert_not_null(hist.state_at(4), "unacked seq 4 retained")


func _test_pending_returns_unacked_in_order() -> void:
	var hist := NetPrediction.new()
	for i in range(1, 5):
		hist.record(_make_input(i), Vector2(i, 0), Vector2.ZERO)
	hist.ack(2)
	var pending := hist.pending()
	assert_eq(pending.size(), 2, "two pending after ack(2)")
	assert_eq(int(pending[0]["seq"]), 3, "oldest pending first")
	assert_eq(int(pending[1]["seq"]), 4, "newest pending last")


func _test_pending_inputs_window() -> void:
	var hist := NetPrediction.new()
	for i in range(1, 6):
		hist.record(_make_input(i), Vector2.ZERO, Vector2.ZERO)
	var window := hist.pending_inputs(3)
	assert_eq(window.size(), 3, "window capped at requested count")
	assert_eq(window[0].seq, 3, "window is the newest inputs, oldest first")
	assert_eq(window[2].seq, 5, "window ends at the latest input")
	# Asking for more than exist returns everything.
	assert_eq(hist.pending_inputs(99).size(), 5, "window can't exceed history size")


func _test_history_cap_evicts_oldest() -> void:
	var hist := NetPrediction.new()
	for i in range(1, NetPrediction.MAX_HISTORY + 11):
		hist.record(_make_input(i), Vector2.ZERO, Vector2.ZERO)
	assert_eq(hist.size(), NetPrediction.MAX_HISTORY, "history capped at MAX_HISTORY")
	assert_null(hist.state_at(1), "oldest entry evicted")
	assert_not_null(hist.state_at(NetPrediction.MAX_HISTORY + 10), "newest entry kept")


func _test_clear() -> void:
	var hist := NetPrediction.new()
	hist.record(_make_input(1), Vector2.ZERO, Vector2.ZERO)
	hist.clear()
	assert_eq(hist.size(), 0, "cleared history is empty")


func _test_needs_correction_threshold() -> void:
	# Within tolerance -> no correction; beyond it -> correction.
	assert_false(
		NetPrediction.needs_correction(Vector2(0, 0), Vector2(5, 0), 8.0),
		"5px error under 8px tolerance -> no correction"
	)
	assert_true(
		NetPrediction.needs_correction(Vector2(0, 0), Vector2(20, 0), 8.0),
		"20px error over 8px tolerance -> correction"
	)
	assert_false(
		NetPrediction.needs_correction(Vector2(0, 0), Vector2(8, 0), 8.0),
		"error exactly at tolerance -> no correction"
	)

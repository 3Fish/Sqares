extends TestCase

## Unit tests for NetInterpolation: the client-side snapshot buffer that smooths
## a PUPPET player's motion between ~30 Hz snapshots (#28, deferred from #27).


func _test_empty_buffer_returns_empty() -> void:
	var buf := NetInterpolation.new()
	assert_eq(buf.size(), 0, "fresh buffer is empty")
	assert_true(buf.sample(0.0).is_empty(), "sampling an empty buffer yields {}")
	assert_almost_eq(buf.latest_time(), 0.0, "empty buffer latest_time is 0")


func _test_single_sample_returned_regardless_of_time() -> void:
	var buf := NetInterpolation.new()
	buf.push(1.0, Vector2(10, 20), Vector2(3, 4))
	# Before, at, and after the only sample's time all resolve to that sample.
	for rt in [0.0, 1.0, 5.0]:
		var s := buf.sample(rt)
		assert_eq(s["position"], Vector2(10, 20), "single-sample position @ %s" % rt)
		assert_eq(s["velocity"], Vector2(3, 4), "single-sample velocity @ %s" % rt)
	assert_almost_eq(buf.latest_time(), 1.0, "latest_time is the lone sample's time")


func _test_interpolates_position_and_velocity_at_midpoint() -> void:
	var buf := NetInterpolation.new()
	buf.push(0.0, Vector2(0, 0), Vector2(0, 0))
	buf.push(1.0, Vector2(10, 0), Vector2(20, -40))
	var s := buf.sample(0.5)
	assert_eq(s["position"], Vector2(5, 0), "midpoint position is the halfway lerp")
	assert_eq(s["velocity"], Vector2(10, -20), "midpoint velocity is the halfway lerp")


func _test_interpolates_at_quarter() -> void:
	var buf := NetInterpolation.new()
	buf.push(2.0, Vector2(0, 0), Vector2.ZERO)
	buf.push(6.0, Vector2(40, 80), Vector2.ZERO)
	# render_time 3.0 is 25% of the way from t=2 to t=6.
	var s := buf.sample(3.0)
	assert_eq(s["position"], Vector2(10, 20), "quarter-point position")


func _test_clamps_before_oldest() -> void:
	var buf := NetInterpolation.new()
	buf.push(5.0, Vector2(1, 1), Vector2(2, 2))
	buf.push(6.0, Vector2(9, 9), Vector2(8, 8))
	var s := buf.sample(0.0)  # render time predates the buffer
	assert_eq(s["position"], Vector2(1, 1), "before oldest -> oldest position")
	assert_eq(s["velocity"], Vector2(2, 2), "before oldest -> oldest velocity")


func _test_holds_newest_after_buffer_no_extrapolation() -> void:
	var buf := NetInterpolation.new()
	buf.push(0.0, Vector2(0, 0), Vector2(100, 0))
	buf.push(1.0, Vector2(10, 0), Vector2(100, 0))
	var s := buf.sample(5.0)  # well past the newest sample
	# A stalled stream freezes at the last known state rather than drifting on.
	assert_eq(s["position"], Vector2(10, 0), "after newest -> hold newest position")
	assert_eq(s["velocity"], Vector2(100, 0), "after newest -> hold newest velocity")


func _test_picks_correct_bracket_with_three_samples() -> void:
	var buf := NetInterpolation.new()
	buf.push(0.0, Vector2(0, 0), Vector2.ZERO)
	buf.push(1.0, Vector2(10, 0), Vector2.ZERO)
	buf.push(2.0, Vector2(30, 0), Vector2.ZERO)
	# 1.5 sits in the second segment (t=1 -> t=2): halfway between 10 and 30.
	assert_eq(buf.sample(1.5)["position"], Vector2(20, 0), "bracket is the 1..2 segment")
	# 0.5 sits in the first segment (t=0 -> t=1): halfway between 0 and 10.
	assert_eq(buf.sample(0.5)["position"], Vector2(5, 0), "bracket is the 0..1 segment")


func _test_exact_sample_time_returns_that_sample() -> void:
	var buf := NetInterpolation.new()
	buf.push(0.0, Vector2(0, 0), Vector2.ZERO)
	buf.push(1.0, Vector2(10, 0), Vector2.ZERO)
	buf.push(2.0, Vector2(30, 0), Vector2.ZERO)
	assert_eq(buf.sample(1.0)["position"], Vector2(10, 0), "render time on a sample boundary")


func _test_out_of_order_and_duplicate_pushes_ignored() -> void:
	var buf := NetInterpolation.new()
	buf.push(1.0, Vector2(10, 0), Vector2.ZERO)
	buf.push(1.0, Vector2(99, 99), Vector2.ZERO)  # duplicate timestamp -> ignored
	buf.push(0.5, Vector2(88, 88), Vector2.ZERO)  # older timestamp -> ignored
	assert_eq(buf.size(), 1, "stale/duplicate samples are dropped")
	assert_eq(buf.sample(1.0)["position"], Vector2(10, 0), "original sample is unchanged")


func _test_buffer_caps_and_evicts_oldest() -> void:
	var buf := NetInterpolation.new()
	for i in range(NetInterpolation.MAX_SAMPLES + 10):
		buf.push(float(i), Vector2(i, 0), Vector2.ZERO)
	assert_eq(buf.size(), NetInterpolation.MAX_SAMPLES, "size capped at MAX_SAMPLES")
	assert_almost_eq(
		buf.latest_time(), float(NetInterpolation.MAX_SAMPLES + 9),
		"newest sample retained after eviction"
	)


func _test_clear_empties_buffer() -> void:
	var buf := NetInterpolation.new()
	buf.push(0.0, Vector2(1, 2), Vector2.ZERO)
	buf.push(1.0, Vector2(3, 4), Vector2.ZERO)
	buf.clear()
	assert_eq(buf.size(), 0, "cleared buffer is empty")
	assert_true(buf.sample(0.5).is_empty(), "cleared buffer samples to {}")

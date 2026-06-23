extends TestCase

## Unit tests for StatRegistry's optional per-stat bounds + clamping (#43).
##
## StatRegistry is an autoload; these tests register uniquely-named probe stats
## so they neither collide with the base game's stats (which the deferred
## mod-loader does not populate during the headless run) nor with each other.


func _test_register_without_bounds_is_unbounded() -> void:
	StatRegistry.register("clamp_probe_unbounded", 10.0)
	# An unbounded stat clamps to itself for any value, in either direction.
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_unbounded", -999.0), -999.0,
		"no bound -> negatives pass through")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_unbounded", 1e9), 1e9,
		"no bound -> large values pass through")
	assert_eq(StatRegistry.get_bounds("clamp_probe_unbounded"), [-INF, INF],
		"unbounded stat reports [-INF, INF]")


func _test_register_with_min_only_floors() -> void:
	StatRegistry.register("clamp_probe_floor", 5.0, 0.0)
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_floor", -3.0), 0.0,
		"a below-floor value is raised to the minimum")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_floor", 42.0), 42.0,
		"an above-floor value is untouched (no upper cap)")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_floor", 0.0), 0.0,
		"a value exactly at the floor is kept")


func _test_register_with_max_only_caps() -> void:
	StatRegistry.register("clamp_probe_cap", 5.0, -INF, 10.0)
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_cap", 99.0), 10.0,
		"an above-cap value is lowered to the maximum")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_cap", -50.0), -50.0,
		"a below-cap value is untouched (no lower bound)")


func _test_register_with_both_bounds_clamps_each_end() -> void:
	StatRegistry.register("clamp_probe_band", 5.0, 1.0, 9.0)
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_band", 0.0), 1.0, "clamps up to min")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_band", 100.0), 9.0, "clamps down to max")
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_band", 4.0), 4.0, "in-range value kept")
	assert_eq(StatRegistry.get_bounds("clamp_probe_band"), [1.0, 9.0], "reports the registered band")


func _test_clamp_value_for_unregistered_stat_passes_through() -> void:
	# A stat that was never registered has no bounds, so clamping is a safe no-op.
	assert_almost_eq(StatRegistry.clamp_value("clamp_probe_never_registered", -123.0), -123.0,
		"unregistered stat clamps to itself")
	assert_eq(StatRegistry.get_bounds("clamp_probe_never_registered"), [-INF, INF],
		"unregistered stat reports [-INF, INF]")


func _test_bounds_do_not_alter_default_or_has_stat() -> void:
	# Bounds are orthogonal to the default/has_stat surface the rest of the game
	# reads — a bounded stat still defaults and reports presence normally.
	StatRegistry.register("clamp_probe_default", 7.5, 0.0, 100.0)
	assert_true(StatRegistry.has_stat("clamp_probe_default"), "bounded stat is registered")
	assert_almost_eq(StatRegistry.get_defaults().get("clamp_probe_default", -1.0), 7.5,
		"bounded stat still exposes its default")

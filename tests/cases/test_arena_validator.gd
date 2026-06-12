extends TestCase

## Unit tests for the pure arena validation rules (#36): min spawn count, bounds
## (degenerate sizes / unbounded play area), and reachable-geometry structural
## checks (solid ground, spawns clear of walls and kill zones).


## A baseline arena that passes every check: two spawns clear of geometry, a
## platform to stand on, and a kill zone so the play area is bounded.
func _valid_arena() -> ArenaData:
	var a := ArenaData.new()
	a.add_platform(Vector2(0, 100), Vector2(400, 32))
	a.add_kill_zone(Vector2(0, 600), Vector2(2000, 64))
	a.add_spawn_point(Vector2(-100, 0))
	a.add_spawn_point(Vector2(100, 0))
	return a


func _messages(issues: Array) -> String:
	return ArenaValidator.summarize(issues)


func _test_valid_arena_has_no_errors() -> void:
	var issues := ArenaValidator.validate(_valid_arena())
	assert_false(ArenaValidator.has_errors(issues), "baseline arena is error-free: %s" % _messages(issues))
	assert_true(ArenaValidator.is_valid(_valid_arena()), "baseline arena is_valid")


func _test_null_arena_is_invalid() -> void:
	var issues := ArenaValidator.validate(null)
	assert_true(ArenaValidator.has_errors(issues), "null arena reports an error")
	assert_false(ArenaValidator.is_valid(null), "null arena is not valid")


func _test_too_few_spawns_is_error() -> void:
	var a := _valid_arena()
	a.remove_spawn_point(1)  # leaves a single spawn, below the floor of 2
	var issues := ArenaValidator.validate(a)
	assert_true(ArenaValidator.has_errors(issues), "1 spawn is an error")

	var none := _valid_arena()
	none.remove_spawn_point(1)
	none.remove_spawn_point(0)
	assert_false(ArenaValidator.is_valid(none), "0 spawns is an error")


func _test_fewer_than_recommended_spawns_is_warning_only() -> void:
	# Exactly MIN_SPAWN_POINTS (2) but below RECOMMENDED (4): valid, but warns.
	var issues := ArenaValidator.validate(_valid_arena())
	assert_false(ArenaValidator.has_errors(issues), "2 spawns is not an error")
	assert_true(ArenaValidator.has_warnings(issues), "2 spawns warns about sharing")


func _test_full_spawn_set_does_not_warn_about_count() -> void:
	var a := _valid_arena()
	a.add_spawn_point(Vector2(-200, 0))
	a.add_spawn_point(Vector2(200, 0))  # now 4 spawns == RECOMMENDED
	var issues := ArenaValidator.validate(a)
	assert_false(_messages(issues).contains("share a spawn"), "4 spawns: no share warning")


func _test_no_platforms_is_error() -> void:
	var a := ArenaData.new()
	a.add_kill_zone(Vector2(0, 600), Vector2(2000, 64))
	a.add_spawn_point(Vector2(-100, 0))
	a.add_spawn_point(Vector2(100, 0))
	var issues := ArenaValidator.validate(a)
	assert_true(ArenaValidator.has_errors(issues), "no platforms is an error")
	assert_true(_messages(issues).contains("nothing to stand on"), "explains the missing ground")


func _test_degenerate_platform_size_is_error() -> void:
	var a := _valid_arena()
	a.add_platform(Vector2(0, 0), Vector2(0, 32))  # zero width
	assert_true(ArenaValidator.has_errors(ArenaValidator.validate(a)), "zero-width platform is an error")

	var b := _valid_arena()
	b.add_platform(Vector2(0, 0), Vector2(64, -8))  # negative height
	assert_true(ArenaValidator.has_errors(ArenaValidator.validate(b)), "negative-height platform is an error")


func _test_degenerate_kill_zone_size_is_error() -> void:
	var a := _valid_arena()
	a.add_kill_zone(Vector2(0, 0), Vector2(64, 0))  # zero height
	assert_true(ArenaValidator.has_errors(ArenaValidator.validate(a)), "zero-height kill zone is an error")


func _test_no_kill_zones_warns_about_bounds() -> void:
	var a := ArenaData.new()
	a.add_platform(Vector2(0, 100), Vector2(400, 32))
	a.add_spawn_point(Vector2(-100, 0))
	a.add_spawn_point(Vector2(100, 0))
	var issues := ArenaValidator.validate(a)
	assert_false(ArenaValidator.has_errors(issues), "no kill zones is not an error")
	assert_true(_messages(issues).contains("fall away"), "warns the play area is unbounded")


func _test_spawn_inside_kill_zone_is_error() -> void:
	var a := _valid_arena()
	a.add_spawn_point(Vector2(0, 600))  # right in the kill zone added by _valid_arena
	var issues := ArenaValidator.validate(a)
	assert_true(ArenaValidator.has_errors(issues), "spawn inside a kill zone is an error")
	assert_true(_messages(issues).contains("instant death"), "explains the instant death")


func _test_spawn_inside_platform_is_warning_not_error() -> void:
	var a := _valid_arena()
	a.add_spawn_point(Vector2(0, 100))  # buried in the platform at (0,100)
	var issues := ArenaValidator.validate(a)
	assert_false(ArenaValidator.has_errors(issues), "spawn in a platform is not an error")
	assert_true(_messages(issues).contains("may be stuck"), "warns about being stuck")


func _test_count_and_summary_helpers() -> void:
	# 0 spawns (error) + no platforms (error) + no kill zones (warning).
	var a := ArenaData.new()
	var issues := ArenaValidator.validate(a)
	assert_true(ArenaValidator.count(issues, ArenaValidator.Severity.ERROR) >= 2, "counts multiple errors")
	assert_true(ArenaValidator.count(issues, ArenaValidator.Severity.WARNING) >= 1, "counts the bounds warning")
	assert_eq(ArenaValidator.summarize([]), "Arena is valid.", "empty summary reads as valid")
	assert_true(_messages(issues).contains("[ERROR]"), "summary tags errors")

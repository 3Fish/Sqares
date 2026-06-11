extends TestCase

## Unit tests for ArenaData serialisation.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")


func _make_sample() -> ArenaData:
	var arena: ArenaData = ArenaDataScript.new()
	arena.id = "test_arena"
	arena.display_name = "Test Arena"
	arena.author = "tester"
	arena.background_color = Color(0.1, 0.2, 0.3, 1.0)
	arena.add_platform(Vector2(-100, 50), Vector2(240, 24), Color(0.3, 0.3, 0.45, 1.0))
	arena.add_platform(Vector2(100, -50), Vector2(160, 24))
	arena.add_spawn_point(Vector2(-400, 242))
	arena.add_spawn_point(Vector2(400, 242))
	arena.add_kill_zone(Vector2(0, 440), Vector2(1600, 32))
	return arena


func _test_builders_populate_collections() -> void:
	var arena := _make_sample()
	assert_eq(arena.platforms.size(), 2, "two platforms")
	assert_eq(arena.spawn_points.size(), 2, "two spawns")
	assert_eq(arena.kill_zones.size(), 1, "one kill zone")


func _test_default_platform_color() -> void:
	var arena: ArenaData = ArenaDataScript.new()
	arena.add_platform(Vector2.ZERO, Vector2(10, 10))
	assert_eq(arena.platforms[0]["color"], Color(0.3, 0.3, 0.45, 1.0), "default color applied")


func _test_remove_helpers_drop_the_indexed_element() -> void:
	var arena := _make_sample()
	arena.remove_platform(0)
	assert_eq(arena.platforms.size(), 1, "one platform left")
	assert_eq(arena.platforms[0]["position"], Vector2(100, -50), "the other platform survived")

	arena.remove_spawn_point(0)
	assert_eq(arena.spawn_points.size(), 1, "one spawn left")
	assert_eq(arena.spawn_points[0], Vector2(400, 242), "the other spawn survived")

	arena.remove_kill_zone(0)
	assert_eq(arena.kill_zones.size(), 0, "kill zone removed")


func _test_remove_out_of_range_is_a_noop() -> void:
	var arena := _make_sample()
	arena.remove_platform(-1)
	arena.remove_platform(99)
	arena.remove_spawn_point(5)
	arena.remove_kill_zone(-3)
	assert_eq(arena.platforms.size(), 2, "platforms untouched")
	assert_eq(arena.spawn_points.size(), 2, "spawns untouched")
	assert_eq(arena.kill_zones.size(), 1, "kill zones untouched")


func _test_to_dict_is_json_safe() -> void:
	var arena := _make_sample()
	var dict := arena.to_dict()
	# A round-trip through real JSON must succeed (no Vector2/Color leaking through).
	var text := JSON.stringify(dict)
	assert_true(text.length() > 0, "stringify produced output")
	assert_not_null(JSON.parse_string(text), "stringified dict re-parses")
	assert_eq(dict["format_version"], ArenaDataScript.FORMAT_VERSION, "version stamped")


func _test_round_trip_preserves_data() -> void:
	var original := _make_sample()
	var restored: ArenaData = ArenaDataScript.from_dict(original.to_dict())

	assert_eq(restored.id, "test_arena", "id preserved")
	assert_eq(restored.display_name, "Test Arena", "name preserved")
	assert_eq(restored.author, "tester", "author preserved")
	assert_eq(restored.background_color, Color(0.1, 0.2, 0.3, 1.0), "bg color preserved")
	assert_eq(restored.platforms.size(), 2, "platform count preserved")
	assert_eq(restored.platforms[0]["position"], Vector2(-100, 50), "platform position preserved")
	assert_eq(restored.platforms[0]["size"], Vector2(240, 24), "platform size preserved")
	assert_eq(restored.spawn_points.size(), 2, "spawn count preserved")
	assert_eq(restored.spawn_points[1], Vector2(400, 242), "spawn position preserved")
	assert_eq(restored.kill_zones.size(), 1, "kill zone count preserved")
	assert_eq(restored.kill_zones[0]["size"], Vector2(1600, 32), "kill zone size preserved")


func _test_json_round_trip() -> void:
	var original := _make_sample()
	var restored: ArenaData = ArenaDataScript.from_json(original.to_json())
	assert_not_null(restored, "from_json returned an arena")
	assert_eq(restored.to_json(), original.to_json(), "json is stable across a round trip")


func _test_from_json_rejects_garbage() -> void:
	assert_null(ArenaDataScript.from_json("not json at all"), "garbage string rejected")
	assert_null(ArenaDataScript.from_json("[1, 2, 3]"), "non-object json rejected")


func _test_from_dict_is_defensive() -> void:
	# Missing keys → defaults; malformed entries skipped rather than crashing.
	var restored: ArenaData = ArenaDataScript.from_dict({
		"id": "partial",
		"platforms": [{"position": [5, 6]}, "garbage"],  # one valid (size defaults), one junk
		"spawn_points": [[1, 2], "nope"],
	})
	assert_eq(restored.id, "partial", "id read")
	assert_eq(restored.display_name, "", "missing name defaults to empty")
	assert_eq(restored.platforms.size(), 1, "non-dict platform skipped")
	assert_eq(restored.platforms[0]["size"], Vector2.ZERO, "missing size defaults to zero")
	# Spawn points: only well-formed [x, y] entries become non-fallback vectors.
	assert_eq(restored.spawn_points[0], Vector2(1, 2), "valid spawn parsed")

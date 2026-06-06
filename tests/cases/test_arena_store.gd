extends TestCase

## Integration tests for ArenaStore save/load against the user:// filesystem.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")
const ArenaStoreScript = preload("res://scripts/arena/arena_store.gd")

# Distinct ids so the suite never collides with real user data, and is easy to purge.
const IDS := ["__test_alpha", "__test_beta", "__test_gamma"]


func before_each() -> void:
	_purge()


func after_each() -> void:
	_purge()


func _purge() -> void:
	for id in IDS:
		ArenaStoreScript.delete(id)


func _make(id: String) -> ArenaData:
	var arena: ArenaData = ArenaDataScript.new()
	arena.id = id
	arena.display_name = "Stored"
	arena.add_platform(Vector2(0, 100), Vector2(200, 24))
	arena.add_spawn_point(Vector2(-50, 80))
	arena.add_kill_zone(Vector2(0, 400), Vector2(800, 32))
	return arena


func _test_save_then_load_round_trip() -> void:
	var arena := _make("__test_alpha")
	var err: int = ArenaStoreScript.save(arena)
	assert_eq(err, OK, "save returned OK")
	assert_true(ArenaStoreScript.exists("__test_alpha"), "file exists after save")

	var loaded: ArenaData = ArenaStoreScript.load_arena("__test_alpha")
	assert_not_null(loaded, "load returned an arena")
	assert_eq(loaded.display_name, "Stored", "display_name persisted")
	assert_eq(loaded.spawn_points[0], Vector2(-50, 80), "spawn persisted through disk")
	assert_eq(loaded.platforms[0]["size"], Vector2(200, 24), "platform persisted through disk")


func _test_load_missing_returns_null() -> void:
	assert_null(ArenaStoreScript.load_arena("__test_does_not_exist"), "missing load is null")


func _test_delete_removes_file() -> void:
	ArenaStoreScript.save(_make("__test_beta"))
	assert_true(ArenaStoreScript.exists("__test_beta"), "exists before delete")
	var err: int = ArenaStoreScript.delete("__test_beta")
	assert_eq(err, OK, "delete returned OK")
	assert_false(ArenaStoreScript.exists("__test_beta"), "gone after delete")
	assert_eq(ArenaStoreScript.delete("__test_beta"), ERR_DOES_NOT_EXIST, "second delete reports missing")


func _test_list_ids_finds_saved_arenas() -> void:
	ArenaStoreScript.save(_make("__test_alpha"))
	ArenaStoreScript.save(_make("__test_gamma"))
	var ids := ArenaStoreScript.list_ids()
	assert_true(ids.has("__test_alpha"), "alpha listed")
	assert_true(ids.has("__test_gamma"), "gamma listed")


func _test_sanitize_id_makes_safe_filenames() -> void:
	assert_eq(ArenaStoreScript.sanitize_id("My Arena!"), "my_arena_", "spaces and punctuation collapsed")
	assert_eq(ArenaStoreScript.sanitize_id("Keep-It_1"), "keep-it_1", "safe chars preserved, lowercased")


func _test_save_backfills_id_from_display_name() -> void:
	var arena: ArenaData = ArenaDataScript.new()
	arena.display_name = "No Id Arena"
	var err: int = ArenaStoreScript.save(arena)
	assert_eq(err, OK, "save with empty id still OK")
	assert_eq(arena.id, "no_id_arena", "id back-filled from display name")
	# Clean up the extra file this test creates.
	ArenaStoreScript.delete("no_id_arena")


func _test_save_null_is_rejected() -> void:
	assert_eq(ArenaStoreScript.save(null), ERR_INVALID_PARAMETER, "null save rejected")

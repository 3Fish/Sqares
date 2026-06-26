extends TestCase

## Integration tests for MatchConfigStore save/load against the user:// filesystem
## (#135). Mirrors test_arena_store.gd: distinct names so the suite never collides
## with real user data and is easy to purge.

const StoreScript = preload("res://scripts/core/match_config_store.gd")

const NAMES := ["__test Brawl", "__test Duel", "__test_gamma"]


func before_each() -> void:
	_purge()


func after_each() -> void:
	_purge()


func _purge() -> void:
	for name in NAMES:
		StoreScript.delete(name)


func _sample(mode: String, wins: int, arena: String, ff: bool) -> Dictionary:
	return MatchConfig.to_dict(mode, wins, arena, ff)


func _test_save_then_load_round_trip() -> void:
	var err: int = StoreScript.save("__test Brawl", _sample("teams", 3, "highrise", false))
	assert_eq(err, OK, "save returned OK")
	assert_true(StoreScript.exists("__test Brawl"), "file exists after save")

	var loaded := StoreScript.load_config("__test Brawl")
	assert_false(loaded.is_empty(), "load returned a config")
	assert_eq(String(loaded["name"]), "__test Brawl", "display name persisted verbatim")
	assert_eq(String(loaded["game_mode"]), "teams", "mode persisted through disk")
	assert_eq(int(loaded["wins_needed"]), 3, "wins persisted through disk")
	assert_eq(String(loaded["arena_id"]), "highrise", "arena persisted through disk")
	assert_false(bool(loaded["friendly_fire"]), "friendly fire persisted through disk")


func _test_load_missing_returns_empty() -> void:
	assert_true(StoreScript.load_config("__test_does_not_exist").is_empty(), "missing load is empty")


func _test_exists_is_false_for_blank_name() -> void:
	assert_false(StoreScript.exists("   "), "a blank name has no file")


func _test_save_rejects_empty_name() -> void:
	assert_eq(StoreScript.save("  ", _sample("ffa", 5, "crossroads", true)),
		ERR_INVALID_PARAMETER, "blank name save rejected")


func _test_delete_removes_file() -> void:
	StoreScript.save("__test Duel", _sample("ffa", 5, "crossroads", true))
	assert_true(StoreScript.exists("__test Duel"), "exists before delete")
	assert_eq(StoreScript.delete("__test Duel"), OK, "delete returned OK")
	assert_false(StoreScript.exists("__test Duel"), "gone after delete")
	assert_eq(StoreScript.delete("__test Duel"), ERR_DOES_NOT_EXIST, "second delete reports missing")


func _test_list_names_returns_display_names() -> void:
	StoreScript.save("__test Brawl", _sample("teams", 3, "highrise", false))
	StoreScript.save("__test_gamma", _sample("ffa", 2, "crossroads", true))
	var names := StoreScript.list_names()
	assert_true(names.has("__test Brawl"), "spaced display name listed verbatim, not the slug")
	assert_true(names.has("__test_gamma"), "gamma listed")


func _test_sanitize_name_makes_safe_filenames() -> void:
	assert_eq(StoreScript.sanitize_name("My Config!"), "my_config_", "spaces and punctuation collapsed")
	assert_eq(StoreScript.sanitize_name("Keep-It_1"), "keep-it_1", "safe chars preserved, lowercased")


func _test_names_colliding_on_slug_overwrite() -> void:
	# "__test Brawl" and "__test_Brawl" slugify identically -> the A3 overwrite case.
	StoreScript.save("__test Brawl", _sample("teams", 3, "highrise", false))
	assert_true(StoreScript.exists("__test_Brawl"), "a slug-equal name reports as existing (overwrite prompt path)")
	StoreScript.save("__test_Brawl", _sample("ffa", 7, "crossroads", true))
	var loaded := StoreScript.load_config("__test Brawl")
	assert_eq(String(loaded["game_mode"]), "ffa", "second save overwrote the first on the shared slug")
	assert_eq(int(loaded["wins_needed"]), 7, "overwritten content reflects the latest save")

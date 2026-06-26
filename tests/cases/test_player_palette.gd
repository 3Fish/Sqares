extends TestCase

## Unit tests for the fixed named player-colour palette (#132): the palette's
## size, lookups, index clamping, and per-player default index. Pure static data
## and helpers — no scene-tree dependency, per the conventions in `CLAUDE.md`.


func _test_palette_has_sixteen_named_colours() -> void:
	# The maintainer asked for a fixed palette of 16 colours (#132 A1).
	assert_eq(PlayerPalette.count(), 16, "palette offers exactly 16 colours")
	for entry: Dictionary in PlayerPalette.COLORS:
		assert_true(entry.has("name"), "each entry carries a colour name")
		assert_false(String(entry["name"]).is_empty(), "the colour name is non-empty")
		assert_true(entry.has("color"), "each entry carries a Color")


func _test_color_and_name_lookups_match_entries() -> void:
	assert_eq(PlayerPalette.name_at(0), String(PlayerPalette.COLORS[0]["name"]), "name_at(0) matches the entry")
	assert_eq(PlayerPalette.color_at(0), PlayerPalette.COLORS[0]["color"], "color_at(0) matches the entry")
	var last := PlayerPalette.count() - 1
	assert_eq(PlayerPalette.name_at(last), String(PlayerPalette.COLORS[last]["name"]), "name_at(last) matches")


func _test_clamp_index_keeps_lookups_in_range() -> void:
	assert_eq(PlayerPalette.clamp_index(-5), 0, "negative index clamps up to 0")
	assert_eq(PlayerPalette.clamp_index(0), 0, "in-range index stays")
	assert_eq(PlayerPalette.clamp_index(PlayerPalette.count() - 1), PlayerPalette.count() - 1, "max stays")
	assert_eq(PlayerPalette.clamp_index(999), PlayerPalette.count() - 1, "too-high clamps down to last")
	# A wild index still resolves to a real colour rather than erroring.
	assert_eq(PlayerPalette.color_at(999), PlayerPalette.COLORS[PlayerPalette.count() - 1]["color"], "color_at clamps")


func _test_default_index_is_distinct_for_the_local_roster() -> void:
	# Players 0..3 (the local couch roster) each default to a distinct palette slot.
	var seen: Dictionary = {}
	for player_id in 4:
		var idx := PlayerPalette.default_index(player_id)
		assert_true(idx >= 0 and idx < PlayerPalette.count(), "default index is a real palette slot")
		seen[idx] = true
	assert_eq(seen.size(), 4, "the four local players default to four distinct colours")


func _test_default_index_wraps_past_the_palette() -> void:
	# A hypothetical id beyond the palette wraps rather than going out of range.
	assert_eq(PlayerPalette.default_index(PlayerPalette.count()), 0, "id == count wraps to 0")
	assert_eq(PlayerPalette.default_index(PlayerPalette.count() + 2), 2, "wraps modulo the palette size")

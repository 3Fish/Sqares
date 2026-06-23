extends TestCase

## Tests for the elastic-border visual (#84, deferred via #101). The frame / flash /
## out-of-bounds-arrow geometry lives in the pure, scene-free `BorderOverlay`; the
## node tracks the per-player out-of-bounds edge and the live flash list and exposes
## the same data through `flashes()` / `indicators()` (which `_draw` consumes). Per
## the maintainer's #101 answer the boundary is a semi-transparent red frame with a
## contact flash and a per-player arrow, so these cover the geometry only. Scene-
## tree-free per `CLAUDE.md`.

const Overlay = preload("res://scripts/ui/border_overlay.gd")

const HX := 640.0
const HY := 360.0


## Minimal duck-typed stand-in for a Player: the overlay reads only
## `global_position` and `is_out_of_bounds()`.
class StubPlayer extends RefCounted:
	var global_position: Vector2 = Vector2.ZERO
	var _oob: bool = false
	func is_out_of_bounds() -> bool:
		return _oob


# --- Pure world -> overlay mapping ------------------------------------------

func _test_world_origin_maps_to_screen_centre() -> void:
	assert_eq(Overlay.world_to_overlay(Vector2.ZERO), Vector2(HX, HY), "origin -> screen centre")


func _test_border_corners_map_to_viewport_corners() -> void:
	assert_eq(Overlay.world_to_overlay(Vector2(-HX, -HY)), Vector2(0, 0), "top-left border -> (0,0)")
	assert_eq(Overlay.world_to_overlay(Vector2(HX, HY)), Vector2(2 * HX, 2 * HY), "bottom-right border -> viewport corner")


# --- Pure flash fade --------------------------------------------------------

func _test_flash_is_full_at_start_and_gone_at_end() -> void:
	assert_almost_eq(Overlay.flash_alpha(0.0, 0.28), 1.0, "new flash is fully opaque")
	assert_almost_eq(Overlay.flash_alpha(0.28, 0.28), 0.0, "flash is gone at its duration")


func _test_flash_fades_linearly_and_clamps() -> void:
	assert_almost_eq(Overlay.flash_alpha(0.14, 0.28), 0.5, "half-life -> half alpha")
	assert_almost_eq(Overlay.flash_alpha(0.5, 0.28), 0.0, "past the duration clamps to 0")
	assert_almost_eq(Overlay.flash_alpha(0.1, 0.0), 0.0, "zero duration -> no flash")


# --- Pure contact point -----------------------------------------------------

func _test_contact_point_inside_is_unchanged() -> void:
	assert_eq(Overlay.border_contact_point(Vector2(100, 50)), Vector2(100, 50), "in-bounds point is its own contact point")


func _test_contact_point_clamps_to_the_crossed_edge() -> void:
	assert_eq(Overlay.border_contact_point(Vector2(800, 50)), Vector2(HX, 50), "past the right edge -> on the right border")
	assert_eq(Overlay.border_contact_point(Vector2(-800, -500)), Vector2(-HX, -HY), "past the top-left corner -> the corner")


# --- Pure indicator geometry ------------------------------------------------

func _test_indicator_clamps_far_offscreen_player_to_the_margin() -> void:
	# Far off the right: overlay x would be 2000+640 = 2640, clamped to width-margin.
	var pos := Overlay.indicator_position(Vector2(2000, 0), MapBorder.HALF_EXTENT, 28.0)
	assert_almost_eq(pos.x, 2 * HX - 28.0, "arrow stays a margin inside the right edge")
	assert_almost_eq(pos.y, HY, "arrow keeps the player's vertical position")


func _test_indicator_clamps_into_both_axes() -> void:
	var pos := Overlay.indicator_position(Vector2(-2000, 2000), MapBorder.HALF_EXTENT, 28.0)
	assert_almost_eq(pos.x, 28.0, "clamped to the left margin")
	assert_almost_eq(pos.y, 2 * HY - 28.0, "clamped to the bottom margin")


func _test_onscreen_player_indicator_is_not_clamped() -> void:
	var pos := Overlay.indicator_position(Vector2.ZERO, MapBorder.HALF_EXTENT, 28.0)
	assert_eq(pos, Vector2(HX, HY), "an on-screen position is left at its mapped point")


func _test_indicator_points_outward_toward_the_player() -> void:
	assert_almost_eq(Overlay.indicator_angle(Vector2(100, 0)), 0.0, "player to the right -> arrow points right")
	assert_almost_eq(Overlay.indicator_angle(Vector2(0, 100)), PI / 2.0, "player below -> arrow points down")
	assert_almost_eq(Overlay.indicator_angle(Vector2(-100, 0)), PI, "player to the left -> arrow points left")


# --- Node wiring (flash spawn / expiry, indicator list) ---------------------

func _test_in_bounds_player_has_no_flash_or_indicator() -> void:
	var overlay := Overlay.new()
	var p := StubPlayer.new()
	p.global_position = Vector2(100, 0)
	overlay.register_player(0, p, Color.RED, "P1")
	overlay.advance(0.0)
	assert_eq(overlay.flashes().size(), 0, "no contact flash while in bounds")
	assert_eq(overlay.indicators().size(), 0, "no arrow while in bounds")
	overlay.free()


func _test_crossing_out_spawns_one_flash_and_an_indicator() -> void:
	var overlay := Overlay.new()
	var p := StubPlayer.new()
	overlay.register_player(0, p, Color(0.4, 0.7, 1.0), "P1")
	# Cross the right border.
	p.global_position = Vector2(800, 50)
	p._oob = true
	overlay.advance(0.0)

	var fl := overlay.flashes()
	assert_eq(fl.size(), 1, "first contact spawns exactly one flash")
	assert_eq(fl[0]["position"], Vector2(2 * HX, 50 + HY), "flash sits at the contact point on the border")
	assert_almost_eq(fl[0]["alpha"], 1.0, "the new flash is fully opaque")

	var ind := overlay.indicators()
	assert_eq(ind.size(), 1, "one out-of-bounds arrow")
	assert_eq(ind[0]["label"], "P1", "arrow carries the player name")
	assert_eq(ind[0]["color"], Color(0.4, 0.7, 1.0), "arrow uses the player colour")
	overlay.free()


func _test_staying_out_does_not_respawn_the_flash() -> void:
	var overlay := Overlay.new()
	var p := StubPlayer.new()
	overlay.register_player(0, p, Color.RED, "P1")
	p.global_position = Vector2(800, 0)
	p._oob = true
	overlay.advance(0.0)
	overlay.advance(0.0)  # still out of bounds on the next tick
	assert_eq(overlay.flashes().size(), 1, "the flash fires once per excursion, not every tick")
	overlay.free()


func _test_flash_expires_after_its_duration() -> void:
	var overlay := Overlay.new()
	var p := StubPlayer.new()
	overlay.register_player(0, p, Color.RED, "P1")
	p.global_position = Vector2(800, 0)
	p._oob = true
	overlay.advance(0.0)
	overlay.advance(Overlay.FLASH_DURATION)  # age the flash out
	assert_eq(overlay.flashes().size(), 0, "the flash is gone once it reaches its duration")
	# Still out of bounds, so the arrow persists even after the flash fades.
	assert_eq(overlay.indicators().size(), 1, "the out-of-bounds arrow stays while the player is out")
	overlay.free()


func _test_re_entering_then_leaving_rearms_the_flash() -> void:
	var overlay := Overlay.new()
	var p := StubPlayer.new()
	overlay.register_player(0, p, Color.RED, "P1")
	p.global_position = Vector2(800, 0)
	p._oob = true
	overlay.advance(0.0)
	overlay.advance(Overlay.FLASH_DURATION)  # flash expires
	# Back in bounds...
	p._oob = false
	overlay.advance(0.0)
	assert_eq(overlay.indicators().size(), 0, "no arrow once back in bounds")
	# ...and out again -> a fresh contact flash.
	p._oob = true
	overlay.advance(0.0)
	assert_eq(overlay.flashes().size(), 1, "a new excursion spawns a fresh flash")
	overlay.free()

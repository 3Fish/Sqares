extends TestCase

## Tests for display / fullscreen scaling (#83).
##
## Exercises the pure letterbox / window-clamp helpers so the 16:9-preservation,
## minimum-size, and resolution-independence guarantees are verifiable without a
## live window.

const Display = preload("res://scripts/core/display_settings.gd")

const BASE := Vector2(1280, 720)


# --- Aspect & uniform scaling -----------------------------------------------

func _test_base_aspect_is_16_9() -> void:
	assert_almost_eq(Display.base_aspect(), 16.0 / 9.0, "base resolution is 16:9")


func _test_content_scale_is_uniform_and_fits() -> void:
	# Exact 16:9 windows scale uniformly with no border.
	assert_almost_eq(Display.content_scale(Vector2(1920, 1080), BASE), 1.5, "1080p scales 1.5x")
	assert_almost_eq(Display.content_scale(Vector2(640, 360), BASE), 0.5, "360p scales 0.5x")
	assert_almost_eq(Display.content_scale(BASE, BASE), 1.0, "native scales 1x")


func _test_minimum_size_is_16_9() -> void:
	var ratio := float(Display.MIN_WIDTH) / float(Display.MIN_HEIGHT)
	assert_almost_eq(ratio, 16.0 / 9.0, "minimum window size preserves 16:9")


# --- Letter-/pillarboxing instead of stretching -----------------------------

func _test_pillarbox_on_too_wide_window() -> void:
	# 21:9-ish window: height limits the scale -> vertical fill, horizontal bars.
	var win := Vector2(2560, 1080)
	assert_almost_eq(Display.content_scale(win, BASE), 1080.0 / 720.0, "scale limited by height")
	var rect := Display.viewport_rect(win, BASE)
	assert_almost_eq(rect.size.y, win.y, "content fills window height", 0.001)
	assert_true(rect.size.x < win.x, "horizontal pillarbox bars present")
	assert_almost_eq(rect.position.x, (win.x - rect.size.x) * 0.5, "content centred horizontally", 0.001)
	assert_almost_eq(rect.position.y, 0.0, "no vertical offset", 0.001)


func _test_letterbox_on_too_tall_window() -> void:
	# 4:3 window: width limits the scale -> horizontal fill, vertical bars.
	var win := Vector2(1280, 960)
	assert_almost_eq(Display.content_scale(win, BASE), 1.0, "scale limited by width")
	var rect := Display.viewport_rect(win, BASE)
	assert_almost_eq(rect.size.x, win.x, "content fills window width", 0.001)
	assert_true(rect.size.y < win.y, "vertical letterbox bars present")
	assert_almost_eq(rect.position.y, (win.y - rect.size.y) * 0.5, "content centred vertically", 0.001)


# --- Resolution-independent gameplay coordinates ----------------------------

func _test_world_coords_identical_across_resolutions() -> void:
	# Acceptance criterion: gameplay/world coordinates are independent of the
	# rendering resolution. A fixed world point maps to *different* screen pixels
	# at each resolution but round-trips back to the *same* world coordinate.
	var resolutions := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(854, 480), Vector2(640, 360)]
	var world_points := [Vector2(0, 0), Vector2(640, 360), Vector2(1280, 720), Vector2(300, 540)]
	for world: Vector2 in world_points:
		var screens: Array[Vector2] = []
		for res: Vector2 in resolutions:
			var screen := Display.world_to_screen(world, res, BASE)
			var back := Display.screen_to_world(screen, res, BASE)
			assert_almost_eq(back.x, world.x, "world x round-trips at %s" % res, 0.001)
			assert_almost_eq(back.y, world.y, "world y round-trips at %s" % res, 0.001)
			screens.append(screen)
		# Sanity: a non-origin point really does land on different pixels per
		# resolution, proving the invariance is meaningful, not a constant map.
		if world != Vector2.ZERO:
			assert_true(screens[0] != screens[1], "screen pixels differ across resolutions for %s" % world)


# --- Minimum window size ----------------------------------------------------

func _test_clamp_window_size_enforces_minimum() -> void:
	assert_eq(Display.clamp_window_size(Vector2i(320, 200)), Vector2i(480, 270), "clamps both axes up to minimum")
	assert_eq(Display.clamp_window_size(Vector2i(800, 100)), Vector2i(800, 270), "clamps only the deficient axis")
	assert_eq(Display.clamp_window_size(Vector2i(1280, 720)), Vector2i(1280, 720), "leaves valid size untouched")

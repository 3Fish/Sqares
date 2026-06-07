extends TestCase

## Covers the pure pan/zoom + coordinate maths behind the arena editor canvas
## (#34). These helpers are scene-free, so they can be exercised directly — the
## same convention as `test_match_director.gd`. The placement tools (#35) will
## build on `screen_to_world`, so the round-trip and zoom-about-cursor invariants
## matter beyond just the shell.

const VIEWPORT := Vector2(800, 600)


func _assert_vec_almost_eq(actual: Vector2, expected: Vector2, message: String = "") -> void:
	assert_almost_eq(actual.x, expected.x, "x " + message)
	assert_almost_eq(actual.y, expected.y, "y " + message)


# --- world <-> screen -------------------------------------------------------

func _test_world_to_screen_centres_pan() -> void:
	# The pan point always maps to the centre of the viewport, at any zoom.
	var pan := Vector2(120, -40)
	_assert_vec_almost_eq(
		EditorCamera.world_to_screen(pan, pan, 1.0, VIEWPORT), VIEWPORT * 0.5,
		"pan at centre (zoom 1)"
	)
	_assert_vec_almost_eq(
		EditorCamera.world_to_screen(pan, pan, 3.5, VIEWPORT), VIEWPORT * 0.5,
		"pan at centre (zoom 3.5)"
	)


func _test_world_to_screen_applies_zoom() -> void:
	# 10 world units right of pan, at zoom 2, is 20px right of centre.
	var screen := EditorCamera.world_to_screen(Vector2(10, 0), Vector2.ZERO, 2.0, VIEWPORT)
	_assert_vec_almost_eq(screen, VIEWPORT * 0.5 + Vector2(20, 0), "scaled offset")


func _test_screen_to_world_inverts_world_to_screen() -> void:
	var pan := Vector2(-50, 75)
	var zoom := 1.75
	var world := Vector2(33, -19)
	var screen := EditorCamera.world_to_screen(world, pan, zoom, VIEWPORT)
	_assert_vec_almost_eq(
		EditorCamera.screen_to_world(screen, pan, zoom, VIEWPORT), world, "round-trip"
	)


func _test_screen_centre_is_pan() -> void:
	var pan := Vector2(200, 10)
	_assert_vec_almost_eq(
		EditorCamera.screen_to_world(VIEWPORT * 0.5, pan, 2.0, VIEWPORT), pan, "centre -> pan"
	)


# --- zoom -------------------------------------------------------------------

func _test_clamp_zoom_bounds() -> void:
	assert_almost_eq(EditorCamera.clamp_zoom(0.001), EditorCamera.MIN_ZOOM, "below min")
	assert_almost_eq(EditorCamera.clamp_zoom(999.0), EditorCamera.MAX_ZOOM, "above max")
	assert_almost_eq(EditorCamera.clamp_zoom(1.5), 1.5, "in range")


func _test_apply_zoom_multiplies_and_clamps() -> void:
	assert_almost_eq(EditorCamera.apply_zoom(2.0, 1.5), 3.0, "zoom in")
	assert_almost_eq(EditorCamera.apply_zoom(2.0, 0.5), 1.0, "zoom out")
	# Clamped at the ceiling.
	assert_almost_eq(EditorCamera.apply_zoom(EditorCamera.MAX_ZOOM, 2.0), EditorCamera.MAX_ZOOM, "clamped high")
	assert_almost_eq(EditorCamera.apply_zoom(EditorCamera.MIN_ZOOM, 0.5), EditorCamera.MIN_ZOOM, "clamped low")


# --- pan --------------------------------------------------------------------

func _test_pan_by_screen_delta_moves_content_with_cursor() -> void:
	# Dragging right by 40px at zoom 2 shifts the centre world point 20 units left.
	var pan := EditorCamera.pan_by_screen_delta(Vector2(100, 100), Vector2(40, 0), 2.0)
	_assert_vec_almost_eq(pan, Vector2(80, 100), "drag right")


func _test_pan_drag_keeps_grabbed_world_point_under_cursor() -> void:
	# The whole point of drag-pan: a world point grabbed under the cursor stays
	# under the cursor after the view pans by the same screen delta.
	var pan := Vector2(10, -5)
	var zoom := 1.5
	var cursor := Vector2(300, 220)
	var grabbed := EditorCamera.screen_to_world(cursor, pan, zoom, VIEWPORT)
	var delta := Vector2(25, -15)
	var new_pan := EditorCamera.pan_by_screen_delta(pan, delta, zoom)
	var now_under_cursor := EditorCamera.screen_to_world(cursor + delta, new_pan, zoom, VIEWPORT)
	_assert_vec_almost_eq(now_under_cursor, grabbed, "grabbed point follows cursor")


# --- zoom about cursor ------------------------------------------------------

func _test_zoom_about_screen_point_keeps_point_fixed() -> void:
	var pan := Vector2(40, 60)
	var old_zoom := 1.0
	var new_zoom := 2.0
	var cursor := Vector2(640, 120)
	var world_under := EditorCamera.screen_to_world(cursor, pan, old_zoom, VIEWPORT)
	var new_pan := EditorCamera.zoom_about_screen_point(pan, old_zoom, new_zoom, cursor, VIEWPORT)
	var world_after := EditorCamera.screen_to_world(cursor, new_pan, new_zoom, VIEWPORT)
	_assert_vec_almost_eq(world_after, world_under, "cursor anchor stable")


func _test_zoom_about_centre_leaves_pan_unchanged() -> void:
	# Zooming about the exact centre should not move the pan point.
	var pan := Vector2(7, 13)
	var new_pan := EditorCamera.zoom_about_screen_point(pan, 1.0, 4.0, VIEWPORT * 0.5, VIEWPORT)
	_assert_vec_almost_eq(new_pan, pan, "centre zoom keeps pan")


# --- visible rect -----------------------------------------------------------

func _test_visible_world_rect_centre_and_size() -> void:
	var pan := Vector2(100, 50)
	var zoom := 2.0
	var rect := EditorCamera.visible_world_rect(pan, zoom, VIEWPORT)
	# At zoom 2 the 800x600 viewport shows 400x300 world units, centred on pan.
	_assert_vec_almost_eq(rect.size, Vector2(400, 300), "size")
	_assert_vec_almost_eq(rect.get_center(), pan, "centre")

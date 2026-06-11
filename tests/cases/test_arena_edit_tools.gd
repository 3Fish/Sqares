extends TestCase

## Covers the pure placement/editing maths behind the arena editor's tools (#35):
## grid snapping, rectangle construction from a drag, hit-testing for selection,
## resize-handle geometry, and the resize itself. These helpers are scene-free
## (same convention as `test_editor_camera.gd` / `test_arena_builder.gd`), so the
## decisions the canvas makes on every click can be pinned down directly. The
## mouse/keyboard plumbing and rendering in `ArenaEditorCanvas` are scene concerns
## left to manual/boot verification.

const Tools = preload("res://scripts/ui/arena_edit_tools.gd")
const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")


func _assert_vec(actual: Vector2, expected: Vector2, message: String = "") -> void:
	assert_almost_eq(actual.x, expected.x, "x " + message)
	assert_almost_eq(actual.y, expected.y, "y " + message)


# --- snapping ---------------------------------------------------------------

func _test_snap_rounds_to_nearest_grid_point() -> void:
	_assert_vec(Tools.snap(Vector2(20, -20), 16.0), Vector2(16, -16), "rounds toward nearest")
	_assert_vec(Tools.snap(Vector2(24, 25), 16.0), Vector2(32, 32), "rounds up at/over half")
	_assert_vec(Tools.snap(Vector2(0, 0), 16.0), Vector2.ZERO, "origin stays put")


func _test_snap_disabled_for_nonpositive_spacing() -> void:
	_assert_vec(Tools.snap(Vector2(3, 7), 0.0), Vector2(3, 7), "spacing 0 is a no-op")
	_assert_vec(Tools.snap(Vector2(3, 7), -4.0), Vector2(3, 7), "negative spacing is a no-op")


# --- rect from drag ---------------------------------------------------------

func _test_rect_from_drag_normalises_corners() -> void:
	# Drag bottom-right -> top-left; result is centre + positive size regardless.
	var r := Tools.rect_from_drag(Vector2(100, 80), Vector2(20, 20), Vector2.ZERO)
	_assert_vec(r["position"], Vector2(60, 50), "centre is midpoint")
	_assert_vec(r["size"], Vector2(80, 60), "size is the absolute span")


func _test_rect_from_drag_enforces_minimum_size() -> void:
	var r := Tools.rect_from_drag(Vector2(10, 10), Vector2(12, 12), Tools.MIN_RECT_SIZE)
	_assert_vec(r["size"], Tools.MIN_RECT_SIZE, "tiny drag clamped to minimum")


# --- hit testing ------------------------------------------------------------

func _make_arena() -> ArenaData:
	var a: ArenaData = ArenaDataScript.new()
	a.add_platform(Vector2(0, 0), Vector2(100, 40))      # x:-50..50, y:-20..20
	a.add_platform(Vector2(0, 0), Vector2(20, 20))       # overlaps, drawn on top
	a.add_kill_zone(Vector2(200, 0), Vector2(60, 60))    # x:170..230
	a.add_spawn_point(Vector2(-300, -100))
	a.add_spawn_point(Vector2(300, 100))
	return a


func _test_platform_index_at_picks_topmost() -> void:
	var a := _make_arena()
	# The overlapping region returns the later (index 1) platform — it's on top.
	assert_eq(Tools.platform_index_at(a, Vector2(0, 0)), 1, "topmost platform wins")
	# A point only inside the larger first platform returns index 0.
	assert_eq(Tools.platform_index_at(a, Vector2(40, 0)), 0, "outer platform")
	assert_eq(Tools.platform_index_at(a, Vector2(500, 500)), -1, "empty space -> -1")


func _test_kill_zone_index_at() -> void:
	var a := _make_arena()
	assert_eq(Tools.kill_zone_index_at(a, Vector2(200, 0)), 0, "inside kill zone")
	assert_eq(Tools.kill_zone_index_at(a, Vector2(0, 0)), -1, "outside kill zone")


func _test_spawn_index_at_picks_closest_within_radius() -> void:
	var a := _make_arena()
	assert_eq(Tools.spawn_index_at(a, Vector2(-305, -98), 20.0), 0, "near first spawn")
	assert_eq(Tools.spawn_index_at(a, Vector2(305, 104), 20.0), 1, "near second spawn")
	assert_eq(Tools.spawn_index_at(a, Vector2(0, 0), 20.0), -1, "too far from any spawn")


# --- resize handles ---------------------------------------------------------

func _test_corner_positions() -> void:
	# 100x40 rect centred at origin: corners at (+-50, +-20).
	_assert_vec(Tools.corner(Vector2.ZERO, Vector2(100, 40), Tools.Handle.TOP_LEFT), Vector2(-50, -20), "TL")
	_assert_vec(Tools.corner(Vector2.ZERO, Vector2(100, 40), Tools.Handle.BOTTOM_RIGHT), Vector2(50, 20), "BR")


func _test_handle_at_finds_grabbed_corner() -> void:
	var center := Vector2.ZERO
	var size := Vector2(100, 40)
	# Just off the bottom-right corner, within pick radius.
	assert_eq(Tools.handle_at(center, size, Vector2(52, 21), 6.0), Tools.Handle.BOTTOM_RIGHT, "BR grabbed")
	# Centre of the rect is far from every corner -> NONE.
	assert_eq(Tools.handle_at(center, size, Vector2(0, 0), 6.0), Tools.Handle.NONE, "centre grabs nothing")


func _test_resize_keeps_opposite_corner_fixed() -> void:
	# Drag the top-left corner of a [-50..50, -20..20] rect to (-70, -40);
	# the bottom-right (50, 20) must stay put, growing the rect.
	var result := Tools.resize_rect(Vector2.ZERO, Vector2(100, 40), Tools.Handle.TOP_LEFT, Vector2(-70, -40))
	var rect := Tools.centred_rect(result["position"], result["size"])
	_assert_vec(rect.position, Vector2(-70, -40), "dragged corner moved")
	_assert_vec(rect.end, Vector2(50, 20), "opposite corner fixed")


func _test_resize_with_no_handle_is_identity() -> void:
	var result := Tools.resize_rect(Vector2(5, 5), Vector2(30, 30), Tools.Handle.NONE, Vector2(999, 999))
	_assert_vec(result["position"], Vector2(5, 5), "centre unchanged")
	_assert_vec(result["size"], Vector2(30, 30), "size unchanged")

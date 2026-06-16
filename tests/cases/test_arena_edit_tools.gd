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


# --- property inspector: field capabilities ---------------------------------

func _test_has_size_only_for_rectangles() -> void:
	assert_true(Tools.has_size(Tools.Kind.PLATFORM), "platforms have size")
	assert_true(Tools.has_size(Tools.Kind.KILL_ZONE), "kill zones have size")
	assert_false(Tools.has_size(Tools.Kind.SPAWN), "spawn points are points")
	assert_false(Tools.has_size(Tools.Kind.NONE), "no selection has no size")


func _test_has_color_only_for_platforms() -> void:
	assert_true(Tools.has_color(Tools.Kind.PLATFORM), "platforms have colour")
	assert_false(Tools.has_color(Tools.Kind.KILL_ZONE), "kill zones have no colour field")
	assert_false(Tools.has_color(Tools.Kind.SPAWN), "spawns have no colour field")


func _test_element_exists_validates_kind_and_index() -> void:
	var a := _make_arena()  # 2 platforms, 1 kill zone, 2 spawns
	assert_true(Tools.element_exists(a, Tools.Kind.PLATFORM, 1), "platform 1 exists")
	assert_false(Tools.element_exists(a, Tools.Kind.PLATFORM, 2), "platform 2 out of range")
	assert_true(Tools.element_exists(a, Tools.Kind.KILL_ZONE, 0), "kill zone 0 exists")
	assert_false(Tools.element_exists(a, Tools.Kind.KILL_ZONE, 1), "kill zone 1 out of range")
	assert_true(Tools.element_exists(a, Tools.Kind.SPAWN, 1), "spawn 1 exists")
	assert_false(Tools.element_exists(a, Tools.Kind.SPAWN, -1), "negative index rejected")
	assert_false(Tools.element_exists(a, Tools.Kind.NONE, 0), "NONE kind never exists")
	assert_false(Tools.element_exists(null, Tools.Kind.PLATFORM, 0), "null arena rejected")


# --- property inspector: reads ----------------------------------------------

func _test_element_position_reads_each_kind() -> void:
	var a := _make_arena()
	_assert_vec(Tools.element_position(a, Tools.Kind.PLATFORM, 0), Vector2(0, 0), "platform centre")
	_assert_vec(Tools.element_position(a, Tools.Kind.KILL_ZONE, 0), Vector2(200, 0), "kill zone centre")
	_assert_vec(Tools.element_position(a, Tools.Kind.SPAWN, 0), Vector2(-300, -100), "spawn point")
	_assert_vec(Tools.element_position(a, Tools.Kind.PLATFORM, 9), Vector2.ZERO, "invalid -> ZERO")


func _test_element_size_only_for_rectangles() -> void:
	var a := _make_arena()
	_assert_vec(Tools.element_size(a, Tools.Kind.PLATFORM, 0), Vector2(100, 40), "platform size")
	_assert_vec(Tools.element_size(a, Tools.Kind.KILL_ZONE, 0), Vector2(60, 60), "kill zone size")
	_assert_vec(Tools.element_size(a, Tools.Kind.SPAWN, 0), Vector2.ZERO, "spawn has no size")


func _test_element_color_only_for_platforms() -> void:
	var a: ArenaData = ArenaDataScript.new()
	a.add_platform(Vector2.ZERO, Vector2(64, 16), Color(0.2, 0.4, 0.6, 1.0))
	a.add_kill_zone(Vector2(0, 0), Vector2(32, 32))
	assert_eq(Tools.element_color(a, Tools.Kind.PLATFORM, 0), Color(0.2, 0.4, 0.6, 1.0), "platform colour")
	assert_eq(Tools.element_color(a, Tools.Kind.KILL_ZONE, 0), Color.WHITE, "kill zone -> WHITE default")


# --- property inspector: writes ---------------------------------------------

func _test_set_element_position_moves_each_kind() -> void:
	var a := _make_arena()
	assert_true(Tools.set_element_position(a, Tools.Kind.PLATFORM, 0, Vector2(11, 22)), "applied")
	_assert_vec(a.platforms[0]["position"], Vector2(11, 22), "platform moved")
	assert_true(Tools.set_element_position(a, Tools.Kind.SPAWN, 1, Vector2(7, -7)), "applied")
	_assert_vec(a.spawn_points[1], Vector2(7, -7), "spawn moved")
	assert_false(Tools.set_element_position(a, Tools.Kind.KILL_ZONE, 5, Vector2(1, 1)), "invalid index no-op")


func _test_set_element_size_clamps_to_minimum() -> void:
	var a := _make_arena()
	assert_true(Tools.set_element_size(a, Tools.Kind.PLATFORM, 0, Vector2(200, 8)), "applied")
	# Width kept; height floored to the minimum rectangle extent.
	_assert_vec(a.platforms[0]["size"], Vector2(200, Tools.MIN_RECT_SIZE.y), "height clamped")
	assert_false(Tools.set_element_size(a, Tools.Kind.SPAWN, 0, Vector2(50, 50)), "spawns have no size")


func _test_set_element_color_only_on_platforms() -> void:
	var a := _make_arena()
	assert_true(Tools.set_element_color(a, Tools.Kind.PLATFORM, 0, Color.RED), "applied")
	assert_eq(a.platforms[0]["color"], Color.RED, "platform recoloured")
	assert_false(Tools.set_element_color(a, Tools.Kind.KILL_ZONE, 0, Color.RED), "kill zone has no colour")


# --- selection validation (#79) ---------------------------------------------

func _test_selection_exists_validates_platform_index() -> void:
	var a := ArenaDataScript.new().add_platform(Vector2.ZERO, Vector2(32, 32))
	assert_true(Tools.selection_exists(a, Tools.Kind.PLATFORM, 0), "in-range platform")
	assert_false(Tools.selection_exists(a, Tools.Kind.PLATFORM, 1), "out-of-range platform")
	assert_false(Tools.selection_exists(a, Tools.Kind.PLATFORM, -1), "negative index")


func _test_selection_exists_validates_spawn_and_kill_zone() -> void:
	var a := ArenaDataScript.new()
	a.add_spawn_point(Vector2(10, 10))
	a.add_kill_zone(Vector2.ZERO, Vector2(64, 16))
	assert_true(Tools.selection_exists(a, Tools.Kind.SPAWN, 0), "spawn 0 exists")
	assert_true(Tools.selection_exists(a, Tools.Kind.KILL_ZONE, 0), "kill zone 0 exists")
	assert_false(Tools.selection_exists(a, Tools.Kind.SPAWN, 1), "no spawn 1")
	assert_false(Tools.selection_exists(a, Tools.Kind.KILL_ZONE, 1), "no kill zone 1")


func _test_selection_exists_rejects_none_kind_and_null_arena() -> void:
	var a := ArenaDataScript.new().add_platform(Vector2.ZERO, Vector2(32, 32))
	assert_false(Tools.selection_exists(a, Tools.Kind.NONE, 0), "NONE kind is not a selection")
	assert_false(Tools.selection_exists(null, Tools.Kind.PLATFORM, 0), "null arena is never selectable")


func _test_selection_exists_false_after_element_removed() -> void:
	var a := ArenaDataScript.new().add_platform(Vector2.ZERO, Vector2(32, 32))
	assert_true(Tools.selection_exists(a, Tools.Kind.PLATFORM, 0), "exists before removal")
	a.remove_platform(0)
	assert_false(Tools.selection_exists(a, Tools.Kind.PLATFORM, 0), "index gone after removal")

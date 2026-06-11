extends TestCase

## Covers the arena editor canvas's pure framing maths (#34) — the content
## bounds that `frame_content` centres the view on. The drawing and input
## handling are scene/render concerns left to manual/visual verification, but the
## bounds computation is plain geometry and worth pinning down.

var _canvas: ArenaEditorCanvas


func before_each() -> void:
	_canvas = ArenaEditorCanvas.new()


func after_each() -> void:
	_canvas.free()


func _test_centred_rect_places_corner_from_centre() -> void:
	# A 40x20 rect centred at (100, 50) spans (80,40)..(120,60).
	var r := ArenaEditorCanvas._centred_rect(Vector2(100, 50), Vector2(40, 20))
	assert_almost_eq(r.position.x, 80.0, "x")
	assert_almost_eq(r.position.y, 40.0, "y")
	assert_almost_eq(r.get_center().x, 100.0, "cx")
	assert_almost_eq(r.get_center().y, 50.0, "cy")


func _test_content_bounds_empty_is_zero_rect() -> void:
	_canvas.set_arena(ArenaData.new())
	var b := _canvas._content_bounds()
	assert_eq(b, Rect2(), "empty arena -> zero rect")


func _test_content_bounds_encloses_all_elements() -> void:
	var data := ArenaData.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))   # x: -50..50, y: -10..10
	data.add_spawn_point(Vector2(200, -120))             # point
	data.add_kill_zone(Vector2(-60, 80), Vector2(40, 40)) # x: -80..-40, y: 60..100
	_canvas.set_arena(data)
	var b := _canvas._content_bounds()
	assert_almost_eq(b.position.x, -80.0, "min x (kill zone left)")
	assert_almost_eq(b.position.y, -120.0, "min y (spawn)")
	assert_almost_eq(b.end.x, 200.0, "max x (spawn)")
	assert_almost_eq(b.end.y, 100.0, "max y (kill zone bottom)")

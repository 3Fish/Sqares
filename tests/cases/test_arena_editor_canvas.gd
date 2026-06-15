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


# --- Undo/redo gesture wiring (#72) ------------------------------------------

func _test_click_place_is_one_undoable_step() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.set_tool(ArenaEditTools.Tool.PLATFORM)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	_canvas._on_left_release(Vector2.ZERO, Vector2.ZERO)
	assert_eq(_canvas.arena.platforms.size(), 1, "click placed a platform")
	assert_true(_canvas.undo(), "placement is undoable")
	assert_eq(_canvas.arena.platforms.size(), 0, "undo removed the platform")
	assert_false(_canvas.history.can_undo(), "one gesture = one step")
	assert_true(_canvas.redo(), "undone placement is redoable")
	assert_eq(_canvas.arena.platforms.size(), 1, "redo restored the platform")


func _test_select_click_on_empty_space_records_no_step() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.set_tool(ArenaEditTools.Tool.SELECT)
	_canvas._on_left_press(Vector2(320, 320), Vector2(50, 50))
	_canvas._on_left_release(Vector2(320, 320), Vector2(50, 50))
	assert_false(_canvas.history.can_undo(), "selection-only click is not an edit")
	assert_false(_canvas.undo(), "nothing to undo")


func _test_drag_move_is_a_single_step_and_undo_restores_position() -> void:
	var data := ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64))
	_canvas.set_arena(data)
	_canvas.set_tool(ArenaEditTools.Tool.SELECT)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	# Two motion updates within one drag must still collapse into one step.
	_canvas._apply_move(Vector2(64, 0))
	_canvas._apply_move(Vector2(128, 32))
	_canvas._on_left_release(Vector2(128, 32), Vector2(200, 200))
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2(128, 32), "drag moved the platform")
	assert_true(_canvas.undo(), "move is undoable")
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2.ZERO, "undo restored the position")
	assert_false(_canvas.history.can_undo(), "whole drag was one step")


func _test_delete_selected_is_undoable() -> void:
	var data := ArenaData.new().add_spawn_point(Vector2(32, -16))
	_canvas.set_arena(data)
	_canvas._select(ArenaEditTools.Kind.SPAWN, 0)
	assert_true(_canvas.delete_selected(), "delete removed the spawn")
	assert_eq(_canvas.arena.spawn_points.size(), 0, "spawn gone")
	assert_true(_canvas.undo(), "delete is undoable")
	assert_eq(_canvas.arena.spawn_points.size(), 1, "undo restored the spawn")
	assert_eq(_canvas.arena.spawn_points[0], Vector2(32, -16), "restored at its position")


func _test_two_gestures_are_two_steps() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.set_tool(ArenaEditTools.Tool.SPAWN)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	_canvas._on_left_release(Vector2.ZERO, Vector2.ZERO)
	_canvas._on_left_press(Vector2(64, 0), Vector2(10, 0))
	_canvas._on_left_release(Vector2(64, 0), Vector2(10, 0))
	assert_eq(_canvas.arena.spawn_points.size(), 2, "two spawns placed")
	assert_true(_canvas.undo(), "second placement undone")
	assert_eq(_canvas.arena.spawn_points.size(), 1, "back to one spawn")
	assert_true(_canvas.undo(), "first placement undone")
	assert_eq(_canvas.arena.spawn_points.size(), 0, "back to empty")
	assert_false(_canvas.undo(), "no further steps")


func _test_set_arena_resets_history() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.set_tool(ArenaEditTools.Tool.SPAWN)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	_canvas._on_left_release(Vector2.ZERO, Vector2.ZERO)
	assert_true(_canvas.history.can_undo(), "edit recorded on old document")
	_canvas.set_arena(ArenaData.new())
	assert_false(_canvas.history.can_undo(), "New/Load starts a fresh history")
	assert_false(_canvas.undo(), "nothing to undo on the new document")


func _test_undo_refused_during_active_gesture() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.set_tool(ArenaEditTools.Tool.PLATFORM)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	assert_false(_canvas.undo(), "undo refused while rubber-banding")
	assert_false(_canvas.redo(), "redo refused while rubber-banding")
	_canvas._on_left_release(Vector2(160, 64), Vector2(300, 120))
	assert_true(_canvas.undo(), "undo works again once the gesture ended")


func _test_tool_switch_mid_drag_commits_the_applied_edit() -> void:
	var data := ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64))
	_canvas.set_arena(data)
	_canvas.set_tool(ArenaEditTools.Tool.SELECT)
	_canvas._on_left_press(Vector2.ZERO, Vector2.ZERO)
	_canvas._apply_move(Vector2(96, 0))
	# Switching tools cancels the drag but must keep the applied move undoable.
	_canvas.set_tool(ArenaEditTools.Tool.SPAWN)
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2(96, 0), "move stayed applied")
	assert_true(_canvas.undo(), "interrupted drag is one undoable step")
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2.ZERO, "undo restored the position")


# --- property inspector edits (#72) -----------------------------------------

func _test_set_selected_position_is_one_undoable_step() -> void:
	var data := ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64))
	_canvas.set_arena(data)
	_canvas._select(ArenaEditTools.Kind.PLATFORM, 0)
	assert_true(_canvas.set_selected_position(Vector2(48, -16)), "edit applied")
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2(48, -16), "platform moved")
	assert_true(_canvas.undo(), "inspector edit is undoable")
	assert_eq(_canvas.arena.platforms[0]["position"], Vector2.ZERO, "undo restored position")
	assert_false(_canvas.history.can_undo(), "one field edit = one step")


func _test_set_selected_size_clamps_and_commits() -> void:
	var data := ArenaData.new().add_kill_zone(Vector2.ZERO, Vector2(64, 64))
	_canvas.set_arena(data)
	_canvas._select(ArenaEditTools.Kind.KILL_ZONE, 0)
	assert_true(_canvas.set_selected_size(Vector2(120, 4)), "edit applied")
	# Height floored to the minimum rect extent.
	assert_eq(_canvas.arena.kill_zones[0]["size"], Vector2(120, ArenaEditTools.MIN_RECT_SIZE.y), "size clamped")
	assert_true(_canvas.undo(), "size edit is undoable")
	assert_eq(_canvas.arena.kill_zones[0]["size"], Vector2(64, 64), "undo restored size")


func _test_set_selected_color_only_affects_platforms() -> void:
	var data := ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64), Color.WHITE)
	data.add_kill_zone(Vector2(200, 0), Vector2(32, 32))
	_canvas.set_arena(data)
	_canvas._select(ArenaEditTools.Kind.PLATFORM, 0)
	assert_true(_canvas.set_selected_color(Color.RED), "platform recolour applied")
	assert_eq(_canvas.arena.platforms[0]["color"], Color.RED, "platform colour changed")
	# A kill zone has no colour field, so the edit is a no-op (and records nothing).
	_canvas._select(ArenaEditTools.Kind.KILL_ZONE, 0)
	assert_false(_canvas.set_selected_color(Color.BLUE), "kill zone has no colour")


func _test_inspector_edit_with_no_selection_is_noop() -> void:
	_canvas.set_arena(ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64)))
	_canvas._clear_selection()
	assert_false(_canvas.set_selected_position(Vector2(10, 10)), "no selection -> no edit")
	assert_false(_canvas.history.can_undo(), "nothing recorded")


func _test_identical_inspector_value_records_no_step() -> void:
	var data := ArenaData.new().add_platform(Vector2(32, 32), Vector2(64, 64))
	_canvas.set_arena(data)
	_canvas._select(ArenaEditTools.Kind.PLATFORM, 0)
	# Re-applying the same position is "applicable" but changes nothing.
	assert_true(_canvas.set_selected_position(Vector2(32, 32)), "setter reports applicable")
	assert_false(_canvas.history.can_undo(), "no-op edit records no undo step")


func _test_select_emits_selection_changed() -> void:
	var data := ArenaData.new().add_platform(Vector2.ZERO, Vector2(64, 64))
	_canvas.set_arena(data)
	var seen: Array = []
	_canvas.selection_changed.connect(func(kind: int, index: int) -> void: seen.append([kind, index]))
	_canvas._select(ArenaEditTools.Kind.PLATFORM, 0)
	assert_eq(seen.size(), 1, "one emission on a real selection change")
	assert_eq(seen[0][0], ArenaEditTools.Kind.PLATFORM, "kind reported")
	assert_eq(seen[0][1], 0, "index reported")
	# Re-selecting the same element must not re-emit.
	_canvas._select(ArenaEditTools.Kind.PLATFORM, 0)
	assert_eq(seen.size(), 1, "no emission when selection is unchanged")
	_canvas._clear_selection()
	assert_eq(seen.size(), 2, "clearing a live selection emits NONE")
	assert_eq(seen[1][0], ArenaEditTools.Kind.NONE, "cleared kind is NONE")

extends Control
class_name ArenaEditorCanvas

## The arena editor's drawing surface: a pannable, zoomable grid that renders the
## current `ArenaData` (platforms, spawn points, kill zones) and hosts the
## placement/editing tools (#35). The shell (#34) added view + camera; this layer
## adds left-mouse interaction: add / move / delete / resize platforms and kill
## zones, and place spawn points.
##
## All coordinate maths go through the pure `EditorCamera` helpers and all
## placement decisions through the pure `ArenaEditTools` helpers, so the view and
## the (tested) maths cannot drift.

## Emitted whenever the arena geometry changes (place / move / resize / delete),
## so the editor can update its status line / dirty state.
signal arena_modified

## World-space spacing of the background grid, in pixels-at-zoom-1.
const GRID_SPACING: float = 64.0
## Above this many grid lines on screen the grid is skipped (too dense to read).
const MAX_GRID_LINES: int = 400
## How much one mouse-wheel notch multiplies / divides the zoom.
const ZOOM_STEP: float = 1.15
## Beyond this many screen pixels a left press-drag counts as a drag (vs a click).
const DRAG_THRESHOLD_PX: float = 4.0
## Half-size, in screen pixels, of the square resize handles drawn on a selection.
const HANDLE_PX: float = 5.0
## Screen-pixel pick radius for grabbing a resize handle or a spawn point.
const PICK_PX: float = 9.0

const COLOR_GRID := Color(1, 1, 1, 0.06)
const COLOR_AXIS := Color(1, 1, 1, 0.18)
const COLOR_PLATFORM_OUTLINE := Color(1, 1, 1, 0.35)
const COLOR_SPAWN := Color(0.4, 0.9, 0.5, 0.95)
const COLOR_KILLZONE := Color(0.9, 0.25, 0.25, 0.28)
const COLOR_KILLZONE_OUTLINE := Color(0.95, 0.35, 0.35, 0.8)
const COLOR_SELECT := Color(1.0, 0.85, 0.2, 0.95)
const COLOR_PREVIEW := Color(1.0, 1.0, 1.0, 0.5)

## Camera state. `pan` is the world point shown at the canvas centre.
var pan: Vector2 = Vector2.ZERO
var zoom: float = 1.0

## The arena currently being viewed/edited. Never null after `_ready`.
var arena: ArenaData = ArenaData.new()

## The active placement tool (`ArenaEditTools.Tool`).
var tool: int = ArenaEditTools.Tool.SELECT

## Gesture-level undo/redo history (#72). One completed edit gesture (a
## click-place, a press→release drag, a delete) is one undo step.
var history: EditorUndoHistory = EditorUndoHistory.new()

## Current selection (`ArenaEditTools.Kind` + element index).
var sel_kind: int = ArenaEditTools.Kind.NONE
var sel_index: int = -1

var _panning: bool = false

# Left-drag interaction state.
var _drawing: bool = false          ## Rubber-banding a new platform / kill zone.
var _draw_start: Vector2 = Vector2.ZERO
var _draw_current: Vector2 = Vector2.ZERO
var _moving: bool = false           ## Dragging the selected element.
var _move_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false         ## Dragging a resize handle of the selection.
var _resize_handle: int = ArenaEditTools.Handle.NONE
var _press_screen: Vector2 = Vector2.ZERO
## Snapshot taken when an edit gesture begins; committed as one undo step at
## gesture end if the gesture actually changed the arena.
var _gesture_before: Dictionary = {}
## Selection active when the gesture began, recorded alongside `_gesture_before`
## so undo can restore the pre-edit selection (#79).
var _gesture_before_sel: Dictionary = {}


func _ready() -> void:
	# FOCUS_CLICK lets the canvas receive the Delete key once clicked.
	focus_mode = Control.FOCUS_CLICK


func set_arena(new_arena: ArenaData) -> void:
	arena = new_arena if new_arena != null else ArenaData.new()
	_clear_selection()
	# History is per-document: replacing the arena (New / Load) resets it.
	history.clear()
	_gesture_before = {}
	_gesture_before_sel = {}
	queue_redraw()


## Switch the active placement tool, cancelling any in-progress drag.
func set_tool(new_tool: int) -> void:
	tool = new_tool
	_cancel_drag()
	queue_redraw()


## Delete the current selection, if any. Returns true when something was removed.
func delete_selected() -> bool:
	var before := arena.to_dict()
	var before_sel := _current_selection()
	match sel_kind:
		ArenaEditTools.Kind.PLATFORM: arena.remove_platform(sel_index)
		ArenaEditTools.Kind.SPAWN: arena.remove_spawn_point(sel_index)
		ArenaEditTools.Kind.KILL_ZONE: arena.remove_kill_zone(sel_index)
		_: return false
	# Inside an open press→release gesture the commit at gesture end already
	# captures this change; pushing here too would record a duplicate step.
	if _gesture_before.is_empty():
		history.push_if_changed(before, arena.to_dict(), before_sel)
	_clear_selection()
	arena_modified.emit()
	queue_redraw()
	return true


## Revert the last committed edit. Returns true when a step was applied.
func undo() -> bool:
	if _drawing or _moving or _resizing:
		return false
	return _apply_history_state(history.undo(arena.to_dict(), _current_selection()))


## Re-apply the last undone edit. Returns true when a step was applied.
func redo() -> bool:
	if _drawing or _moving or _resizing:
		return false
	return _apply_history_state(history.redo(arena.to_dict(), _current_selection()))


func _apply_history_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	arena = ArenaData.from_dict(state)
	# Restore the selection recorded with this step (#79). The element it points
	# at may not exist in the restored state, so validate before reapplying and
	# fall back to no selection otherwise.
	_restore_selection(history.restored_selection)
	arena_modified.emit()
	queue_redraw()
	return true


## The current selection as a `{ "kind", "index" }` dictionary, for recording
## with an undo step.
func _current_selection() -> Dictionary:
	return {"kind": sel_kind, "index": sel_index}


## Reapply a selection recorded on an undo step, dropping it when the element no
## longer exists in the (just-restored) arena.
func _restore_selection(sel: Dictionary) -> void:
	var kind: int = sel.get("kind", ArenaEditTools.Kind.NONE)
	var index: int = sel.get("index", -1)
	if ArenaEditTools.selection_exists(arena, kind, index):
		_select(kind, index)
	else:
		_clear_selection()


## Centre the view on the arena's content (or the origin when it's empty).
func frame_content() -> void:
	if arena.platforms.is_empty() and arena.spawn_points.is_empty() and arena.kill_zones.is_empty():
		pan = Vector2.ZERO
		zoom = 1.0
	else:
		var bounds := _content_bounds()
		pan = bounds.get_center()
	queue_redraw()


# --- Input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		if key.is_command_or_control_pressed() and key.keycode == KEY_Z:
			if key.shift_pressed:
				redo()
			else:
				undo()
		elif key.is_command_or_control_pressed() and key.keycode == KEY_Y:
			redo()
		elif key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
			delete_selected()


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_at(mb.position, ZOOM_STEP)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_at(mb.position, 1.0 / ZOOM_STEP)
	elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
		# Middle / right drag pans; left is the placement / editing button.
		_panning = mb.pressed
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			grab_focus()
			_on_left_press(_to_world(mb.position), mb.position)
		else:
			_on_left_release(_to_world(mb.position), mb.position)


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if _panning:
		pan = EditorCamera.pan_by_screen_delta(pan, mm.relative, zoom)
		queue_redraw()
		return
	var world := _to_world(mm.position)
	if _drawing:
		_draw_current = ArenaEditTools.snap(world)
		queue_redraw()
	elif _resizing:
		_apply_resize(world)
	elif _moving:
		_apply_move(world)


func _on_left_press(world: Vector2, screen: Vector2) -> void:
	_press_screen = screen
	# Snapshot for undo; committed at gesture end only if something changed.
	_gesture_before = arena.to_dict()
	_gesture_before_sel = _current_selection()
	match tool:
		ArenaEditTools.Tool.SPAWN:
			arena.add_spawn_point(ArenaEditTools.snap(world))
			_select(ArenaEditTools.Kind.SPAWN, arena.spawn_points.size() - 1)
			arena_modified.emit()
		ArenaEditTools.Tool.PLATFORM, ArenaEditTools.Tool.KILL_ZONE:
			_drawing = true
			_draw_start = ArenaEditTools.snap(world)
			_draw_current = _draw_start
		_:
			_begin_select_or_grab(world)
	queue_redraw()


func _on_left_release(world: Vector2, screen: Vector2) -> void:
	if _drawing:
		_commit_drawn_rect(world, screen)
	_drawing = false
	_moving = false
	_resizing = false
	_resize_handle = ArenaEditTools.Handle.NONE
	_commit_gesture()
	queue_redraw()


## On a SELECT-tool press: grab a resize handle of the current selection, else
## hit-test for a new selection (and start moving it), else clear the selection.
func _begin_select_or_grab(world: Vector2) -> void:
	var geom := _selected_rect()
	if not geom.is_empty():
		var handle := ArenaEditTools.handle_at(geom.position, geom.size, world, PICK_PX / zoom)
		if handle != ArenaEditTools.Handle.NONE:
			_resizing = true
			_resize_handle = handle
			return

	var p := ArenaEditTools.platform_index_at(arena, world)
	if p != -1:
		_select(ArenaEditTools.Kind.PLATFORM, p)
		_start_move(world)
		return
	var k := ArenaEditTools.kill_zone_index_at(arena, world)
	if k != -1:
		_select(ArenaEditTools.Kind.KILL_ZONE, k)
		_start_move(world)
		return
	var s := ArenaEditTools.spawn_index_at(arena, world, PICK_PX / zoom)
	if s != -1:
		_select(ArenaEditTools.Kind.SPAWN, s)
		_start_move(world)
		return
	_clear_selection()


func _start_move(world: Vector2) -> void:
	_moving = true
	_move_offset = _selected_center() - world


func _apply_move(world: Vector2) -> void:
	var center := ArenaEditTools.snap(world + _move_offset)
	match sel_kind:
		ArenaEditTools.Kind.PLATFORM: arena.platforms[sel_index]["position"] = center
		ArenaEditTools.Kind.KILL_ZONE: arena.kill_zones[sel_index]["position"] = center
		ArenaEditTools.Kind.SPAWN: arena.spawn_points[sel_index] = center
		_: return
	arena_modified.emit()
	queue_redraw()


func _apply_resize(world: Vector2) -> void:
	var geom := _selected_rect()
	if geom.is_empty():
		return
	var snapped := ArenaEditTools.snap(world)
	var result := ArenaEditTools.resize_rect(geom.position, geom.size, _resize_handle, snapped)
	match sel_kind:
		ArenaEditTools.Kind.PLATFORM:
			arena.platforms[sel_index]["position"] = result["position"]
			arena.platforms[sel_index]["size"] = result["size"]
		ArenaEditTools.Kind.KILL_ZONE:
			arena.kill_zones[sel_index]["position"] = result["position"]
			arena.kill_zones[sel_index]["size"] = result["size"]
		_: return
	arena_modified.emit()
	queue_redraw()


func _commit_drawn_rect(world: Vector2, screen: Vector2) -> void:
	var end := ArenaEditTools.snap(world)
	var rect: Dictionary
	# A click without a meaningful drag drops a default-sized rectangle.
	if _press_screen.distance_to(screen) <= DRAG_THRESHOLD_PX:
		rect = {"position": _draw_start, "size": ArenaEditTools.DEFAULT_RECT_SIZE}
	else:
		rect = ArenaEditTools.rect_from_drag(_draw_start, end)
	if tool == ArenaEditTools.Tool.KILL_ZONE:
		arena.add_kill_zone(rect["position"], rect["size"])
		_select(ArenaEditTools.Kind.KILL_ZONE, arena.kill_zones.size() - 1)
	else:
		arena.add_platform(rect["position"], rect["size"])
		_select(ArenaEditTools.Kind.PLATFORM, arena.platforms.size() - 1)
	arena_modified.emit()


# --- Selection helpers ------------------------------------------------------

func _select(kind: int, index: int) -> void:
	sel_kind = kind
	sel_index = index


func _clear_selection() -> void:
	sel_kind = ArenaEditTools.Kind.NONE
	sel_index = -1


func _cancel_drag() -> void:
	_drawing = false
	_moving = false
	_resizing = false
	_resize_handle = ArenaEditTools.Handle.NONE
	# A tool switch mid-drag leaves the moves applied; close the gesture so the
	# applied portion is still a single undoable step.
	_commit_gesture()


## Commit the gesture-start snapshot as one undo step if the gesture changed
## the arena (a click that only selected something commits nothing).
func _commit_gesture() -> void:
	if _gesture_before.is_empty():
		return
	history.push_if_changed(_gesture_before, arena.to_dict(), _gesture_before_sel)
	_gesture_before = {}
	_gesture_before_sel = {}


## Centre of the current selection, or ZERO when nothing valid is selected.
func _selected_center() -> Vector2:
	match sel_kind:
		ArenaEditTools.Kind.PLATFORM:
			return arena.platforms[sel_index].get("position", Vector2.ZERO)
		ArenaEditTools.Kind.KILL_ZONE:
			return arena.kill_zones[sel_index].get("position", Vector2.ZERO)
		ArenaEditTools.Kind.SPAWN:
			return arena.spawn_points[sel_index]
	return Vector2.ZERO


## Centre+size of the selected rectangle as a `{position, size}` Dictionary, or
## an empty Dictionary when the selection is not a resizable rectangle.
func _selected_rect() -> Dictionary:
	if sel_index < 0:
		return {}
	match sel_kind:
		ArenaEditTools.Kind.PLATFORM:
			var p: Dictionary = arena.platforms[sel_index]
			return {"position": p.get("position", Vector2.ZERO), "size": p.get("size", Vector2.ZERO)}
		ArenaEditTools.Kind.KILL_ZONE:
			var k: Dictionary = arena.kill_zones[sel_index]
			return {"position": k.get("position", Vector2.ZERO), "size": k.get("size", Vector2.ZERO)}
	return {}


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var new_zoom := EditorCamera.apply_zoom(zoom, factor)
	if is_equal_approx(new_zoom, zoom):
		return
	pan = EditorCamera.zoom_about_screen_point(pan, zoom, new_zoom, screen_point, size)
	zoom = new_zoom
	queue_redraw()


func _to_world(screen: Vector2) -> Vector2:
	return EditorCamera.screen_to_world(screen, pan, zoom, size)


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), arena.background_color)
	_draw_grid()
	_draw_kill_zones()
	_draw_platforms()
	_draw_spawn_points()
	_draw_selection()
	_draw_preview()


func _draw_grid() -> void:
	var rect := EditorCamera.visible_world_rect(pan, zoom, size)
	# Too many lines to be legible (e.g. zoomed far out): skip rather than churn.
	if (rect.size.x + rect.size.y) / GRID_SPACING > MAX_GRID_LINES:
		return
	var start_x := floorf(rect.position.x / GRID_SPACING) * GRID_SPACING
	var x := start_x
	while x <= rect.end.x:
		var sx := EditorCamera.world_to_screen(Vector2(x, 0), pan, zoom, size).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), COLOR_AXIS if is_zero_approx(x) else COLOR_GRID)
		x += GRID_SPACING
	var start_y := floorf(rect.position.y / GRID_SPACING) * GRID_SPACING
	var y := start_y
	while y <= rect.end.y:
		var sy := EditorCamera.world_to_screen(Vector2(0, y), pan, zoom, size).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), COLOR_AXIS if is_zero_approx(y) else COLOR_GRID)
		y += GRID_SPACING


func _draw_platforms() -> void:
	for p in arena.platforms:
		var screen_rect := _world_rect_to_screen(p.get("position", Vector2.ZERO), p.get("size", Vector2.ZERO))
		var color: Color = p.get("color", Color(0.3, 0.3, 0.45, 1.0))
		draw_rect(screen_rect, color)
		draw_rect(screen_rect, COLOR_PLATFORM_OUTLINE, false, 1.0)


func _draw_kill_zones() -> void:
	for k in arena.kill_zones:
		var screen_rect := _world_rect_to_screen(k.get("position", Vector2.ZERO), k.get("size", Vector2.ZERO))
		draw_rect(screen_rect, COLOR_KILLZONE)
		draw_rect(screen_rect, COLOR_KILLZONE_OUTLINE, false, 1.0)


func _draw_spawn_points() -> void:
	var radius := maxf(4.0, 10.0 * zoom)
	for i in arena.spawn_points.size():
		var center := EditorCamera.world_to_screen(arena.spawn_points[i], pan, zoom, size)
		draw_circle(center, radius, COLOR_SPAWN)
		draw_circle(center, radius, Color(0, 0, 0, 0.5), false, 1.0)


## Outline the current selection and, for rectangles, draw corner resize handles.
func _draw_selection() -> void:
	if sel_kind == ArenaEditTools.Kind.SPAWN:
		var c := EditorCamera.world_to_screen(_selected_center(), pan, zoom, size)
		var r := maxf(4.0, 10.0 * zoom) + 3.0
		draw_circle(c, r, COLOR_SELECT, false, 2.0)
		return
	var geom := _selected_rect()
	if geom.is_empty():
		return
	var screen_rect := _world_rect_to_screen(geom.position, geom.size)
	draw_rect(screen_rect, COLOR_SELECT, false, 2.0)
	for h in [ArenaEditTools.Handle.TOP_LEFT, ArenaEditTools.Handle.TOP_RIGHT,
			ArenaEditTools.Handle.BOTTOM_LEFT, ArenaEditTools.Handle.BOTTOM_RIGHT]:
		var corner_world: Vector2 = ArenaEditTools.corner(geom.position, geom.size, h)
		var corner_screen := EditorCamera.world_to_screen(corner_world, pan, zoom, size)
		draw_rect(Rect2(corner_screen - Vector2(HANDLE_PX, HANDLE_PX), Vector2(HANDLE_PX, HANDLE_PX) * 2.0), COLOR_SELECT)


## While rubber-banding a new platform / kill zone, preview its outline.
func _draw_preview() -> void:
	if not _drawing:
		return
	var rect: Dictionary = ArenaEditTools.rect_from_drag(_draw_start, _draw_current, Vector2.ZERO)
	var screen_rect := _world_rect_to_screen(rect["position"], rect["size"])
	draw_rect(screen_rect, COLOR_PREVIEW, false, 1.0)


## Convert a centred world rectangle (centre + full size) into a screen-space Rect2.
func _world_rect_to_screen(center: Vector2, world_size: Vector2) -> Rect2:
	var top_left := EditorCamera.world_to_screen(center - world_size * 0.5, pan, zoom, size)
	return Rect2(top_left, world_size * zoom)


func _content_bounds() -> Rect2:
	var rects: Array[Rect2] = []
	for p in arena.platforms:
		rects.append(_centred_rect(p.get("position", Vector2.ZERO), p.get("size", Vector2.ZERO)))
	for k in arena.kill_zones:
		rects.append(_centred_rect(k.get("position", Vector2.ZERO), k.get("size", Vector2.ZERO)))
	for s in arena.spawn_points:
		rects.append(Rect2(s, Vector2.ZERO))
	if rects.is_empty():
		return Rect2()
	var bounds := rects[0]
	for i in range(1, rects.size()):
		bounds = bounds.merge(rects[i])
	return bounds


static func _centred_rect(center: Vector2, world_size: Vector2) -> Rect2:
	return Rect2(center - world_size * 0.5, world_size)

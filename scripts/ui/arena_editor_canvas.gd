extends Control
class_name ArenaEditorCanvas

## The arena editor's drawing surface: a pannable, zoomable grid that renders the
## current `ArenaData` (platforms, spawn points, kill zones). This is the "shell"
## canvas (#34) — it views the arena and owns the camera; the placement/editing
## tools that mutate the geometry are #35. All coordinate maths go through the
## pure `EditorCamera` helpers so the view and the (tested) maths cannot drift.

## World-space spacing of the background grid, in pixels-at-zoom-1.
const GRID_SPACING: float = 64.0
## Above this many grid lines on screen the grid is skipped (too dense to read).
const MAX_GRID_LINES: int = 400
## How much one mouse-wheel notch multiplies / divides the zoom.
const ZOOM_STEP: float = 1.15

const COLOR_GRID := Color(1, 1, 1, 0.06)
const COLOR_AXIS := Color(1, 1, 1, 0.18)
const COLOR_PLATFORM_OUTLINE := Color(1, 1, 1, 0.35)
const COLOR_SPAWN := Color(0.4, 0.9, 0.5, 0.95)
const COLOR_KILLZONE := Color(0.9, 0.25, 0.25, 0.28)
const COLOR_KILLZONE_OUTLINE := Color(0.95, 0.35, 0.35, 0.8)

## Camera state. `pan` is the world point shown at the canvas centre.
var pan: Vector2 = Vector2.ZERO
var zoom: float = 1.0

## The arena currently being viewed/edited. Never null after `_ready`.
var arena: ArenaData = ArenaData.new()

var _panning: bool = false


func set_arena(new_arena: ArenaData) -> void:
	arena = new_arena if new_arena != null else ArenaData.new()
	queue_redraw()


## Centre the view on the arena's content (or the origin when it's empty).
func frame_content() -> void:
	if arena.platforms.is_empty() and arena.spawn_points.is_empty() and arena.kill_zones.is_empty():
		pan = Vector2.ZERO
		zoom = 1.0
	else:
		var bounds := _content_bounds()
		pan = bounds.get_center()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			# Middle / right drag pans; left stays free for placement tools (#35).
			_panning = mb.pressed
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		pan = EditorCamera.pan_by_screen_delta(pan, mm.relative, zoom)
		queue_redraw()


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var new_zoom := EditorCamera.apply_zoom(zoom, factor)
	if is_equal_approx(new_zoom, zoom):
		return
	pan = EditorCamera.zoom_about_screen_point(pan, zoom, new_zoom, screen_point, size)
	zoom = new_zoom
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), arena.background_color)
	_draw_grid()
	_draw_kill_zones()
	_draw_platforms()
	_draw_spawn_points()


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

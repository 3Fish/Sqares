extends RefCounted
class_name EditorCamera

## Pure pan/zoom + coordinate math for the arena editor canvas.
##
## All methods are static and scene-free (no Node/Camera2D dependency) so they
## can be unit-tested directly, following the same pattern as
## `MatchDirector.resolve_spawn_positions`. The placement tools (#35) reuse
## `screen_to_world` to drop geometry under the cursor.
##
## Conventions:
## - `pan`      — the world-space point displayed at the centre of the viewport.
## - `zoom`     — pixels per world unit (> 0); zoom 1.0 means 1px == 1 world unit,
##                larger values zoom in.
## - `viewport` — the canvas size in pixels.

## Sensible zoom bounds for the editor; exposed so the canvas and tests agree.
const MIN_ZOOM: float = 0.1
const MAX_ZOOM: float = 8.0


## World point -> screen pixel for the given view.
static func world_to_screen(world: Vector2, pan: Vector2, zoom: float, viewport: Vector2) -> Vector2:
	return (world - pan) * zoom + viewport * 0.5


## Screen pixel -> world point for the given view. Inverse of `world_to_screen`.
static func screen_to_world(screen: Vector2, pan: Vector2, zoom: float, viewport: Vector2) -> Vector2:
	return (screen - viewport * 0.5) / zoom + pan


## Clamp a zoom level into the editor's supported range.
static func clamp_zoom(zoom: float, min_zoom: float = MIN_ZOOM, max_zoom: float = MAX_ZOOM) -> float:
	return clampf(zoom, min_zoom, max_zoom)


## Multiply the current zoom by `factor` (> 1 zooms in, < 1 zooms out) and clamp.
static func apply_zoom(current: float, factor: float, min_zoom: float = MIN_ZOOM, max_zoom: float = MAX_ZOOM) -> float:
	return clamp_zoom(current * factor, min_zoom, max_zoom)


## New pan after dragging the canvas by `screen_delta` pixels. Dragging the
## mouse moves the content with it, so the world point shown at the centre
## shifts in the opposite direction (scaled by zoom).
static func pan_by_screen_delta(pan: Vector2, screen_delta: Vector2, zoom: float) -> Vector2:
	return pan - screen_delta / zoom


## New pan after changing zoom from `old_zoom` to `new_zoom` while keeping the
## world point currently under `screen_point` fixed (zoom-about-cursor).
static func zoom_about_screen_point(pan: Vector2, old_zoom: float, new_zoom: float, screen_point: Vector2, viewport: Vector2) -> Vector2:
	var world_before := screen_to_world(screen_point, pan, old_zoom, viewport)
	var world_after := screen_to_world(screen_point, pan, new_zoom, viewport)
	return pan + (world_before - world_after)


## The world-space rectangle currently visible in the viewport.
static func visible_world_rect(pan: Vector2, zoom: float, viewport: Vector2) -> Rect2:
	var top_left := screen_to_world(Vector2.ZERO, pan, zoom, viewport)
	return Rect2(top_left, viewport / zoom)

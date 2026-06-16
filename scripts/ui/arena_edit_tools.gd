extends RefCounted
class_name ArenaEditTools

## Pure, scene-free placement/editing logic for the arena editor canvas (#35).
##
## Mirrors the `EditorCamera` / `ArenaBuilder` convention: every method is static
## and has no Node/scene dependency, so the placement maths — grid snapping,
## hit-testing, and resize-handle geometry — can be unit-tested directly. The
## canvas (`ArenaEditorCanvas`) owns the mouse/keyboard plumbing and selection
## state; the decisions live here so the view and the (tested) maths cannot drift.
##
## Rectangles (platforms, kill zones) are stored centre + full size, matching
## `ArenaData`; helpers convert to/from a top-left `Rect2` where geometry is easier.

## The placement tools the editor exposes on its toolbar.
enum Tool { SELECT, PLATFORM, SPAWN, KILL_ZONE }

## What kind of element a selection refers to.
enum Kind { NONE, PLATFORM, SPAWN, KILL_ZONE }

## Resize grab points on a rectangle's bounding box.
enum Handle { NONE, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

## Grid spacing geometry snaps to, in world units (matches the canvas grid / 4).
const GRID_SNAP: float = 16.0
## Smallest platform / kill-zone extent, so a stray click can't make a 0-size rect.
const MIN_RECT_SIZE: Vector2 = Vector2(16, 16)
## Size used when a platform / kill zone is placed by a single click (no drag).
const DEFAULT_RECT_SIZE: Vector2 = Vector2(128, 32)


## Does the `kind`/`index` selection still refer to an existing element of
## `arena`? Used after an undo/redo restore (#79) to decide whether the recorded
## selection can be reapplied or must be dropped, since the element it pointed at
## may not exist in the restored state. A `NONE` kind or out-of-range / negative
## index is not a valid selection.
static func selection_exists(arena: ArenaData, kind: int, index: int) -> bool:
	if arena == null or index < 0:
		return false
	match kind:
		Kind.PLATFORM: return index < arena.platforms.size()
		Kind.SPAWN: return index < arena.spawn_points.size()
		Kind.KILL_ZONE: return index < arena.kill_zones.size()
	return false


## Snap a world point to the nearest grid intersection. A non-positive spacing
## disables snapping (returns the point unchanged).
static func snap(point: Vector2, spacing: float = GRID_SNAP) -> Vector2:
	if spacing <= 0.0:
		return point
	return (point / spacing).round() * spacing


## A centred rectangle (centre + full size) as a top-left `Rect2`.
static func centred_rect(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size * 0.5, size)


## Build a normalised rectangle from two opposite drag corners, enforcing a
## minimum size. Returns `{ "position": centre, "size": size }` to drop straight
## into `ArenaData.platforms` / `kill_zones`.
static func rect_from_drag(a: Vector2, b: Vector2, min_size: Vector2 = MIN_RECT_SIZE) -> Dictionary:
	var top_left := a.min(b)
	var bottom_right := a.max(b)
	var size := (bottom_right - top_left).max(min_size)
	return {"position": top_left + size * 0.5, "size": size}


## Does a centred rectangle contain a world point?
static func rect_contains(center: Vector2, size: Vector2, point: Vector2) -> bool:
	return centred_rect(center, size).has_point(point)


## Index of the topmost platform under `point`, or -1. Later platforms draw on
## top (see `ArenaEditorCanvas._draw_platforms`), so scan back-to-front to pick
## the one the user actually sees.
static func platform_index_at(arena: ArenaData, point: Vector2) -> int:
	for i in range(arena.platforms.size() - 1, -1, -1):
		var p: Dictionary = arena.platforms[i]
		if rect_contains(p.get("position", Vector2.ZERO), p.get("size", Vector2.ZERO), point):
			return i
	return -1


## Index of the topmost kill zone under `point`, or -1.
static func kill_zone_index_at(arena: ArenaData, point: Vector2) -> int:
	for i in range(arena.kill_zones.size() - 1, -1, -1):
		var k: Dictionary = arena.kill_zones[i]
		if rect_contains(k.get("position", Vector2.ZERO), k.get("size", Vector2.ZERO), point):
			return i
	return -1


## Index of the spawn point within `radius` world units of `point` (closest
## wins), or -1 when none is close enough.
static func spawn_index_at(arena: ArenaData, point: Vector2, radius: float) -> int:
	var best := -1
	var best_dist := radius * radius
	for i in arena.spawn_points.size():
		var d := arena.spawn_points[i].distance_squared_to(point)
		if d <= best_dist:
			best_dist = d
			best = i
	return best


## Which corner handle (if any) of a centred rectangle is under `point`, given a
## pick radius in world units. Returns the closest within range, else `NONE`.
static func handle_at(center: Vector2, size: Vector2, point: Vector2, pick_radius: float) -> Handle:
	var best := Handle.NONE
	var best_dist := pick_radius * pick_radius
	for h in [Handle.TOP_LEFT, Handle.TOP_RIGHT, Handle.BOTTOM_LEFT, Handle.BOTTOM_RIGHT]:
		var d: float = corner(center, size, h).distance_squared_to(point)
		if d <= best_dist:
			best_dist = d
			best = h
	return best


## World position of one corner handle of a centred rectangle.
static func corner(center: Vector2, size: Vector2, handle: int) -> Vector2:
	var half := size * 0.5
	match handle:
		Handle.TOP_LEFT: return center + Vector2(-half.x, -half.y)
		Handle.TOP_RIGHT: return center + Vector2(half.x, -half.y)
		Handle.BOTTOM_LEFT: return center + Vector2(-half.x, half.y)
		Handle.BOTTOM_RIGHT: return center + Vector2(half.x, half.y)
	return center


## New `{ centre, size }` after dragging `handle` to `point`, keeping the opposite
## corner fixed and enforcing `min_size`. An invalid handle leaves the rect as-is.
static func resize_rect(center: Vector2, size: Vector2, handle: int, point: Vector2, min_size: Vector2 = MIN_RECT_SIZE) -> Dictionary:
	if handle == Handle.NONE:
		return {"position": center, "size": size}
	var fixed := corner(center, size, _opposite(handle))
	return rect_from_drag(fixed, point, min_size)


static func _opposite(handle: int) -> int:
	match handle:
		Handle.TOP_LEFT: return Handle.BOTTOM_RIGHT
		Handle.TOP_RIGHT: return Handle.BOTTOM_LEFT
		Handle.BOTTOM_LEFT: return Handle.TOP_RIGHT
		Handle.BOTTOM_RIGHT: return Handle.TOP_LEFT
	return Handle.NONE

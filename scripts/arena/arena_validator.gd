extends RefCounted
class_name ArenaValidator

## Pre-save / pre-playtest validation for a custom [ArenaData] (#36).
##
## Pure, scene-free static helpers (mirrors [ArenaEditTools] / [ArenaBuilder]):
## every check operates on an [ArenaData] and returns structured issues, so the
## editor can surface them in its status line and the rules can be unit-tested
## without a scene tree.
##
## An *issue* is a `{ "severity": Severity, "message": String }` Dictionary.
## ERRORs make an arena unplayable (e.g. nowhere to stand, a spawn that kills
## instantly) and block playtest; WARNINGs are advisory (e.g. fewer spawns than
## the max player count) and never block.
##
## The three checks #36 asks for map on as: **min spawn count** (`_check_spawns`),
## **bounds** (`_check_bounds` — degenerate sizes + an unbounded play area), and
## **reachable geometry** (`_check_geometry` / `_check_spawn_placement` — solid
## ground exists, and no spawn is buried in a wall or sitting in a kill zone).
## Full pathfinding-based reachability is intentionally out of scope (see the PR's
## deferred notes); these structural checks catch the arenas that actually break a
## match.
##
## A lightweight **overlap / self-intersection** sanity pass (`_check_overlaps`,
## #74) flags layouts that are buildable but questionable rather than
## match-breaking — overlapping platforms and stacked spawn points — as WARNINGs.

enum Severity { WARNING, ERROR }

## Fewest spawn points an arena must define to be playable. Mirrors the local
## couch floor of two players; kept as a local constant so the arena layer stays
## decoupled from the match layer.
const MIN_SPAWN_POINTS: int = 2
## Spawn points an arena ideally provides — the local-play ceiling. Fewer still
## plays (MatchDirector fans extras out / reuses spawns) but is worth a warning.
const RECOMMENDED_SPAWN_POINTS: int = 4


## Validate `data`, returning every issue found (empty Array == perfectly valid).
static func validate(data: ArenaData) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if data == null:
		_add(issues, Severity.ERROR, "Arena data is null.")
		return issues
	_check_spawns(data, issues)
	_check_geometry(data, issues)
	_check_bounds(data, issues)
	_check_spawn_placement(data, issues)
	_check_overlaps(data, issues)
	return issues


## Convenience: true when `data` has no ERROR-level issues (warnings are allowed).
static func is_valid(data: ArenaData) -> bool:
	return not has_errors(validate(data))


## Count issues of a given severity in a list produced by [method validate].
static func count(issues: Array, severity: Severity) -> int:
	var n := 0
	for issue in issues:
		if issue.get("severity", Severity.WARNING) == severity:
			n += 1
	return n


static func has_errors(issues: Array) -> bool:
	return count(issues, Severity.ERROR) > 0


static func has_warnings(issues: Array) -> bool:
	return count(issues, Severity.WARNING) > 0


## A multi-line `[ERROR]/[WARN] message` summary for the editor status line.
static func summarize(issues: Array) -> String:
	if issues.is_empty():
		return "Arena is valid."
	var lines: Array[String] = []
	for issue in issues:
		var tag := "ERROR" if issue.get("severity", Severity.WARNING) == Severity.ERROR else "WARN"
		lines.append("[%s] %s" % [tag, issue.get("message", "")])
	return "\n".join(lines)


# --- Individual checks ------------------------------------------------------

## Min spawn count: at least MIN_SPAWN_POINTS to start a match; a warning below
## the recommended ceiling since extra players then share / reuse a spawn.
static func _check_spawns(data: ArenaData, issues: Array[Dictionary]) -> void:
	var n := data.spawn_points.size()
	if n < MIN_SPAWN_POINTS:
		_add(issues, Severity.ERROR,
			"Arena needs at least %d spawn points (has %d)." % [MIN_SPAWN_POINTS, n])
	elif n < RECOMMENDED_SPAWN_POINTS:
		_add(issues, Severity.WARNING,
			"Only %d spawn points; with up to %d players some will share a spawn." % [n, RECOMMENDED_SPAWN_POINTS])


## Reachable geometry (ground): there must be at least one platform, and every
## rectangle must have a positive extent (a 0-size collider is unplayable).
static func _check_geometry(data: ArenaData, issues: Array[Dictionary]) -> void:
	if data.platforms.is_empty():
		_add(issues, Severity.ERROR, "Arena has no platforms; players have nothing to stand on.")
	for i in data.platforms.size():
		if not _has_positive_size(data.platforms[i]):
			_add(issues, Severity.ERROR, "Platform %d has a non-positive size." % i)
	for i in data.kill_zones.size():
		if not _has_positive_size(data.kill_zones[i]):
			_add(issues, Severity.ERROR, "Kill zone %d has a non-positive size." % i)


## Bounds: an arena with no kill zone is unbounded — a player who falls away is
## never eliminated, so the last-alive check can never resolve and the round stalls.
static func _check_bounds(data: ArenaData, issues: Array[Dictionary]) -> void:
	if data.kill_zones.is_empty():
		_add(issues, Severity.WARNING,
			"Arena has no kill zones; players who fall away are never eliminated, which can stall a round.")


## Reachable geometry (spawns): a spawn inside a kill zone kills instantly
## (ERROR); a spawn buried in a solid platform leaves the player stuck (WARNING).
static func _check_spawn_placement(data: ArenaData, issues: Array[Dictionary]) -> void:
	for i in data.spawn_points.size():
		var sp: Vector2 = data.spawn_points[i]
		if _point_in_any(data.kill_zones, sp):
			_add(issues, Severity.ERROR, "Spawn point %d is inside a kill zone (instant death)." % i)
		if _point_in_any(data.platforms, sp):
			_add(issues, Severity.WARNING, "Spawn point %d is inside a platform (player may be stuck)." % i)


## Overlap / self-intersection sanity pass (#74): buildable-but-questionable
## layouts, surfaced as advisory WARNINGs (they never block playtest).
##
## - Overlapping platforms: two platform rectangles that genuinely interpenetrate.
##   Edge-sharing (flush) layouts only touch on a border, so `intersects` is called
##   with `include_borders = false` and the common compound-shape technique of
##   butting platforms together is NOT flagged.
## - Stacked spawns: two spawn points at the same position would spawn players on
##   top of one another. Coincidence (`is_equal_approx`) is used rather than a
##   player-size proximity radius so the arena layer stays decoupled from the
##   match/player layer (mirroring the `MIN_SPAWN_POINTS` rationale above).
static func _check_overlaps(data: ArenaData, issues: Array[Dictionary]) -> void:
	for i in data.platforms.size():
		var rect_i := _rect_of(data.platforms[i])
		for j in range(i + 1, data.platforms.size()):
			if rect_i.intersects(_rect_of(data.platforms[j]), false):
				_add(issues, Severity.WARNING, "Platforms %d and %d overlap." % [i, j])
	for i in data.spawn_points.size():
		var sp: Vector2 = data.spawn_points[i]
		for j in range(i + 1, data.spawn_points.size()):
			if sp.is_equal_approx(data.spawn_points[j]):
				_add(issues, Severity.WARNING,
					"Spawn points %d and %d are stacked at the same position." % [i, j])


# --- Internal helpers -------------------------------------------------------

static func _add(issues: Array[Dictionary], severity: Severity, message: String) -> void:
	issues.append({"severity": severity, "message": message})


static func _has_positive_size(rect: Dictionary) -> bool:
	var size: Vector2 = rect.get("size", Vector2.ZERO)
	return size.x > 0.0 and size.y > 0.0


## True when `point` falls inside any centred-rectangle entry of `rects`. Matches
## the centre+size storage ArenaData uses for platforms / kill zones.
static func _point_in_any(rects: Array, point: Vector2) -> bool:
	for rect in rects:
		var center: Vector2 = rect.get("position", Vector2.ZERO)
		var size: Vector2 = rect.get("size", Vector2.ZERO)
		if Rect2(center - size * 0.5, size).has_point(point):
			return true
	return false


## Build the axis-aligned [Rect2] for a centre+size entry. `abs()` normalises any
## negative-size (degenerate) entry so the intersection test is well-defined; such
## entries are already flagged as errors by `_check_geometry`.
static func _rect_of(entry: Dictionary) -> Rect2:
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var size: Vector2 = entry.get("size", Vector2.ZERO)
	return Rect2(center - size * 0.5, size).abs()

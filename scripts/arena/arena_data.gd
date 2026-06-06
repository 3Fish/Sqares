extends RefCounted
class_name ArenaData

## Serializable description of a custom arena.
##
## Holds everything needed to rebuild an arena at runtime — geometry (platforms),
## spawn points, kill zones, and metadata — independent of any scene or node.
## The arena editor (#34/#35) produces these, the load path (#33) turns them into
## a runtime scene satisfying the `arena_base.gd` spawn contract, and `ArenaStore`
## persists them to `user://arenas/` as JSON.
##
## Coordinates are stored in the arena's local space (the same space the built-in
## `.tscn` arenas use). JSON keeps the files human-editable and mod-friendly.

## Bumped when the on-disk schema changes in a backwards-incompatible way.
const FORMAT_VERSION: int = 1

# --- Metadata ---------------------------------------------------------------
var id: String = ""                       ## Unique slug; also the file name.
var display_name: String = ""             ## Human-facing name shown in menus.
var author: String = ""                   ## Optional creator attribution.

# --- Presentation -----------------------------------------------------------
var background_color: Color = Color(0.09, 0.09, 0.16, 1.0)

# --- Geometry ---------------------------------------------------------------
## Solid platforms. Each entry: { "position": Vector2, "size": Vector2, "color": Color }.
## `position` is the centre of the rectangle; `size` is its full extent.
var platforms: Array[Dictionary] = []

## Player spawn locations (centres), in placement order.
var spawn_points: Array[Vector2] = []

## Lethal regions. Each entry: { "position": Vector2, "size": Vector2 }.
var kill_zones: Array[Dictionary] = []


# --- Construction helpers ---------------------------------------------------

## Append a platform. Returns self for chaining.
func add_platform(position: Vector2, size: Vector2, color: Color = Color(0.3, 0.3, 0.45, 1.0)) -> ArenaData:
	platforms.append({"position": position, "size": size, "color": color})
	return self


## Append a spawn point. Returns self for chaining.
func add_spawn_point(position: Vector2) -> ArenaData:
	spawn_points.append(position)
	return self


## Append a kill zone. Returns self for chaining.
func add_kill_zone(position: Vector2, size: Vector2) -> ArenaData:
	kill_zones.append({"position": position, "size": size})
	return self


# --- Serialisation ----------------------------------------------------------

## Convert to a plain, JSON-safe dictionary (Vector2/Color flattened to arrays).
func to_dict() -> Dictionary:
	var plats: Array = []
	for p in platforms:
		plats.append({
			"position": _vec_to_arr(p.get("position", Vector2.ZERO)),
			"size": _vec_to_arr(p.get("size", Vector2.ZERO)),
			"color": _color_to_arr(p.get("color", Color.WHITE)),
		})
	var spawns: Array = []
	for s in spawn_points:
		spawns.append(_vec_to_arr(s))
	var kills: Array = []
	for k in kill_zones:
		kills.append({
			"position": _vec_to_arr(k.get("position", Vector2.ZERO)),
			"size": _vec_to_arr(k.get("size", Vector2.ZERO)),
		})
	return {
		"format_version": FORMAT_VERSION,
		"id": id,
		"display_name": display_name,
		"author": author,
		"background_color": _color_to_arr(background_color),
		"platforms": plats,
		"spawn_points": spawns,
		"kill_zones": kills,
	}


## Rebuild an ArenaData from a dictionary produced by `to_dict()`.
## Defensive: missing or malformed fields fall back to sensible defaults so a
## partially-corrupt file still loads instead of crashing.
static func from_dict(data: Dictionary) -> ArenaData:
	var arena := ArenaData.new()
	arena.id = str(data.get("id", ""))
	arena.display_name = str(data.get("display_name", ""))
	arena.author = str(data.get("author", ""))
	arena.background_color = _arr_to_color(
		data.get("background_color", []), arena.background_color
	)

	for p in _as_array(data.get("platforms", [])):
		if p is Dictionary:
			arena.platforms.append({
				"position": _arr_to_vec(p.get("position", []), Vector2.ZERO),
				"size": _arr_to_vec(p.get("size", []), Vector2.ZERO),
				"color": _arr_to_color(p.get("color", []), Color(0.3, 0.3, 0.45, 1.0)),
			})

	for s in _as_array(data.get("spawn_points", [])):
		arena.spawn_points.append(_arr_to_vec(s, Vector2.ZERO))

	for k in _as_array(data.get("kill_zones", [])):
		if k is Dictionary:
			arena.kill_zones.append({
				"position": _arr_to_vec(k.get("position", []), Vector2.ZERO),
				"size": _arr_to_vec(k.get("size", []), Vector2.ZERO),
			})

	return arena


## Serialise to an indented JSON string.
func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Parse a JSON string into an ArenaData. Returns null on invalid JSON.
static func from_json(text: String) -> ArenaData:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("ArenaData: could not parse JSON into an arena.")
		return null
	return from_dict(parsed)


# --- Internal conversion helpers -------------------------------------------

static func _vec_to_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func _arr_to_vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _color_to_arr(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _arr_to_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var a: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), a)
	return fallback


static func _as_array(value: Variant) -> Array:
	return value if value is Array else []

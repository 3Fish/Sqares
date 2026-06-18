extends RefCounted
class_name ArenaBuilder

## Turns an [ArenaData] description into a runtime [Arena] node tree (#33).
##
## The arena editor (#34/#35) produces [ArenaData] and persists it via
## [ArenaStore]; this builder is the load path that rebuilds it into something
## playable. The output satisfies the `arena_base.gd` / `MatchDirector` spawn
## contract: spawn markers are named `Spawn*`, and a single `KillZone` Area2D
## (when the data has kill zones) is wired by [Arena] on `_ready`.
##
## Built arenas mirror the structure of the hand-authored `.tscn` arenas
## (StaticBody2D platforms with a collision shape + a Polygon2D visual), so they
## behave identically once instantiated.
##
## All methods are static — the builder holds no state.

## Default platform fill colour, matching the built-in arenas.
const PLATFORM_COLOR: Color = Color(0.3, 0.3, 0.45, 1.0)
## Padding added around the content bounds when sizing the background.
const BACKGROUND_PADDING: float = 64.0
## Fallback half-extent for the background when an arena has no content yet.
const DEFAULT_BACKGROUND_EXTENT: float = 640.0
## KillZone collision mask — matches the built-in arenas (players are on layer 2).
const KILL_ZONE_MASK: int = 2


## Build a detached runtime [Arena] from `data`. The node is not added to any
## tree; the caller (or an instantiated [PackedScene]) owns it.
static func build(data: ArenaData) -> Arena:
	var root := Arena.new()
	root.name = _root_name(data)

	root.add_child(_build_background(data))

	for i in data.platforms.size():
		root.add_child(_build_platform(data.platforms[i], i))

	for i in data.spawn_points.size():
		root.add_child(_build_spawn(data.spawn_points[i], i))

	var kill_zone := _build_kill_zone(data)
	if kill_zone:
		root.add_child(kill_zone)

	return root


## Build the arena and pack it into a [PackedScene] so it can be registered in
## [LevelRegistry] and instantiated by [MatchDirector] just like a built-in
## `.tscn` arena. Returns null if packing fails.
static func build_packed_scene(data: ArenaData) -> PackedScene:
	var root := build(data)
	_set_owner_recursive(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	# The detached tree has served its purpose; the PackedScene holds a copy.
	root.free()
	if err != OK:
		push_error("ArenaBuilder: failed to pack arena '%s' (error %d)." % [data.id, err])
		return null
	return scene


# --- Pure helpers (no scene-tree dependency — covered by tests/) -------------

## Axis-aligned bounds covering every platform, spawn and kill zone, padded.
## Falls back to a default square when the arena has no content. Used to size
## the background so it always covers the playable area.
static func compute_bounds(data: ArenaData) -> Rect2:
	var has_any := false
	var min_p := Vector2.INF
	var max_p := -Vector2.INF

	for p in data.platforms:
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		var half: Vector2 = (p.get("size", Vector2.ZERO) as Vector2) * 0.5
		min_p = min_p.min(pos - half)
		max_p = max_p.max(pos + half)
		has_any = true

	for s in data.spawn_points:
		min_p = min_p.min(s)
		max_p = max_p.max(s)
		has_any = true

	for k in data.kill_zones:
		var pos: Vector2 = k.get("position", Vector2.ZERO)
		var half: Vector2 = (k.get("size", Vector2.ZERO) as Vector2) * 0.5
		min_p = min_p.min(pos - half)
		max_p = max_p.max(pos + half)
		has_any = true

	if not has_any:
		return Rect2(
			Vector2(-DEFAULT_BACKGROUND_EXTENT, -DEFAULT_BACKGROUND_EXTENT),
			Vector2(DEFAULT_BACKGROUND_EXTENT, DEFAULT_BACKGROUND_EXTENT) * 2.0
		)

	var pad := Vector2(BACKGROUND_PADDING, BACKGROUND_PADDING)
	return Rect2(min_p - pad, (max_p - min_p) + pad * 2.0)


## The centred rectangle polygon for a node of the given `size`.
static func rect_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


# --- Internal construction --------------------------------------------------

static func _root_name(data: ArenaData) -> String:
	if not data.display_name.strip_edges().is_empty():
		return data.display_name
	if not data.id.strip_edges().is_empty():
		return data.id
	return "CustomArena"


static func _build_background(data: ArenaData) -> Polygon2D:
	var bounds := compute_bounds(data)
	var bg := Polygon2D.new()
	bg.name = "Background"
	bg.color = data.background_color
	bg.polygon = PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	])
	return bg


## Builds one platform node. A `physics`-flagged platform (#96) becomes a
## pushable [PhysicsBlock] (RigidBody2D); otherwise a solid [StaticBody2D].
## Both carry a centred rectangle collision shape and a Polygon2D visual, so
## they render identically — only the body type (and behaviour) differs.
static func _build_platform(platform: Dictionary, index: int) -> PhysicsBody2D:
	var size: Vector2 = platform.get("size", Vector2.ZERO)
	var color: Color = platform.get("color", PLATFORM_COLOR)
	var is_physics: bool = bool(platform.get("physics", false))

	var body: PhysicsBody2D
	if is_physics:
		var block := PhysicsBlock.new()
		block.configure(size)
		body = block
	else:
		body = StaticBody2D.new()
	body.name = "Platform%d" % index
	body.position = platform.get("position", Vector2.ZERO)

	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	body.add_child(collision)

	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = rect_polygon(size)
	visual.color = color
	body.add_child(visual)

	return body


static func _build_spawn(position: Vector2, index: int) -> Node2D:
	var spawn := Node2D.new()
	# arena_base.get_spawn_points() keys off the "Spawn" name prefix.
	spawn.name = "Spawn%d" % index
	spawn.position = position
	# Mirror the built-in arenas, which also tag spawns for discoverability.
	spawn.add_to_group("spawn_point")
	return spawn


## Build one `KillZone` Area2D holding a collision shape per data kill zone, or
## null when the arena defines none. [Arena] wires the single `$KillZone` node.
static func _build_kill_zone(data: ArenaData) -> Area2D:
	if data.kill_zones.is_empty():
		return null

	var area := Area2D.new()
	area.name = "KillZone"
	area.collision_layer = 0
	area.collision_mask = KILL_ZONE_MASK

	for i in data.kill_zones.size():
		var kz: Dictionary = data.kill_zones[i]
		var shape := RectangleShape2D.new()
		shape.size = kz.get("size", Vector2.ZERO)
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D%d" % i
		collision.shape = shape
		# Shapes are positioned in the KillZone's local space (= arena space,
		# since KillZone sits at the origin).
		collision.position = kz.get("position", Vector2.ZERO)
		area.add_child(collision)

	return area


## Recursively point every descendant's `owner` at `root` so they are all saved
## when the tree is packed. The root itself keeps its null owner.
static func _set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owner_recursive(child, root)

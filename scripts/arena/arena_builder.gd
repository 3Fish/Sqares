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

	# Ropes resolve their block endpoints by `Platform<index>` name, so the
	# platforms above are already in the tree when each rope's `_ready` runs.
	for i in data.ropes.size():
		root.add_child(_build_rope(data, data.ropes[i], i))

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

	# Include rope world anchors so a mid-air anchor isn't left off the
	# background; block endpoints are already covered by their platforms.
	for r in data.ropes:
		if int(r.get("a_block", -1)) < 0:
			var pa: Vector2 = r.get("a_anchor", Vector2.ZERO)
			min_p = min_p.min(pa)
			max_p = max_p.max(pa)
			has_any = true
		if int(r.get("b_block", -1)) < 0:
			var pb: Vector2 = r.get("b_anchor", Vector2.ZERO)
			min_p = min_p.min(pb)
			max_p = max_p.max(pb)
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


## Builds one platform node from its independent `physics` (#96) and
## `destructible` (#97) flags:
## - neither: a solid [StaticBody2D];
## - physics: a pushable [PhysicsBlock] (RigidBody2D);
## - destructible only: a damageable static [DestructibleBlock];
## - physics + destructible: a [PhysicsBlock] made destructible (pushable AND
##   damageable).
## All carry a centred rectangle collision shape and a Polygon2D visual, so they
## render identically — only the body type (and behaviour) differs.
static func _build_platform(platform: Dictionary, index: int) -> PhysicsBody2D:
	var size: Vector2 = platform.get("size", Vector2.ZERO)
	var color: Color = platform.get("color", PLATFORM_COLOR)
	var is_physics: bool = bool(platform.get("physics", false))
	var is_destructible: bool = bool(platform.get("destructible", false))

	var body: PhysicsBody2D
	if is_physics:
		var block := PhysicsBlock.new()
		block.configure(size)
		if is_destructible:
			block.make_destructible()
		body = block
	elif is_destructible:
		var dblock := DestructibleBlock.new()
		dblock.configure(size)
		body = dblock
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


## Builds one Chain/Rope (#98) from its endpoint config. Block endpoints are
## stored as platform indices that the [Rope] resolves from its `Platform<index>`
## siblings at `_ready`; world anchors are stored as points. The rope length is
## baked from the endpoints' initial separation when the data left it automatic
## (negative), so a packed/instanced arena keeps a stable length.
static func _build_rope(data: ArenaData, rope: Dictionary, index: int) -> Rope:
	var node := Rope.new()
	node.name = "Rope%d" % index
	node.endpoint_a_block = int(rope.get("a_block", -1))
	node.endpoint_a_anchor = rope.get("a_anchor", Vector2.ZERO)
	node.endpoint_b_block = int(rope.get("b_block", -1))
	node.endpoint_b_anchor = rope.get("b_anchor", Vector2.ZERO)

	var length := float(rope.get("length", -1.0))
	if length < 0.0:
		var pa := _rope_endpoint_point(data, node.endpoint_a_block, node.endpoint_a_anchor)
		var pb := _rope_endpoint_point(data, node.endpoint_b_block, node.endpoint_b_anchor)
		length = pa.distance_to(pb)
	node.rope_length = length
	return node


## The arena-space point of a rope endpoint: a platform's centre when `block` is a
## valid index, otherwise the world `anchor`.
static func _rope_endpoint_point(data: ArenaData, block: int, anchor: Vector2) -> Vector2:
	if block >= 0 and block < data.platforms.size():
		return data.platforms[block].get("position", Vector2.ZERO)
	return anchor


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

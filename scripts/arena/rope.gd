extends Node2D
class_name Rope

## A Chain/Rope constraint object (#98 — PoC step 3 of #85).
##
## The rope is itself indestructible and has two endpoints. Each endpoint is
## either a fixed point in world space (a mid-air anchor) or a platform block
## (resolved from its sibling `Platform<index>` node, built by [ArenaBuilder]).
## The rope is a **constraint, not a custom animation**: every physics tick it
## applies a maximum-length distance constraint (the pure [RopeConstraint] maths)
## to any endpoint that is a physics-enabled [PhysicsBlock], so the block follows
## normal physics — gravity, player pushes, bullet impacts — while being held by
## the rope.
##
## Endpoint behaviour:
## - **Physics block** endpoint: dynamic; inverse mass `1 / mass`, so it is pulled
##   back when the rope goes taut (and the correction is shared by mass on a
##   block ↔ block rope).
## - **World anchor** or **non-physics (static) block** endpoint: a fixed point
##   (inverse mass 0) that never moves.
## - If **neither** endpoint is a physics block the rope is purely **decorative**
##   (no constraint forces).
##
## Severing: if an endpoint is a **destructible** block, destroying it emits its
## `destroyed` signal, which severs the rope (the constraint stops acting). A
## mid-air anchor is never destroyed and never severs.
##
## The constraint maths live in the pure, scene-free [RopeConstraint] (covered by
## the headless suite per `CLAUDE.md`); this node holds only the endpoint
## resolution, the per-tick wiring, and the sever state. A dedicated rope visual
## and online replication of the constraint/sever are deferred follow-ups (see the
## PR), mirroring #84/#96/#97.

## Endpoint A. `*_block` is the platform index this endpoint attaches to, or `-1`
## for a world anchor at `*_anchor` (in arena-local space). Exported so a built
## arena round-trips through its packed scene.
@export var endpoint_a_block: int = -1
@export var endpoint_a_anchor: Vector2 = Vector2.ZERO
## Endpoint B — same encoding as endpoint A.
@export var endpoint_b_block: int = -1
@export var endpoint_b_anchor: Vector2 = Vector2.ZERO
## Rope length (max endpoint separation). A negative value means "derive from the
## endpoints' initial separation when the rope resolves".
@export var rope_length: float = -1.0

## Resolved block nodes for block endpoints (null for a world anchor).
var _node_a: Node2D = null
var _node_b: Node2D = null
## True once an endpoint block has been destroyed: the constraint stops acting.
var _severed: bool = false
var _resolved: bool = false


func _ready() -> void:
	# Run the constraint after the bodies have integrated this step.
	process_physics_priority = 100
	resolve()


## Resolves the two endpoints from the exported config: looks up `Platform<index>`
## siblings for block endpoints, derives the rope length from the initial endpoint
## separation when it was left automatic, and connects each destructible endpoint
## block's `destroyed` signal so the rope severs. Idempotent and safe to call on a
## detached tree (used by the headless tests), so it does not depend on `_ready`.
func resolve() -> void:
	if _resolved:
		return
	_node_a = _resolve_block(endpoint_a_block)
	_node_b = _resolve_block(endpoint_b_block)
	if rope_length < 0.0:
		rope_length = _position_of(_node_a, endpoint_a_anchor).distance_to(
			_position_of(_node_b, endpoint_b_anchor))
	_connect_sever(_node_a)
	_connect_sever(_node_b)
	_resolved = true


## True when neither endpoint is a physics block, so the rope applies no forces
## and merely spans its endpoints decoratively.
func is_decorative() -> bool:
	return _inv_mass(_node_a) <= 0.0 and _inv_mass(_node_b) <= 0.0


## True once a destructible endpoint block has been destroyed and the rope has
## severed; from then on it applies no constraint.
func is_severed() -> bool:
	return _severed


func _physics_process(_delta: float) -> void:
	if _severed or is_decorative():
		return
	_apply_constraint()


# ---------------------------------------------------------------------------
# Constraint application
# ---------------------------------------------------------------------------

## Pulls any physics-block endpoint back so the rope is no longer over-extended,
## using the shared [RopeConstraint] position + velocity corrections. Fixed
## endpoints (anchors / static blocks) absorb none of the correction.
func _apply_constraint() -> void:
	# An endpoint block freed without severing (shouldn't happen, but stay robust):
	# treat the rope as inert rather than reading a dangling node.
	if _endpoint_broken(_node_a, endpoint_a_block) or _endpoint_broken(_node_b, endpoint_b_block):
		return
	var pa := _position_of(_node_a, endpoint_a_anchor)
	var pb := _position_of(_node_b, endpoint_b_anchor)
	var ima := _inv_mass(_node_a)
	var imb := _inv_mass(_node_b)

	var pos := RopeConstraint.solve(pa, pb, ima, imb, rope_length)
	var vel := RopeConstraint.velocity_correction(
		pa, pb, _velocity_of(_node_a), _velocity_of(_node_b), ima, imb)

	_apply_to(_node_a, pos["a"], vel["a"])
	_apply_to(_node_b, pos["b"], vel["b"])


## Applies a position + velocity correction to a physics-block endpoint. No-op for
## a fixed endpoint (a world anchor or a non-physics block never moves).
func _apply_to(node: Node2D, position_delta: Vector2, velocity_delta: Vector2) -> void:
	var block := node as PhysicsBlock
	if block == null:
		return
	block.position += position_delta
	block.linear_velocity += velocity_delta


# ---------------------------------------------------------------------------
# Endpoint resolution helpers
# ---------------------------------------------------------------------------

## True when an endpoint is meant to be a block (a non-negative platform index)
## but its resolved node is missing/freed.
func _endpoint_broken(node: Node2D, block_index: int) -> bool:
	return block_index >= 0 and not is_instance_valid(node)


## The block node for a platform `index`, or null for a world anchor (index < 0)
## or when the sibling can't be found.
func _resolve_block(index: int) -> Node2D:
	if index < 0:
		return null
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("Platform%d" % index) as Node2D


## Position (in the rope's parent space) of an endpoint: the block's position when
## it is a block, else the authored world anchor. A freed block falls back to the
## anchor so a severed/missing endpoint has a defined point.
func _position_of(node: Node2D, anchor: Vector2) -> Vector2:
	if is_instance_valid(node):
		return node.position
	return anchor


## Linear velocity of a physics-block endpoint, or zero for a fixed endpoint.
func _velocity_of(node: Node2D) -> Vector2:
	var block: PhysicsBlock = (node as PhysicsBlock) if is_instance_valid(node) else null
	return block.linear_velocity if block != null else Vector2.ZERO


## Inverse mass of an endpoint: `1 / mass` for a physics block, else 0 (a world
## anchor or a non-physics/static block is a fixed point that never moves).
func _inv_mass(node: Node2D) -> float:
	var block: PhysicsBlock = (node as PhysicsBlock) if is_instance_valid(node) else null
	if block != null and block.mass > 0.0:
		return 1.0 / block.mass
	return RopeConstraint.FIXED_INV_MASS


## Connects a destructible endpoint block's `destroyed` signal so the rope severs
## when that block is destroyed. World anchors and plain static blocks have no
## such signal and never sever.
func _connect_sever(node: Node2D) -> void:
	if is_instance_valid(node) and node.has_signal("destroyed"):
		node.connect("destroyed", _on_endpoint_destroyed)


func _on_endpoint_destroyed(_block: Object) -> void:
	_severed = true

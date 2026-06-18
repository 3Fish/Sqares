class_name RopeConstraint
extends RefCounted

## Pure 2D distance-constraint maths for the Chain/Rope object (#98, from #85).
##
## A chain/rope is an inextensible-but-flexible link: it resists being stretched
## past its length but offers no resistance when its endpoints come closer (it
## simply goes slack). So the constraint is a **maximum-length** distance
## constraint — taut endpoints are pulled back together, slack endpoints are left
## alone. This is the defining behaviour of a chain/rope (a rigid link would be a
## rod/bar, which #98 deliberately is not).
##
## Endpoints are described only by position and **inverse mass**: a dynamic
## [PhysicsBlock] endpoint uses `1 / PhysicsModel.block_mass(size)`, while a fixed
## world anchor or a non-physics (static) block uses inverse mass `0` so it never
## moves. The correction needed to satisfy the constraint is split between the two
## endpoints in proportion to their inverse mass (position-based dynamics), so a
## world-anchor ↔ physics-block rope moves only the block, and a block ↔ block
## rope shares the correction by mass.
##
## Every function is pure (no scene-tree dependency) so the constraint is covered
## by the headless test suite per `CLAUDE.md`; [Rope] holds the endpoint
## resolution + sever state and applies these corrections to the live bodies.

## Inverse mass of a fixed endpoint (world anchor or non-physics block): it never
## moves, so it absorbs none of the constraint correction.
const FIXED_INV_MASS := 0.0


## How far past `rest_length` the two endpoints are stretched, or `0.0` when the
## rope is slack (current distance ≤ `rest_length`). Never negative. Pure.
static func over_extension(a: Vector2, b: Vector2, rest_length: float) -> float:
	return maxf(0.0, a.distance_to(b) - rest_length)


## True when the rope is stretched to (past) its length and is therefore pulling
## its endpoints together; false while it hangs slack. Pure.
static func is_taut(a: Vector2, b: Vector2, rest_length: float) -> bool:
	return over_extension(a, b, rest_length) > 0.0


## Position correction (a delta to add to each endpoint) that pulls a taut rope
## back to `rest_length`, split between the endpoints by inverse mass. Returns
## `{ "a": Vector2, "b": Vector2 }`. Both deltas are [constant Vector2.ZERO] when
## the rope is slack, when the endpoints coincide (no defined direction), or when
## both endpoints are fixed (`inv_mass` 0). Pure — position-based dynamics, so the
## split is unit-tested without a live physics step.
static func solve(a: Vector2, b: Vector2, inv_mass_a: float, inv_mass_b: float, rest_length: float) -> Dictionary:
	var zero := {"a": Vector2.ZERO, "b": Vector2.ZERO}
	var dist := a.distance_to(b)
	var stretch := dist - rest_length
	if stretch <= 0.0 or dist <= 0.0:
		return zero  # slack, or coincident endpoints -> nothing to correct
	var total_inv := inv_mass_a + inv_mass_b
	if total_inv <= 0.0:
		return zero  # both endpoints fixed -> the rope cannot move either
	# Direction from a toward b; pull a forward along it and b back along it so
	# the gap closes by exactly `stretch`, shared in proportion to inverse mass.
	var dir := (b - a) / dist
	var correction := dir * stretch
	return {
		"a": correction * (inv_mass_a / total_inv),
		"b": -correction * (inv_mass_b / total_inv),
	}


## Velocity correction (a delta to add to each endpoint's velocity) that cancels
## the **separating** component of the endpoints' relative velocity along the rope,
## so a taut rope does not keep stretching or bounce outward. Returns
## `{ "a": Vector2, "b": Vector2 }`, split by inverse mass. Zero when the
## endpoints are approaching (the rope only resists separation, never compression),
## when they coincide, or when both are fixed. Pure — the caller applies it only
## while the rope is taut.
static func velocity_correction(a: Vector2, b: Vector2, vel_a: Vector2, vel_b: Vector2, inv_mass_a: float, inv_mass_b: float) -> Dictionary:
	var zero := {"a": Vector2.ZERO, "b": Vector2.ZERO}
	var dist := a.distance_to(b)
	if dist <= 0.0:
		return zero
	var total_inv := inv_mass_a + inv_mass_b
	if total_inv <= 0.0:
		return zero
	var dir := (b - a) / dist
	# Relative radial speed: positive means b is moving away from a (separating).
	var separating := (vel_b - vel_a).dot(dir)
	if separating <= 0.0:
		return zero  # endpoints approaching -> rope is going slack, no resistance
	var impulse := separating / total_inv
	return {
		"a": dir * (impulse * inv_mass_a),
		"b": -dir * (impulse * inv_mass_b),
	}

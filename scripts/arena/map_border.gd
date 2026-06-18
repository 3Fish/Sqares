class_name MapBorder
extends RefCounted

## The damaging elastic map boundary (#84).
##
## Map borders are NOT solid walls. A player whose body touches or crosses the
## border is treated as "out of bounds": it takes damage and is repelled inward
## by a distance-based restoring force, like the elastic ropes of a wrestling
## ring. The border is a hardcoded, non-removable game rule (per the maintainer's
## #84 decision) and coincides with the edge of the view area — every built-in
## arena centres its `Camera2D` at the origin over the 1280x720 viewport, so the
## play-area edge is `±HALF_EXTENT` in arena space, on all four sides. The
## optional instant-death `KillZone` block is a separate, designer-placed element
## and is unaffected by this.
##
## Every function here is pure (no scene-tree dependency) so the boundary maths
## are covered by the headless test suite per `CLAUDE.md`; [Player] holds the
## small per-excursion state (out-of-bounds flag + damage countdown) and wires
## these helpers into its simulation step.

## Half-extent of the play area, in world pixels — the edge of the 1280x720 view
## area, centred at the arena origin. The border lies on all four sides at this
## extent.
const HALF_EXTENT := Vector2(640.0, 360.0)

## Restoring-force spring constant (Hooke's law), in px/s² of inward acceleration
## per pixel of penetration. Tuning: firm enough that a terminal-velocity fall is
## reversed within a small overshoot rather than sinking far off-screen.
const SPRING_CONSTANT := 300.0

## Immediate inward speed (px/s) added the instant the border is first touched,
## so even the lightest contact bounces the player back ("electric fence").
## Tuning.
const CONTACT_IMPULSE := 200.0

## Damage applied on first contact (t = 0) and on every damage tick thereafter.
const DAMAGE_PER_TICK := 50.0

## Interval between damage ticks while out of bounds, in seconds (50 per 500 ms).
const DAMAGE_INTERVAL := 0.5

## Tolerance (seconds) for the damage-countdown boundary. When per-frame deltas
## sum to exactly an interval, the countdown can land a few float-ulps *above*
## zero (e.g. `0.5 - 5*0.1 == 2.78e-17`) and the tick that should fire on that
## boundary is silently lost — degrading the 50-per-500 ms cadence to 50/s. A
## small tolerance fires the boundary tick anyway; `1e-9` s is far above the
## accumulated float noise yet far below any meaningful game time.
const TICK_EPSILON := 1e-9


## Inward penetration of a body of half-size `half` centred at `center` past the
## border at `half_extent`. The returned vector points **inward** (the direction
## a restoring force should act) and its per-axis magnitude is how far the body's
## edge has crossed that border. Returns [constant Vector2.ZERO] when the body is
## fully inside, so a non-zero result means "out of bounds". A corner excursion
## yields both components. Pure.
static func penetration(center: Vector2, half: Vector2, half_extent: Vector2 = HALF_EXTENT) -> Vector2:
	var pen := Vector2.ZERO

	var over_right := (center.x + half.x) - half_extent.x
	var over_left := -half_extent.x - (center.x - half.x)
	if over_right > 0.0:
		pen.x = -over_right        # crossed the right border -> push left (inward)
	elif over_left > 0.0:
		pen.x = over_left          # crossed the left border  -> push right (inward)

	var over_bottom := (center.y + half.y) - half_extent.y
	var over_top := -half_extent.y - (center.y - half.y)
	if over_bottom > 0.0:
		pen.y = -over_bottom       # crossed the bottom border -> push up (inward)
	elif over_top > 0.0:
		pen.y = over_top           # crossed the top border    -> push down (inward)

	return pen


## True when the body touches or crosses any border. Pure.
static func is_out_of_bounds(center: Vector2, half: Vector2, half_extent: Vector2 = HALF_EXTENT) -> bool:
	return penetration(center, half, half_extent) != Vector2.ZERO


## Restoring acceleration for a given inward `pen` (Hooke's law: a = k · x,
## directed inward). The caller integrates it into velocity over the tick. While
## out of bounds this is the ONLY force acting — no gravity, friction or damping.
## Pure.
static func restoring_acceleration(pen: Vector2) -> Vector2:
	return pen * SPRING_CONSTANT


## One-shot inward impulse applied on the frame the border is first touched, in
## the direction of `pen`. Zero when `pen` is zero. Pure.
static func contact_impulse(pen: Vector2) -> Vector2:
	if pen == Vector2.ZERO:
		return Vector2.ZERO
	return pen.normalized() * CONTACT_IMPULSE


## Advances the damage countdown for one out-of-bounds tick (used on every tick
## *after* first contact, which deals its [constant DAMAGE_PER_TICK] directly).
## Given the countdown `timer` before the tick and the tick `delta`, returns
## `{ "damage": float, "timer": float }`: each time the countdown crosses zero a
## further [constant DAMAGE_PER_TICK] lands and the countdown resets by
## [constant DAMAGE_INTERVAL] (so a long tick can bank multiple ticks of damage).
## Pure so the 50-per-500 ms cadence is unit-tested without a live clock.
static func accrue_damage(timer: float, delta: float) -> Dictionary:
	var remaining := timer - delta
	var damage := 0.0
	while remaining <= TICK_EPSILON:
		damage += DAMAGE_PER_TICK
		remaining += DAMAGE_INTERVAL
	return {"damage": damage, "timer": remaining}

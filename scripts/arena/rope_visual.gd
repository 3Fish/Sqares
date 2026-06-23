class_name RopeVisual
extends RefCounted

## Pure geometry for the decorative Chain/Rope line (#104, deferred from #98).
##
## #98 ships the rope as a logic-only maximum-length constraint that draws
## nothing. Per the maintainer's [#104 answer](https://github.com/3Fish/Sqares/issues/104#issuecomment-4762604238)
## the rope renders as "just a line with some sag": a straight line while taut
## (every rope is placed at its full length, so it starts straight), bowing
## downward under gravity as the endpoints come closer and the rope goes slack.
## The rope is purely decorative and never collides (the [RopeConstraint] already
## keeps the endpoints within `rope_length`), so this is geometry only — no
## gameplay value depends on the curve, which makes the exact sag shape a visual
## choice rather than a balance decision.
##
## Every function here is pure (no scene-tree dependency) so the curve is covered
## by the headless suite per `CLAUDE.md`; the [Rope] node feeds its resolved
## endpoints in each tick and pushes the returned points into a child `Line2D`.

## Default number of segments the rendered rope is split into. More segments = a
## smoother sag curve; the rope is decorative, so the count has no gameplay
## effect (a per-object visual tuning constant per `CLAUDE.md`).
const SEGMENTS := 16

## Direction the slack rope bows under gravity. Godot screen space has +Y down,
## so a hanging rope droops toward `(0, 1)` regardless of how its endpoints are
## oriented (a level rope sags straight down; this matches gravity, not the
## chord).
const SAG_DIR := Vector2(0.0, 1.0)


## Midpoint droop, in world pixels, of a rope of material length `rope_length`
## whose endpoints are `chord` apart. Modelled as a massless rope folded to a
## single low point directly below the chord midpoint: the two equal halves have
## combined length `rope_length`, so the fold hangs
## `0.5 * sqrt(rope_length^2 - chord^2)` below the chord. This is `0` (a straight
## line) once the rope is taut (`chord >= rope_length`) and grows toward
## `rope_length / 2` as the endpoints meet. Never negative. Pure.
static func sag_depth(chord: float, rope_length: float) -> float:
	if rope_length <= 0.0 or chord >= rope_length:
		return 0.0
	return 0.5 * sqrt(maxf(0.0, rope_length * rope_length - chord * chord))


## The decorative polyline for a rope spanning `a`→`b` with material length
## `rope_length`, in the same space as the endpoints. Returns `segments + 1`
## points: the endpoints verbatim, with the interior points displaced downward
## along a parabola that reaches [method sag_depth] at the midpoint. A taut rope
## (`a.distance_to(b) >= rope_length`) returns a straight chord; a degenerate
## `rope_length <= 0` likewise stays straight. `segments` is clamped to at least
## 1. Pure, so the whole curve is unit-testable without a `Line2D`.
static func sag_points(a: Vector2, b: Vector2, rope_length: float, segments: int = SEGMENTS) -> PackedVector2Array:
	var points := PackedVector2Array()
	var seg := maxi(1, segments)
	var depth := sag_depth(a.distance_to(b), rope_length)
	for i in range(seg + 1):
		var t := float(i) / float(seg)
		# Parabola: 0 at both endpoints, 1 at the midpoint.
		var bow := 4.0 * t * (1.0 - t)
		points.append(a.lerp(b, t) + SAG_DIR * (depth * bow))
	return points

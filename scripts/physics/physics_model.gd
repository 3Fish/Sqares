class_name PhysicsModel
extends RefCounted

## Shared mass / size / health model for the physics system (#96, from #85).
##
## `mass = size * density` is defined exactly once — in [method mass_from_size] —
## and reused for player / bullet / block mass AND for the size-derived block and
## bullet health that Destructible (#97) consumes, so the core formula is never
## duplicated.
##
## Every function is pure (no scene-tree dependency) so the model is covered by
## the headless test suite per `CLAUDE.md`. The density / coupling constants below
## are the per-context `tuning_factor` from #85; they are deliberately
## conservative starting points and are explicitly tuning, not design (final
## balance lands with the playable content in #85/#97).

## Per-context density / tuning constants ("tuning_factor" in #85).
const PLAYER_DENSITY := 0.02
const BULLET_DENSITY := 0.05
## Blocks measure size as area in px², so their density is kept small to land
## block mass in the same rough range as players and bullets.
const BLOCK_DENSITY := 0.001
## Block *health* density, decoupled from the mass density above (#103 A2): block
## durability is tuned independently of how heavy a block is to shove. Sized so a
## player-sized block — the 32×32 `player_size` footprint, area 1024 px² — has
## ~20 health (1024 × 0.02 ≈ 20), destroyed by a single default 25-damage shot,
## and a double-area block has ~40 (two hits). Health scales linearly with area.
const BLOCK_HEALTH_DENSITY := 0.02

## Couples player body size to its health — tankier players are bigger.
const PLAYER_SIZE_PER_HEALTH := 0.5
## Couples bullet size to its damage — harder-hitting bullets are bigger.
const BULLET_SIZE_PER_DAMAGE := 0.02


## The single definition of `mass = size * density`, reused everywhere.
static func mass_from_size(size: float, density: float) -> float:
	return size * density


## Area (px²) of a centred rectangle of full extent `size` — a block's "size".
static func rect_area(size: Vector2) -> float:
	return absf(size.x) * absf(size.y)


# --- Players ----------------------------------------------------------------

## `size = size_stat + health_stat * tuning_factor`.
static func player_size(size_stat: float, health_stat: float) -> float:
	return size_stat + health_stat * PLAYER_SIZE_PER_HEALTH


## `mass = size_stat * tuning_factor`. Drives the push a player exerts on blocks.
static func player_mass(size_stat: float) -> float:
	return mass_from_size(size_stat, PLAYER_DENSITY)


# --- Bullets ----------------------------------------------------------------

## `size = size_stat + damage_stat * tuning_factor` (size_stat = `bullet_scale`).
static func bullet_size(size_stat: float, damage_stat: float) -> float:
	return size_stat + damage_stat * BULLET_SIZE_PER_DAMAGE


## `mass = size * tuning_factor`. Drives the impulse a bullet imparts on impact.
static func bullet_mass(size_stat: float, damage_stat: float) -> float:
	return mass_from_size(bullet_size(size_stat, damage_stat), BULLET_DENSITY)


## `health = damage_stat * tuning_factor`. Part of the unified model; consumed by
## Destructible (#97), provided here so that issue does not re-derive the formula.
static func bullet_health(damage_stat: float) -> float:
	return mass_from_size(damage_stat, BULLET_DENSITY)


# --- Physics blocks ---------------------------------------------------------

## `mass = size * density`, with a block's size being its rectangle area.
static func block_mass(size: Vector2) -> float:
	return mass_from_size(rect_area(size), BLOCK_DENSITY)


## `health = area * health_density`. Routes through the shared `mass_from_size`
## (area × density) definition like block mass, but on its own `BLOCK_HEALTH_DENSITY`
## so durability is decoupled from push mass (#103 A2). Consumed by Destructible
## (#97). Tuned so a player-sized block is destroyed by one default shot (see the
## `BLOCK_HEALTH_DENSITY` note); health scales linearly with the block's area.
static func block_health(size: Vector2) -> float:
	return mass_from_size(rect_area(size), BLOCK_HEALTH_DENSITY)


# --- Push impulse -----------------------------------------------------------

## Impulse a pusher of `pusher_mass` moving at `pusher_velocity` imparts into a
## body it presses against. `contact_normal` points from the pushed body toward
## the pusher (Godot's collision normal as seen by the kinematic pusher); the
## push therefore acts along `-contact_normal`, scaled by the pusher's mass and
## the speed it is driving *into* the body. Returns zero when the pusher is not
## moving into the body (glancing / separating contact). Pure so the push
## strength is unit-tested without a live physics step.
static func push_impulse(pusher_mass: float, pusher_velocity: Vector2, contact_normal: Vector2) -> Vector2:
	var into := pusher_velocity.dot(-contact_normal)
	if into <= 0.0:
		return Vector2.ZERO
	return -contact_normal * (pusher_mass * into)

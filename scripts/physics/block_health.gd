class_name BlockHealth
extends RefCounted

## Damage bookkeeping for a destructible platform block (#97, from #85).
##
## A destructible block's health is derived from its size through the shared
## [PhysicsModel] — `health = area * density`, the same `mass = size * density`
## definition reused for block mass (#96), so the formula is never duplicated.
## This object holds only the per-block health state and the destroy threshold;
## the concrete block nodes ([DestructibleBlock] and a destructible [PhysicsBlock])
## own one and forward bullet damage into it. Pure (no scene-tree dependency) so
## the health/destroy maths are covered by the headless suite per `CLAUDE.md`.

## Maximum (and starting) health, derived from the block's footprint area.
var max_health: float = 0.0
## Remaining health; the block is destroyed once this reaches zero.
var health: float = 0.0


## Builds the health pool for a block of full extent `size`, sizing it from the
## block's area via the single shared formula.
func _init(size: Vector2) -> void:
	max_health = PhysicsModel.block_health(size)
	health = max_health


## Applies `amount` of damage (negative amounts are ignored) and returns true
## when this hit reduces the block to zero health — i.e. when it destroys the
## block. A block already at zero stays destroyed and reports true.
func take(amount: float) -> bool:
	health -= maxf(amount, 0.0)
	if health < 0.0:
		health = 0.0
	return is_destroyed()


## True once health has reached zero.
func is_destroyed() -> bool:
	return health <= 0.0

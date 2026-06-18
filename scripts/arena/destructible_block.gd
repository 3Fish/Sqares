extends StaticBody2D
class_name DestructibleBlock

## A non-physics platform block that can be destroyed (#97 — the Destructible
## flag, from #85).
##
## Built by [ArenaBuilder] from a platform flagged `destructible` but not
## `physics`. It is a solid [StaticBody2D] like a normal platform — players stand
## on it and bullets bounce/stop against it (it is NOT pushable; it receives no
## impulse) — but it also takes bullet damage and, once its size-derived health
## reaches zero, removes itself and emits [signal destroyed]. A Physics **and**
## Destructible block is instead a destructible [PhysicsBlock], which both takes
## damage and is pushable.
##
## Health derives from the block's area through the shared [BlockHealth] /
## [PhysicsModel], so the health formula is defined once and reused.

## Emitted the instant the block is destroyed (health reaches zero), before it
## frees itself. Carries the block so a listener (e.g. a Chain/Rope endpoint in
## #98) can sever its link to this block.
signal destroyed(block: DestructibleBlock)

## Full rectangle extent in pixels; its area drives the block's health.
var block_size: Vector2 = Vector2.ZERO
## Size-derived health pool (shared model). Null until [method configure].
var _health: BlockHealth = null


## Sets the block's footprint and derives its health from the area. Called by
## [ArenaBuilder] at build time. Collision layer stays on the default static
## layer so players and bullets collide with it exactly like a normal platform.
func configure(size: Vector2) -> void:
	block_size = size
	_health = BlockHealth.new(size)


## Remaining health, or zero before the block is configured.
func health() -> float:
	return _health.health if _health else 0.0


## Whether the block has been destroyed.
func is_destroyed() -> bool:
	return _health != null and _health.is_destroyed()


## Applies bullet damage to the block. When the hit reduces health to zero the
## block emits [signal destroyed] and frees itself. A destructible block never
## receives a push impulse (it is static); only its health responds.
func damage_block(amount: float) -> void:
	if _health == null or _health.is_destroyed():
		return
	if _health.take(amount):
		destroyed.emit(self)
		queue_free()

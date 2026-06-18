extends RigidBody2D
class_name PhysicsBlock

## A pushable, gravity-affected platform block (#96 — the Physics flag).
##
## Built by [ArenaBuilder] from a platform flagged `physics`. Unlike the default
## static platforms (`StaticBody2D`), a physics block follows normal RigidBody2D
## physics: it rests under gravity on static geometry, collides with other blocks,
## and is shoved by players and bullets. Its mass derives from its area through
## the shared [PhysicsModel], so the push physics here and the size-derived health
## that Destructible (#97) adds come from one definition.
##
## Players (kinematic) and bullets stay kinematic and only *impart* impulses via
## [method receive_push]; they never become rigid bodies themselves (per #85 Q3).
##
## A physics block can additionally be flagged **Destructible** (#97): it then
## carries a size-derived [BlockHealth], takes bullet damage via
## [method damage_block], and on reaching zero health emits [signal destroyed]
## and frees itself — so a Physics+Destructible block both takes damage and is
## pushable, while a physics-only block is indestructible.

## Emitted the instant a destructible block is destroyed (health reaches zero),
## before it frees itself. Carries the block so a listener (e.g. a Chain/Rope
## endpoint in #98) can sever its link to this block.
signal destroyed(block: PhysicsBlock)

## Collision layers, matching player.tscn / projectile.tscn:
## 1 = static geometry, 2 = players, 4 = projectiles, 8 = physics blocks.
const LAYER_STATIC := 1
const LAYER_PLAYER := 2
const LAYER_BLOCK := 8

## Full rectangle extent in pixels; its area drives mass (and #97 health).
var block_size: Vector2 = Vector2.ZERO
## Size-derived health pool when this block is destructible (#97); null for an
## indestructible physics block.
var _health: BlockHealth = null


## Sets the block's footprint, derives its mass from area via [PhysicsModel], and
## wires its collision layers so it collides with static geometry, players, and
## other blocks. Called by [ArenaBuilder] at build time.
func configure(size: Vector2) -> void:
	block_size = size
	mass = PhysicsModel.block_mass(size)
	collision_layer = LAYER_BLOCK
	collision_mask = LAYER_STATIC | LAYER_PLAYER | LAYER_BLOCK


## Flags this block as destructible (#97), giving it a size-derived health pool.
## Called by [ArenaBuilder] when the platform carries the `destructible` flag.
## Must be called after [method configure] so `block_size` is set. Joins the
## destructible-block group so explosion AoE (#103) can sweep it.
func make_destructible() -> void:
	_health = BlockHealth.new(block_size)
	add_to_group(Projectile.DESTRUCTIBLE_GROUP)


## Whether this block can be destroyed (carries a health pool).
func is_destructible() -> bool:
	return _health != null


## Remaining health, or zero for an indestructible block.
func health() -> float:
	return _health.health if _health else 0.0


## Whether a destructible block has been destroyed.
func is_destroyed() -> bool:
	return _health != null and _health.is_destroyed()


## Applies bullet damage to a destructible block. No-op on an indestructible
## (physics-only) block, so a bullet imparts its push but does no damage. When
## the hit reduces health to zero the block emits [signal destroyed] and frees
## itself. Pushing (impulse) is independent — see [method receive_push].
func damage_block(amount: float) -> void:
	if _health == null or _health.is_destroyed():
		return
	if _health.take(amount):
		destroyed.emit(self)
		queue_free()


## Area of the block's footprint in px² — the "size" in the shared model.
func area() -> float:
	return PhysicsModel.rect_area(block_size)


## Applies an external impulse from a player shove or bullet impact. A thin seam
## so pushers test `has_method("receive_push")` without knowing the concrete type.
func receive_push(impulse: Vector2) -> void:
	apply_central_impulse(impulse)

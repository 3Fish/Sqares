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

## Collision layers, matching player.tscn / projectile.tscn:
## 1 = static geometry, 2 = players, 4 = projectiles, 8 = physics blocks.
const LAYER_STATIC := 1
const LAYER_PLAYER := 2
const LAYER_BLOCK := 8

## Full rectangle extent in pixels; its area drives mass (and #97 health).
var block_size: Vector2 = Vector2.ZERO


## Sets the block's footprint, derives its mass from area via [PhysicsModel], and
## wires its collision layers so it collides with static geometry, players, and
## other blocks. Called by [ArenaBuilder] at build time.
func configure(size: Vector2) -> void:
	block_size = size
	mass = PhysicsModel.block_mass(size)
	collision_layer = LAYER_BLOCK
	collision_mask = LAYER_STATIC | LAYER_PLAYER | LAYER_BLOCK


## Area of the block's footprint in px² — the "size" in the shared model.
func area() -> float:
	return PhysicsModel.rect_area(block_size)


## Applies an external impulse from a player shove or bullet impact. A thin seam
## so pushers test `has_method("receive_push")` without knowing the concrete type.
func receive_push(impulse: Vector2) -> void:
	apply_central_impulse(impulse)

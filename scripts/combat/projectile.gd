extends CharacterBody2D
class_name Projectile

## Fraction of world gravity applied to bullets, giving them an arc.
const GRAVITY_SCALE := 1.0
## Max course-correction, in radians/second, applied at homing strength 1.0.
## Scaled linearly by the bullet_homing stat (0 = none, 1 = full).
const HOMING_TURN_RATE := 6.0
## Scene group that homing bullets steer toward and knockback can push.
const TARGET_GROUP := "players"

var damage: float = 25.0
var lifesteal: float = 0.0
var bounces_remaining: int = 0
var homing: float = 0.0
var knockback_force: float = 0.0
var explosion_radius: float = 0.0
var shooter: Node = null

var _lifetime: float = 6.0
var _base_gravity: float


func setup(
	direction: Vector2,
	speed: float,
	p_damage: float,
	p_scale: float,
	p_bounces: int,
	p_lifesteal: float,
	p_shooter: Node,
	p_homing: float = 0.0,
	p_knockback: float = 0.0,
	p_explosion_radius: float = 0.0,
) -> void:
	velocity          = direction.normalized() * speed
	damage            = p_damage
	scale             = Vector2.ONE * p_scale
	bounces_remaining = p_bounces
	lifesteal         = p_lifesteal
	homing            = p_homing
	knockback_force   = p_knockback
	explosion_radius  = p_explosion_radius
	shooter           = p_shooter


func _ready() -> void:
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)


func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	if homing > 0.0:
		var target := _find_nearest_target()
		if target:
			velocity = compute_homing_velocity(
				velocity, global_position, target.global_position, homing, delta
			)

	velocity.y += _base_gravity * GRAVITY_SCALE * delta

	var collision := move_and_collide(velocity * delta)
	if not collision:
		return

	var collider := collision.get_collider()
	if collider.has_method("take_damage"):
		collider.take_damage(damage, shooter if is_instance_valid(shooter) else null)
		if knockback_force > 0.0 and collider.has_method("apply_knockback"):
			collider.apply_knockback(velocity.normalized() * knockback_force)
		if explosion_radius > 0.0:
			_detonate(collision.get_position(), collider)
		if lifesteal > 0.0 and is_instance_valid(shooter) and shooter.has_method("heal"):
			shooter.heal(lifesteal)
		SfxDirector.play(SfxDirector.HIT)
		EffectEngine.notify_hit(shooter if is_instance_valid(shooter) else null, collider, self, damage)
		queue_free()
	elif bounces_remaining > 0:
		velocity = velocity.bounce(collision.get_normal())
		bounces_remaining -= 1
		SfxDirector.play(SfxDirector.BOUNCE)
	else:
		queue_free()


## Rotates `p_velocity` toward `target_position`, clamped to the per-frame turn
## budget derived from `homing`. Speed (magnitude) is preserved. Pure function so
## the steering math can be unit-tested without a scene.
static func compute_homing_velocity(
	p_velocity: Vector2,
	p_position: Vector2,
	target_position: Vector2,
	p_homing: float,
	delta: float,
) -> Vector2:
	if p_homing <= 0.0 or p_velocity == Vector2.ZERO:
		return p_velocity
	var desired := target_position - p_position
	if desired == Vector2.ZERO:
		return p_velocity
	var max_turn := HOMING_TURN_RATE * clampf(p_homing, 0.0, 1.0) * delta
	var step := clampf(p_velocity.angle_to(desired), -max_turn, max_turn)
	return p_velocity.rotated(step)


## Deals AoE damage to every combatant within `explosion_radius` of `center`,
## excluding the shooter (no self-damage) and the directly-hit target (which has
## already taken the impact damage). Splash victims take the full bullet `damage`;
## blast falloff and team/friendly-fire filtering are deferred tuning (see #26).
func _detonate(center: Vector2, direct_target: Node) -> void:
	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		if node == shooter or node == direct_target or not (node is Node2D):
			continue
		if not node.has_method("take_damage"):
			continue
		if is_in_blast_radius(center, (node as Node2D).global_position, explosion_radius):
			node.take_damage(damage, shooter if is_instance_valid(shooter) else null)


## True when `point` lies within `radius` of `center` (inclusive of the edge).
## A non-positive radius means no blast. Pure function so the AoE selection can
## be unit-tested without a scene.
static func is_in_blast_radius(center: Vector2, point: Vector2, radius: float) -> bool:
	if radius <= 0.0:
		return false
	return center.distance_squared_to(point) <= radius * radius


## Nearest living combatant (group member) other than the shooter, or null.
func _find_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		if node == shooter or not (node is Node2D):
			continue
		var d: float = global_position.distance_squared_to((node as Node2D).global_position)
		if d < best:
			best = d
			nearest = node
	return nearest

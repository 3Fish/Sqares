extends CharacterBody2D
class_name Projectile

## Fraction of world gravity applied to bullets, giving them an arc.
const GRAVITY_SCALE := 1.0

var damage: float = 25.0
var lifesteal: float = 0.0
var bounces_remaining: int = 0
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
) -> void:
	velocity          = direction.normalized() * speed
	damage            = p_damage
	scale             = Vector2.ONE * p_scale
	bounces_remaining = p_bounces
	lifesteal         = p_lifesteal
	shooter           = p_shooter


func _ready() -> void:
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)


func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	velocity.y += _base_gravity * GRAVITY_SCALE * delta

	var collision := move_and_collide(velocity * delta)
	if not collision:
		return

	var collider := collision.get_collider()
	if collider != shooter and collider.has_method("take_damage"):
		collider.take_damage(damage, shooter)
		if lifesteal > 0.0 and is_instance_valid(shooter) and shooter.has_method("heal"):
			shooter.heal(lifesteal)
		queue_free()
	elif bounces_remaining > 0:
		velocity = velocity.bounce(collision.get_normal())
		bounces_remaining -= 1
	else:
		queue_free()

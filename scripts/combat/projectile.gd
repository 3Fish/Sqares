extends CharacterBody2D
class_name Projectile

## Fraction of world gravity applied to bullets, giving them an arc.
const GRAVITY_SCALE := 0.35
## Seconds after spawn during which the bullet cannot collide with its shooter.
const SHOOTER_GRACE_TIME := 0.2

var damage: float = 25.0
var lifesteal: float = 0.0
var bounces_remaining: int = 0
var shooter: Node = null

var _lifetime: float = 6.0
var _shooter_grace: float = 0.0
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
	_shooter_grace    = SHOOTER_GRACE_TIME


func _ready() -> void:
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	if is_instance_valid(shooter) and shooter is PhysicsBody2D:
		add_collision_exception_with(shooter)


func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	velocity.y += _base_gravity * GRAVITY_SCALE * delta

	if _shooter_grace > 0.0:
		_shooter_grace -= delta
		if _shooter_grace <= 0.0 and is_instance_valid(shooter) and shooter is PhysicsBody2D:
			remove_collision_exception_with(shooter)

	var collision := move_and_collide(velocity * delta)
	if not collision:
		return

	var collider := collision.get_collider()
	if collider.has_method("take_damage"):
		collider.take_damage(damage, shooter)
		if lifesteal > 0.0 and is_instance_valid(shooter) and shooter.has_method("heal"):
			shooter.heal(lifesteal)
		queue_free()
	elif bounces_remaining > 0:
		velocity = velocity.bounce(collision.get_normal())
		bounces_remaining -= 1
	else:
		queue_free()

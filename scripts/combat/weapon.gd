extends Node2D
class_name Weapon

var damage: float = 25.0
var fire_rate: float = 1.0
var bullet_speed: float = 800.0
var bullet_scale: float = 1.0
var bullet_bounces: int = 0
var bullet_homing: float = 0.0
var lifesteal: float = 0.0
var knockback_force: float = 0.0
var explosion_radius: float = 0.0

var _cooldown: float = 0.0
var _projectile_scene: PackedScene


func _ready() -> void:
	_projectile_scene = preload("res://scenes/combat/projectile.tscn")


func apply_stats(stats: Dictionary) -> void:
	damage         = stats.get("damage",          damage)
	fire_rate      = stats.get("fire_rate",        fire_rate)
	bullet_speed   = stats.get("bullet_speed",     bullet_speed)
	bullet_scale   = stats.get("bullet_scale",     bullet_scale)
	bullet_bounces = int(stats.get("bullet_bounces", float(bullet_bounces)))
	bullet_homing  = stats.get("bullet_homing",     bullet_homing)
	lifesteal      = stats.get("lifesteal",        lifesteal)
	knockback_force = stats.get("knockback_force",  knockback_force)
	explosion_radius = stats.get("explosion_radius", explosion_radius)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Fires a projectile in `direction` unless cooling down. Returns the spawned
## projectile (so callers can replicate or track it, #27) or null when the
## shot was refused. `net_id` tags a host-confirmed shot with the shooter
## client's predicted-projectile id so the broadcast can echo it.
func try_fire(direction: Vector2, net_id: String = "") -> Projectile:
	if _cooldown > 0.0 or direction == Vector2.ZERO:
		return null
	_cooldown = 1.0 / maxf(fire_rate, 0.1)
	return _spawn_projectile(direction, net_id)


func _spawn_projectile(direction: Vector2, net_id: String) -> Projectile:
	var proj: Projectile = _projectile_scene.instantiate()
	proj.setup(
		direction, bullet_speed, damage, bullet_scale, bullet_bounces, lifesteal,
		get_parent(), bullet_homing, knockback_force, explosion_radius,
	)
	proj.net_id = net_id
	# Hit detection and damage are host-only (#27): every projectile spawned on
	# a client — its own predicted shots included — is purely visual.
	proj.visual_only = NetworkManager.is_client()
	proj.global_position = global_position + direction.normalized() * 48.0
	get_tree().current_scene.add_child(proj)
	SfxDirector.play(SfxDirector.SHOOT)
	if not proj.visual_only:
		# Let card effects react to / mutate the freshly spawned shot. Effects
		# run where damage is adjudicated, so visual-only instances skip this.
		EffectEngine.notify_shoot(get_parent(), self, proj, direction)
	if NetworkManager.is_host():
		# Broadcast after effects so the wire carries the post-mutation shot.
		NetReplicator.broadcast_projectile(proj, get_parent().player_id)
	return proj

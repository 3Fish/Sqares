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
## Magazine capacity in rounds and the idle time (seconds since the last shot)
## after which the magazine snaps back to full (#113). Both are registered,
## card-tunable stats; `reload_time` is a duration, so a smaller value reloads
## sooner.
var magazine_size: int = 3
var reload_time: float = 1.0

var _cooldown: float = 0.0
## Rounds currently in the magazine, and the time since ammo was last consumed.
## `_ammo` reloads to `magazine_size` once `_idle_time` reaches `reload_time`.
var _ammo: int = 3
var _idle_time: float = 0.0
## Shots whose `delay` has not yet elapsed (#113). Each entry is
## {spec, direction, net_id, remaining}; advanced in `_physics_process` and
## spawned when `remaining` hits zero. Cancelled wholesale on trigger-release /
## death / round-end (see `clear_pending`).
var _pending: Array = []
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
	magazine_size  = int(stats.get("magazine_size", float(magazine_size)))
	reload_time    = stats.get("reload_time",       reload_time)


## Refills the magazine and clears any in-flight delayed shots. Called at round
## start so every player begins with a full magazine (#113) and no stale pending
## shots carried over from the previous round.
func reset_ammo() -> void:
	_ammo = magazine_size
	_idle_time = 0.0
	_pending.clear()


## Rounds currently in the magazine. Exposed for a future ammo HUD (#113 A4).
func get_ammo() -> int:
	return _ammo


## Cancels every delayed shot still waiting to spawn (#113): a released trigger,
## a death, or a round end abandons the pending shot rather than firing it late.
func clear_pending() -> void:
	_pending.clear()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_tick_reload(delta)
	# Between/after rounds combatants are frozen (#70); a shot queued just before
	# the round ended is abandoned rather than firing into the next state (#113).
	if not GameManager.is_gameplay_active(GameManager.state):
		_pending.clear()
		return
	_advance_pending(delta)


## Fires in `direction` unless cooling down. Returns the spawned projectile (so
## callers can replicate or track it, #27) — the first one for a multi-bullet
## shot — or null when the shot was refused or cancelled. `net_id` tags a
## host-confirmed shot with the shooter client's predicted-projectile id so the
## broadcast can echo it.
##
## Before anything spawns, card effects get to reshape the shot through a mutable
## `ShotSpec` (#68): they may change the bullet count, override the per-bullet
## stats, or cancel the shot entirely. A cancelled (or zero-count) shot is a true
## no-op — no projectile and no cooldown consumed.
func try_fire(direction: Vector2, net_id: String = "") -> Projectile:
	if _cooldown > 0.0 or direction == Vector2.ZERO:
		return null
	var spec := _build_shot_spec()
	# Pre-shoot effects run only where the shot is adjudicated (host/local), so a
	# client's predicted shot keeps the default single-bullet spec — mirroring how
	# on_shoot dispatch is host-only. (A client has no attached effects yet, #82.)
	# Ammo is authority-side for the same reason (#113 A6): a pure client predicts
	# its shots cooldown-gated and visual-only, and the host's ammo gate decides
	# truth (rejecting a predicted shot it had no rounds for), so the client never
	# tracks ammo locally.
	if not NetworkManager.is_client():
		EffectEngine.notify_before_shoot(get_parent(), self, spec, direction)
		if not AmmoModel.can_fire(_ammo, spec.ammo_cost):
			return null  # #113 A3: magazine can't cover the cost — shot denied.
		if spec.ammo_cost > 0:
			# #113 A5: ammo is consumed by the chain's resulting cost even when an
			# effect cancels the shot (a free cancel must also zero ammo_cost).
			# Drawing rounds restarts the idle-reload clock.
			_ammo = AmmoModel.consume(_ammo, spec.ammo_cost)
			_idle_time = 0.0
	if not spec.fires():
		return null
	# Cooldown is charged from the trigger pull, never the (possibly delayed) spawn
	# (#113): a delayed shot still gates the next trigger from now.
	_cooldown = 1.0 / maxf(fire_rate, 0.1)
	if spec.delay > 0.0:
		# Schedule the spawn for `delay` seconds from now. Online replication of a
		# delayed shot rides the netcode work (#113 A6); for now a delayed shot
		# returns null (no synchronous projectile to echo to a fire intent).
		_pending.append({
			"spec": spec, "direction": direction, "net_id": net_id, "remaining": spec.delay,
		})
		return null
	return _fire_spec(spec, direction, net_id)


## Spawns every bullet of a (final, firing) spec in `direction` and returns the
## first projectile — the shared spawn path for an immediate shot and a delayed
## one whose timer has elapsed.
func _fire_spec(spec: ShotSpec, direction: Vector2, net_id: String) -> Projectile:
	var first: Projectile = null
	for i in spec.bullet_count:
		# All bullets share one spec (#68). Only the first carries the net id so a
		# host-confirmed multi-shot still echoes the client's predicted bullet.
		var proj := _spawn_projectile(spec, direction, net_id if i == 0 else "")
		if first == null:
			first = proj
	return first


## Reloads the magazine once the player has been idle long enough (#113). Pure
## with respect to the scene tree, so the reload cadence is unit-testable by
## calling it directly.
func _tick_reload(delta: float) -> void:
	if _ammo >= magazine_size:
		return
	_idle_time += delta
	_ammo = AmmoModel.reloaded(_ammo, magazine_size, _idle_time, reload_time)


## Advances each pending (delayed) shot and spawns the ones whose timer elapsed
## this tick (#113).
func _advance_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	var still_waiting: Array = []
	for entry in _pending:
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			_fire_spec(entry["spec"], entry["direction"], entry["net_id"])
		else:
			still_waiting.append(entry)
	_pending = still_waiting


## A ShotSpec seeded from this weapon's current stats, for effects to reshape.
func _build_shot_spec() -> ShotSpec:
	return ShotSpec.new(
		damage, bullet_speed, bullet_scale, bullet_bounces,
		bullet_homing, lifesteal, knockback_force, explosion_radius,
	)


func _spawn_projectile(spec: ShotSpec, direction: Vector2, net_id: String) -> Projectile:
	var proj: Projectile = _projectile_scene.instantiate()
	proj.setup(
		direction, spec.speed, spec.damage, spec.scale, spec.bounces, spec.lifesteal,
		get_parent(), spec.homing, spec.knockback, spec.explosion_radius,
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

extends CharacterBody2D
class_name Player

## Coyote time: grace window after walking off a ledge where jumping still works.
const COYOTE_TIME := 0.12
## Jump buffer: queued jump fires on landing if pressed this many seconds early.
const JUMP_BUFFER_TIME := 0.12
## Wall-slide multiplier applied to gravity when pressing into a wall mid-air.
const WALL_SLIDE_GRAVITY_MULT := 0.2
## Ground acceleration in pixels/s².
const ACCELERATION := 1800.0
## Deceleration (friction) when no input, in pixels/s².
const FRICTION := 2400.0
## Terminal fall speed in pixels/s.
const MAX_FALL_SPEED := 900.0

var player_id: int = 0
var stats: PlayerStats
var move_speed: float
var jump_force: float
var gravity_scale: float

var _base_gravity: float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _facing_dir: float = 1.0
var _dead: bool = false

@onready var health: Health = $Health
@onready var weapon: Weapon = $Weapon

signal player_died(player: Player, killer: Node)


func _ready() -> void:
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	stats = PlayerStats.new(StatRegistry.get_defaults())
	_sync_stats(true)
	health.died.connect(_on_died)
	add_to_group(Projectile.TARGET_GROUP)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var on_floor := is_on_floor()  # prev frame result — consistent reference for this tick
	_tick_coyote(delta, on_floor)
	_was_on_floor = on_floor
	_tick_jump_buffer(delta)
	_apply_gravity(delta)
	_apply_horizontal(delta)
	_try_jump()
	_handle_shoot()
	move_and_slide()


# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------

func _tick_coyote(delta: float, on_floor: bool) -> void:
	# _was_on_floor is frame N-2; on_floor is frame N-1 — transition is detectable.
	if _was_on_floor and not on_floor and velocity.y >= 0.0:
		_coyote_timer = COYOTE_TIME
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _tick_jump_buffer(delta: float) -> void:
	if Input.is_action_just_pressed("p%d_jump" % (player_id + 1)):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
		return
	var grav_mult := gravity_scale
	if _is_wall_sliding():
		velocity.y = maxf(velocity.y, 0.0)  # kill upward momentum on wall contact
		grav_mult *= WALL_SLIDE_GRAVITY_MULT
	velocity.y = minf(velocity.y + _base_gravity * grav_mult * delta, MAX_FALL_SPEED)


func _apply_horizontal(delta: float) -> void:
	var dir := Input.get_axis("p%d_move_left" % (player_id + 1), "p%d_move_right" % (player_id + 1))
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * move_speed, ACCELERATION * delta)
		_facing_dir = sign(dir)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)


func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if _is_wall_sliding():
		velocity.y = -jump_force
		velocity.x = get_wall_normal().x * move_speed
		_jump_buffer_timer = 0.0
		return
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	if can_jump:
		velocity.y = -jump_force
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0


func _is_wall_sliding() -> bool:
	if not is_on_wall() or is_on_floor():
		return false
	var dir := Input.get_axis("p%d_move_left" % (player_id + 1), "p%d_move_right" % (player_id + 1))
	if dir == 0.0:
		return false
	# True when the player is pressing into (not away from) the wall.
	return sign(dir) == -sign(get_wall_normal().x)


# ---------------------------------------------------------------------------
# Combat helpers
# ---------------------------------------------------------------------------

func _handle_shoot() -> void:
	if not Input.is_action_pressed("p%d_shoot" % (player_id + 1)):
		return
	weapon.try_fire(_get_aim_direction())


func _get_aim_direction() -> Vector2:
	# Gamepad right stick takes priority over mouse.
	var stick := Vector2(
		Input.get_axis("p%d_aim_left" % (player_id + 1), "p%d_aim_right" % (player_id + 1)),
		Input.get_axis("p%d_aim_up" % (player_id + 1),   "p%d_aim_down" % (player_id + 1)),
	)
	if stick.length_squared() > 0.25:
		return stick.normalized()
	var aim := get_global_mouse_position() - weapon.global_position
	if aim == Vector2.ZERO:
		return Vector2(_facing_dir, 0.0)
	return aim.normalized()


func take_damage(amount: float, attacker: Node = null) -> void:
	health.take_damage(amount, attacker)


func heal(amount: float) -> void:
	health.heal(amount)


## Applies an external impulse (e.g. a knocking-back projectile hit). Ignored
## while dead so a killing blow doesn't fling a frozen corpse.
func apply_knockback(impulse: Vector2) -> void:
	if _dead:
		return
	velocity += impulse


func _on_died(killer: Node) -> void:
	_dead = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	# Dead players stop being homing/knockback targets until they respawn.
	remove_from_group(Projectile.TARGET_GROUP)
	player_died.emit(self, killer)


func respawn(spawn_position: Vector2) -> void:
	_dead = false
	global_position = spawn_position
	velocity = Vector2.ZERO
	health.reset()
	set_physics_process(true)
	if not is_in_group(Projectile.TARGET_GROUP):
		add_to_group(Projectile.TARGET_GROUP)


# ---------------------------------------------------------------------------
# Public API (used by card effects and game manager)
# ---------------------------------------------------------------------------

## Merges overrides into this player's runtime stats and propagates to components.
## Pass an empty dict to recompute from the current stats without changing values.
func apply_stats(overrides: Dictionary) -> void:
	stats.merge(overrides)
	_sync_stats()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Propagates the current PlayerStats to all component nodes.
## Pass initialize_health=true at round start to reset HP; false during mid-match card apply.
func _sync_stats(initialize_health: bool = false) -> void:
	var d := stats.to_dict()
	move_speed    = d.get("move_speed",    300.0)
	jump_force    = d.get("jump_force",    550.0)
	gravity_scale = d.get("gravity_scale", 1.0)
	if initialize_health:
		health.initialize(d)
	else:
		health.apply_stats(d)
	weapon.apply_stats(d)

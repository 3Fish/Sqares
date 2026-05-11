extends CharacterBody2D
class_name Player

## Coyote time: grace window after walking off a ledge where jumping still works.
const COYOTE_TIME := 0.12
## Jump buffer: queued jump fires on landing if pressed this many seconds early.
const JUMP_BUFFER_TIME := 0.12
## Wall-slide multiplier applied to gravity when pressing into a wall mid-air.
const WALL_SLIDE_GRAVITY_MULT := 0.2

var move_speed: float
var jump_force: float
var gravity_scale: float

var _base_gravity: float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false


func _ready() -> void:
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var defaults := StatRegistry.get_defaults()
	move_speed    = defaults.get("move_speed",    300.0)
	jump_force    = defaults.get("jump_force",    550.0)
	gravity_scale = defaults.get("gravity_scale", 1.0)


func _physics_process(delta: float) -> void:
	_tick_coyote(delta)
	_tick_jump_buffer(delta)
	_apply_gravity(delta)
	_apply_horizontal()
	_try_jump()
	move_and_slide()
	_was_on_floor = is_on_floor()


# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------

func _tick_coyote(delta: float) -> void:
	# Start coyote window the first frame we leave the floor without jumping.
	if _was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		_coyote_timer = COYOTE_TIME
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _tick_jump_buffer(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
		return
	var grav_mult := gravity_scale
	if _is_wall_sliding():
		grav_mult *= WALL_SLIDE_GRAVITY_MULT
	velocity.y += _base_gravity * grav_mult * delta


func _apply_horizontal() -> void:
	velocity.x = Input.get_axis("move_left", "move_right") * move_speed


func _try_jump() -> void:
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	if _jump_buffer_timer > 0.0 and can_jump:
		velocity.y = -jump_force
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0


func _is_wall_sliding() -> bool:
	if not is_on_wall() or is_on_floor():
		return false
	var dir := Input.get_axis("move_left", "move_right")
	if dir == 0.0:
		return false
	# True when the player is pressing into (not away from) the wall.
	return sign(dir) == -sign(get_wall_normal().x)


# ---------------------------------------------------------------------------
# Public API (used by card effects and game manager)
# ---------------------------------------------------------------------------

func apply_stats(stats: Dictionary) -> void:
	move_speed    = stats.get("move_speed",    move_speed)
	jump_force    = stats.get("jump_force",    jump_force)
	gravity_scale = stats.get("gravity_scale", gravity_scale)

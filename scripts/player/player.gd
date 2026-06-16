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
## Max position error, in pixels, tolerated between this client's prediction
## and the host's authoritative state before rewinding + replaying (#27).
const RECONCILE_TOLERANCE := 8.0
## How far behind the newest received snapshot a PUPPET is rendered, in seconds
## (#28). One render delay of buffer means there is almost always a future
## sample to interpolate toward, so motion stays continuous instead of stepping
## at the ~30 Hz net tick. ~2 net ticks; a feel constant — PUPPETs are
## display-only, so this never affects host-authoritative outcomes.
const PUPPET_INTERP_DELAY := 0.1

## Who drives this player's simulation (#27):
## - LOCAL: samples this machine's input and simulates authoritatively
##   (offline players, and the host's own player).
## - PREDICTED: a networked client's own player — samples local input, applies
##   it immediately for responsiveness, and is corrected against host
##   snapshots (rewind + replay on disagreement).
## - SIMULATED: the host's stand-in for a remote client, driven by that
##   client's replicated input stream. Shots fire via reliable fire intents
##   (which carry the exact aim + projectile id), not the input's shoot bit.
## - PUPPET: a client's view of any other player — no simulation; position,
##   velocity, and health are applied directly from snapshots.
enum NetRole { LOCAL, PREDICTED, SIMULATED, PUPPET }

var player_id: int = 0
## Action-map id this player samples ("p%d_*" with id + 1). Defaults to
## player_id; a networked client's own player overrides this to 0 so the
## machine's primary (p1) bindings drive it regardless of its slot.
var input_id: int = -1
var net_role: NetRole = NetRole.LOCAL
var stats: PlayerStats
var move_speed: float
var jump_force: float
var gravity_scale: float

## Client-side prediction history for reconciliation (#27).
var prediction := NetPrediction.new()
## Client-side snapshot buffer for smoothing a PUPPET's motion (#28). Fed by
## NetReplicator on each snapshot; sampled in the PUPPET physics step.
var interpolation := NetInterpolation.new()

var _base_gravity: float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _facing_dir: float = 1.0
var _dead: bool = false
var _input_seq: int = 0
## Last replicated input a SIMULATED player applied; held across ticks the
## input stream skips so packet loss doesn't read as a released stick.
var _last_net_input: NetPlayerInput = null

@onready var health: Health = $Health
@onready var weapon: Weapon = $Weapon

signal player_died(player: Player, killer: Node)


func _ready() -> void:
	if input_id < 0:
		input_id = player_id
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	stats = PlayerStats.new(StatRegistry.get_defaults())
	_sync_stats(true)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	add_to_group(Projectile.TARGET_GROUP)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not GameManager.is_gameplay_active(GameManager.state):
		# Between/after rounds (the "wins the round" message, the card-selection
		# overlay, the victory screen) combatants are frozen so the surviving
		# player can't keep moving while losers pick cards (#70).
		return
	match net_role:
		NetRole.LOCAL:
			_step(_sample_input(), delta)
		NetRole.PREDICTED:
			var input := _sample_input()
			_step(input, delta)
			prediction.record(input, global_position, velocity)
			NetReplicator.send_player_inputs(self)
		NetRole.SIMULATED:
			var input: NetPlayerInput = NetReplicator.pull_input(player_id)
			if input == null:
				# No fresh input this tick (loss / jitter): hold the previous
				# stick state, but never replay a one-shot jump press.
				input = _last_net_input if _last_net_input != null else NetPlayerInput.new()
				input.jump = false
			_last_net_input = input
			_step(input, delta)
		NetRole.PUPPET:
			# State arrives via snapshots (NetReplicator pushes them into the
			# buffer); render a smoothed point slightly behind live (#28).
			_apply_interpolation()


# ---------------------------------------------------------------------------
# Simulation step (shared by local play, host simulation, and replay)
# ---------------------------------------------------------------------------

## Advances one physics tick from an explicit input. `replay` suppresses
## shooting so a reconciliation replay can't re-fire already-sent shots.
func _step(input: NetPlayerInput, delta: float, replay: bool = false) -> void:
	var on_floor := is_on_floor()  # prev frame result — consistent reference for this tick
	_tick_coyote(delta, on_floor)
	_was_on_floor = on_floor
	_tick_jump_buffer(delta, input.jump)
	_apply_gravity(delta, input.move_axis)
	_apply_horizontal(delta, input.move_axis)
	_try_jump(input.move_axis)
	if not replay:
		_handle_shoot(input)
	move_and_slide()


## Samples this machine's input for one tick. Each sample takes the next
## sequence number so a PREDICTED player's stream is host-ackable; for LOCAL
## players the seq is simply unused.
func _sample_input() -> NetPlayerInput:
	var input := NetPlayerInput.new()
	_input_seq += 1
	input.seq = _input_seq
	var p := input_id + 1
	input.move_axis = Input.get_axis("p%d_move_left" % p, "p%d_move_right" % p)
	input.jump = Input.is_action_just_pressed("p%d_jump" % p)
	input.shoot = Input.is_action_pressed("p%d_shoot" % p)
	if input.shoot:
		input.aim = _get_aim_direction()
	return input


# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------

func _tick_coyote(delta: float, on_floor: bool) -> void:
	# _was_on_floor is frame N-2; on_floor is frame N-1 — transition is detectable.
	if _was_on_floor and not on_floor and velocity.y >= 0.0:
		_coyote_timer = COYOTE_TIME
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _tick_jump_buffer(delta: float, jump_pressed: bool) -> void:
	if jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER_TIME
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float, move_axis: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
		return
	var grav_mult := gravity_scale
	if _is_wall_sliding(move_axis):
		velocity.y = maxf(velocity.y, 0.0)  # kill upward momentum on wall contact
		grav_mult *= WALL_SLIDE_GRAVITY_MULT
	velocity.y = minf(velocity.y + _base_gravity * grav_mult * delta, MAX_FALL_SPEED)


func _apply_horizontal(delta: float, move_axis: float) -> void:
	if move_axis != 0.0:
		velocity.x = move_toward(velocity.x, move_axis * move_speed, ACCELERATION * delta)
		_facing_dir = sign(move_axis)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)


func _try_jump(move_axis: float) -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if _is_wall_sliding(move_axis):
		velocity.y = -jump_force
		velocity.x = get_wall_normal().x * move_speed
		_jump_buffer_timer = 0.0
		return
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	if can_jump:
		velocity.y = -jump_force
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0


func _is_wall_sliding(move_axis: float) -> bool:
	if not is_on_wall() or is_on_floor():
		return false
	if move_axis == 0.0:
		return false
	# True when the player is pressing into (not away from) the wall.
	return sign(move_axis) == -sign(get_wall_normal().x)


# ---------------------------------------------------------------------------
# Combat helpers
# ---------------------------------------------------------------------------

func _handle_shoot(input: NetPlayerInput) -> void:
	if not input.shoot:
		return
	match net_role:
		NetRole.PREDICTED:
			# Fire a local visual-only shot immediately for responsiveness; the
			# host validates the intent and replicates the authoritative
			# projectile back, echoing the predicted instance's id (#27).
			var predicted := weapon.try_fire(input.aim)
			if predicted:
				NetReplicator.send_fire_intent(self, predicted, input.aim)
		NetRole.SIMULATED:
			pass  # the host fires on the client's reliable fire intent instead
		_:
			weapon.try_fire(input.aim)


func _get_aim_direction() -> Vector2:
	var p := input_id + 1
	# Gamepad right stick takes priority over mouse.
	var stick := Vector2(
		Input.get_axis("p%d_aim_left" % p, "p%d_aim_right" % p),
		Input.get_axis("p%d_aim_up" % p,   "p%d_aim_down" % p),
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


# ---------------------------------------------------------------------------
# Reconciliation (client-side, #27)
# ---------------------------------------------------------------------------

## Applies an authoritative snapshot state to this PREDICTED player: health is
## adopted outright (damage is host-only), the prediction history is acked up
## to the host's last processed input, and — when the authoritative position
## disagrees beyond RECONCILE_TOLERANCE — the player rewinds to the host state
## and replays its still-pending inputs.
func reconcile(auth: NetPlayerState) -> void:
	health.current_hp = auth.health
	var predicted = prediction.state_at(auth.last_input_seq)
	prediction.ack(auth.last_input_seq)
	if predicted == null:
		return  # ack predates / outruns our history; nothing to compare
	if not NetPrediction.needs_correction(predicted["position"], auth.position, RECONCILE_TOLERANCE):
		return
	global_position = auth.position
	velocity = auth.velocity
	var delta := get_physics_process_delta_time()
	for entry in prediction.pending():
		_step(entry["input"], delta, true)
		entry["position"] = global_position
		entry["velocity"] = velocity


## Renders this PUPPET at a smoothed, slightly-delayed position interpolated
## between buffered snapshots (#28). Health is not interpolated — it is adopted
## outright when each snapshot lands (NetReplicator). Before the buffer holds a
## usable sample (the first packet of a round), nothing is applied and the node
## keeps its spawn position.
func _apply_interpolation() -> void:
	var render_time := NetReplicator.net_time_seconds() - PUPPET_INTERP_DELAY
	var state := interpolation.sample(render_time)
	if state.is_empty():
		return
	global_position = state["position"]
	velocity = state["velocity"]


func _on_damaged(amount: float, attacker: Node) -> void:
	# Forwards damage this player actually took to the effect engine so the
	# victim's defensive / retaliation effects (`on_take_damage`) fire. Fed by
	# `Health.damaged`, which only emits when HP is lost.
	EffectEngine.notify_take_damage(self, attacker, amount)


func _on_died(killer: Node) -> void:
	_dead = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	# Dead players stop being homing/knockback targets until they respawn.
	remove_from_group(Projectile.TARGET_GROUP)
	SfxDirector.play(SfxDirector.DEATH)
	player_died.emit(self, killer)


func respawn(spawn_position: Vector2) -> void:
	_dead = false
	global_position = spawn_position
	velocity = Vector2.ZERO
	health.reset()
	# Drop any snapshot samples from the previous round so a freshly spawned
	# PUPPET doesn't interpolate toward stale positions (#28).
	interpolation.clear()
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

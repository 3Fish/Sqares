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
## Display name chosen for this player in match setup (#132). Local identity only;
## surfaced by the team-win announcement (#134). Defaults empty until applied.
var player_name: String = ""
## Action-map id this player samples ("p%d_*" with id + 1). Defaults to
## player_id; a networked client's own player overrides this to 0 so the
## machine's primary (p1) bindings drive it regardless of its slot.
var input_id: int = -1
var net_role: NetRole = NetRole.LOCAL
var stats: PlayerStats
var move_speed: float
var jump_force: float
var gravity_scale: float
## Physics mass derived from the player's size stat (#96). Drives how hard this
## player shoves physics blocks; players stay kinematic and never get shoved.
var mass: float

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
## Damaging-elastic-border state (#84). True while this player's body is touching
## or past a map border; `_border_damage_timer` counts down to the next 50-damage
## tick during that excursion. Both reset on re-entry and on respawn.
var _out_of_bounds: bool = false
var _border_damage_timer: float = 0.0
## Body half-extents used for the border contact test, read from the collision
## shape at `_ready` (falls back to the player.tscn rectangle half-size).
var _body_half_extent: Vector2 = Vector2(14.0, 20.0)

@onready var health: Health = $Health
@onready var weapon: Weapon = $Weapon

signal player_died(player: Player, killer: Node)


func _ready() -> void:
	if input_id < 0:
		input_id = player_id
	_base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	stats = PlayerStats.new(StatRegistry.get_defaults())
	_sync_stats(true)
	# Every round spawns a fresh player node, so this is the round-start seam: each
	# player begins the round with a full magazine (#113).
	weapon.reset_ammo()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	add_to_group(Projectile.TARGET_GROUP)
	# Cache the body's half-extents for the map-border contact test (#84) from the
	# actual collision shape, so the boundary keys off the real footprint.
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		_body_half_extent = (shape_node.shape as RectangleShape2D).size * 0.5


## Applies this player's match-setup identity (#132): records the chosen name and
## tints the character's Visual to the chosen palette colour. Cosmetic and local —
## the HUD keeps its own pip palette (maintainer A3). Safe to call after the node
## is in the tree (MatchDirector calls it right after `add_child`).
func apply_appearance(p_color: Color, p_name: String) -> void:
	player_name = p_name
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual:
		visual.color = p_color


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
	# While out of bounds (#84) the elastic restoring force is the ONLY force that
	# acts — gravity, friction, and movement input are all suppressed until the
	# player is repelled back into the play area.
	if not _update_border(delta, replay):
		_apply_gravity(delta, input.move_axis)
		_apply_horizontal(delta, input.move_axis)
		_try_jump(input.move_axis)
	if not replay:
		_handle_shoot(input)
		_handle_shield(input, delta)
	move_and_slide()
	if not replay:
		# Shove any physics blocks (#96) this player drove into this tick.
		# Skipped on reconciliation replay so an already-applied push isn't
		# double-counted when a PREDICTED player rewinds and re-simulates.
		_push_physics_bodies()


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
	input.shield = Input.is_action_just_pressed("p%d_shield" % p)
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


## Imparts a mass/velocity-scaled impulse into every physics block (#96) this
## player collided with during the last `move_and_slide`. Players are kinematic
## and only push: the block (a RigidBody2D) reacts, the player does not. The
## push strength derives from the player's mass and the speed it drove into the
## block (see PhysicsModel.push_impulse).
func _push_physics_bodies() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider != null and collider.has_method("receive_push"):
			var impulse := PhysicsModel.push_impulse(mass, velocity, collision.get_normal())
			if impulse != Vector2.ZERO:
				collider.receive_push(impulse)


# ---------------------------------------------------------------------------
# Damaging elastic map border (#84)
# ---------------------------------------------------------------------------

## Applies the damaging-elastic-border behaviour for one tick and returns true
## when the player is out of bounds (so [_step] suppresses normal physics and
## lets the restoring force alone govern motion).
##
## On the frame the border is first touched the player takes an immediate
## 50-damage hit and an inward bounce impulse; while it stays out it keeps taking
## 50 damage every 500 ms and is pushed inward by a penetration-scaled spring.
## Crossing back in resets the excursion. Damage is authority-side and never
## re-applied during a reconciliation replay (HP is host-authoritative, #27),
## mirroring how shooting is gated by role.
func _update_border(delta: float, replay: bool) -> bool:
	var pen := MapBorder.penetration(global_position, _body_half_extent)
	if pen == Vector2.ZERO:
		_out_of_bounds = false
		_border_damage_timer = 0.0
		return false

	var first_contact := not _out_of_bounds
	_out_of_bounds = true

	# Penetration-scaled restoring force (Hooke's law), plus a one-shot inward
	# bounce on first contact so even a light touch is repelled.
	velocity += MapBorder.restoring_acceleration(pen) * delta
	if first_contact:
		velocity += MapBorder.contact_impulse(pen)
		# Audio analogue of the bounce: a one-shot "electric-fence touch" cue.
		# Like the impulse it pairs with, this is local feedback fired on whichever
		# machine simulates the player live (a PREDICTED client hears its own
		# contact immediately, like it fires SHOOT for its predicted shots), not
		# gated by damage authority. But unlike the deterministic impulse it must
		# NOT re-fire when a reconciliation replay re-simulates this step, so it is
		# gated by `not replay` (mirroring the border damage below).
		if not replay:
			SfxDirector.play(SfxDirector.BORDER_CONTACT)

	if not replay and _is_damage_authority():
		if first_contact:
			_border_damage_timer = MapBorder.DAMAGE_INTERVAL
			take_damage(MapBorder.DAMAGE_PER_TICK)
		else:
			var accrued := MapBorder.accrue_damage(_border_damage_timer, delta)
			_border_damage_timer = accrued["timer"]
			if accrued["damage"] > 0.0:
				take_damage(accrued["damage"])

	return true


## True while this player's body is touching or past a map border (#84): the
## damaging out-of-bounds state the elastic border applies each tick. Read by the
## HUD's [BorderOverlay] (#101) to flash the contact and flag the player off-screen.
func is_out_of_bounds() -> bool:
	return _out_of_bounds


## True for the machine that authoritatively owns this player's health: offline
## players and the host's own square (LOCAL) and the host's stand-ins for remote
## clients (SIMULATED). A PREDICTED client square only predicts movement — its
## border damage arrives from the host via snapshot — and a PUPPET never steps.
func _is_damage_authority() -> bool:
	return net_role == NetRole.LOCAL or net_role == NetRole.SIMULATED


# ---------------------------------------------------------------------------
# Combat helpers
# ---------------------------------------------------------------------------

## Advances the reflecting shield clocks and raises it on a fresh press (#138).
## Runs only on a live step (gated by `_step`'s `not replay`), so a reconciliation
## rewind never re-spends a charge or double-advances the timers; the host drives
## a SIMULATED player's shield from the same replicated input bit and adjudicates
## reflection authoritatively, so this stays host-consistent.
func _handle_shield(input: NetPlayerInput, delta: float) -> void:
	health.advance_shield(delta)
	if input.shield and health.activate_shield():
		SfxDirector.play(SfxDirector.SHIELD_RAISE)


func _handle_shoot(input: NetPlayerInput) -> void:
	if not input.shoot:
		# Releasing the trigger abandons any delayed shot still charging (#113), and
		# on a client drops any re-timed prediction of a host-delayed shot (#121) so
		# it never spawns an orphan the host won't broadcast.
		weapon.clear_pending()
		NetReplicator.clear_client_pending()
		return
	match net_role:
		NetRole.PREDICTED:
			# Fire a local visual-only shot immediately for responsiveness; the
			# host validates the intent and replicates the authoritative
			# projectile back, echoing the predicted instance's id (#27). A pure
			# client runs no effects, so its shot is always FIRED or REJECTED, never
			# SCHEDULED — the host decides any delay and acks it back (#121).
			var result := weapon.try_fire(input.aim)
			if result.is_fired():
				NetReplicator.send_fire_intent(self, result.projectile, input.aim)
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


## Whether this player's reflecting shield is currently up (#138). Read by an
## incoming Projectile to decide whether to deflect the shot back at its owner.
func is_shielded() -> bool:
	return health.is_shielded()


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
	# Ammo is host-authoritative (#117): a client never simulates its own
	# magazine, so adopt the host's count outright, like health.
	auth.apply_ammo_to(self)
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
	# A pending delayed shot doesn't fire from a corpse (#113), and on a client a
	# re-timed prediction of a host-delayed shot is dropped too (#140) so a death
	# mid-delay (trigger still held, before the round resets) leaves no orphan
	# visual bullet the host will never broadcast — mirroring the host abandoning
	# its scheduled shot here. `clear_client_pending` is a no-op off a client.
	weapon.clear_pending()
	NetReplicator.clear_client_pending()
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
	# Clear any out-of-bounds excursion so a respawn starts with fresh physics (#84).
	_out_of_bounds = false
	_border_damage_timer = 0.0
	# Refill the magazine and drop any in-flight delayed shot for the fresh life (#113).
	weapon.reset_ammo()
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
	mass          = PhysicsModel.player_mass(d.get("player_size", 32.0))
	if initialize_health:
		health.initialize(d)
	else:
		health.apply_stats(d)
	weapon.apply_stats(d)

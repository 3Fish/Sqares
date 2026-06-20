extends CharacterBody2D
class_name Projectile

## Fraction of world gravity applied to bullets, giving them an arc.
const GRAVITY_SCALE := 1.0
## Max course-correction, in radians/second, applied at homing strength 1.0.
## Scaled linearly by the bullet_homing stat (0 = none, 1 = full).
const HOMING_TURN_RATE := 6.0
## Scene group that homing bullets steer toward and knockback can push.
const TARGET_GROUP := "players"
## Scene group of destructible platform blocks (#97). Explosion AoE sweeps this
## group so a blast also damages nearby destructible blocks, not only the one a
## bullet hits directly. Destructible blocks join it at build time.
const DESTRUCTIBLE_GROUP := "destructible_blocks"

var damage: float = 25.0
var lifesteal: float = 0.0
var bounces_remaining: int = 0
var homing: float = 0.0
var knockback_force: float = 0.0
var explosion_radius: float = 0.0
var shooter: Node = null
## True for client-side instances (predicted or replicated, #27): they fly and
## bounce for feedback but never deal damage — hits are adjudicated host-only.
var visual_only: bool = false
## Replication id echoed between a client's predicted shot and the host's
## authoritative confirmation (#27). Empty for purely local projectiles.
var net_id: String = ""

var _lifetime: float = 6.0
var _base_gravity: float
## Physics mass derived from the bullet's size/damage (#96); drives the impulse
## this bullet imparts into a physics block on impact.
var _mass: float = 0.0


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
	_mass             = PhysicsModel.bullet_mass(p_scale, p_damage)


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
	# A platform block is a physics block (#96, pushable) and/or a destructible
	# block (#97, damageable). Either way it is solid: the bullet bounces/stops
	# against it like any wall and is never treated as a combatant (no knockback,
	# explosion, lifesteal, or effect-hit dispatch).
	var is_block := collider.has_method("receive_push") or collider.has_method("damage_block")
	if collider.has_method("take_damage") and not is_block:
		if visual_only:
			# Client-side instance: impact feedback only; the host resolves the
			# real hit and its damage arrives via snapshot / death event.
			SfxDirector.play(SfxDirector.HIT)
			queue_free()
			return
		if not _may_damage(collider):
			# Friendly fire is off and this is a teammate (or the shooter itself
			# on a bounce-back): the shot deals no damage and is consumed — no
			# knockback, explosion, lifesteal, HIT cue, or effect dispatch (#62).
			queue_free()
			return
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
	elif is_block:
		# Block (#96/#97): impart a mass/velocity-scaled impulse into a physics
		# block and/or deal damage to a destructible one — independently, per the
		# flags. The bullet is never consumed by these (it does not "stick"): it
		# bounces if it has bounces left, otherwise stops like hitting any solid.
		# Visual-only (client) instances skip both; blocks are host-authoritative.
		if not visual_only:
			if collider.has_method("receive_push"):
				collider.receive_push(PhysicsModel.push_impulse(_mass, velocity, collision.get_normal()))
			if collider.has_method("damage_block"):
				collider.damage_block(damage)
		if bounces_remaining > 0:
			velocity = velocity.bounce(collision.get_normal())
			bounces_remaining -= 1
			SfxDirector.play(SfxDirector.BOUNCE)
		else:
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
## already taken the impact damage), and additionally damages every destructible
## block (#97) in the blast (#103). Splash victims take the full bullet `damage`;
## blast falloff is deferred tuning (see #26). With friendly fire off the
## shooter's teammates are dropped from the splash too, so an explosion only
## harms enemies (#62); blocks are never team-filtered.
func _detonate(center: Vector2, direct_target: Node) -> void:
	var victims := filter_hostile(
		get_tree().get_nodes_in_group(TARGET_GROUP),
		combatant_id(shooter), GameManager.friendly_fire, GameManager.team_of)
	for node in victims:
		if node == shooter or node == direct_target or not (node is Node2D):
			continue
		if not node.has_method("take_damage"):
			continue
		if is_in_blast_radius(center, (node as Node2D).global_position, explosion_radius):
			node.take_damage(damage, shooter if is_instance_valid(shooter) else null)

	# #103: extend the blast to destructible blocks so an explosion near one
	# damages it, not just a bullet that strikes it directly.
	damage_blocks_in_blast(get_tree().get_nodes_in_group(DESTRUCTIBLE_GROUP), center, direct_target)


## Applies the bullet `damage` to every destructible block in `candidates` whose
## position lies within `explosion_radius` of `center`, skipping `direct_target`
## (already damaged by the impact). Split out from `_detonate` so the blast→block
## dispatch is unit-tested with real blocks without a live scene tree.
func damage_blocks_in_blast(candidates: Array, center: Vector2, direct_target: Node) -> void:
	for node in blast_targets_in_radius(candidates, center, explosion_radius, direct_target):
		if node.has_method("damage_block"):
			node.damage_block(damage)


## The `Node2D` members of `candidates` within `radius` of `center`, excluding
## `direct_target` and any non-`Node2D` entry. Pure function so the AoE block
## selection is unit-tested without a live scene tree.
static func blast_targets_in_radius(candidates: Array, center: Vector2, radius: float, direct_target: Node) -> Array:
	var hit: Array = []
	for node in candidates:
		if node == direct_target or not (node is Node2D):
			continue
		if is_in_blast_radius(center, (node as Node2D).global_position, radius):
			hit.append(node)
	return hit


## True when `point` lies within `radius` of `center` (inclusive of the edge).
## A non-positive radius means no blast. Pure function so the AoE selection can
## be unit-tested without a scene.
static func is_in_blast_radius(center: Vector2, point: Vector2, radius: float) -> bool:
	if radius <= 0.0:
		return false
	return center.distance_squared_to(point) <= radius * radius


## Nearest living *enemy* combatant other than the shooter, or null. With
## friendly fire off the shooter's teammates are dropped first, so a homing
## bullet only steers toward enemies (#62); with it on every group member is a
## candidate, the historical behaviour.
func _find_nearest_target() -> Node2D:
	var candidates := filter_hostile(
		get_tree().get_nodes_in_group(TARGET_GROUP),
		combatant_id(shooter), GameManager.friendly_fire, GameManager.team_of)
	return select_nearest_target(candidates, global_position, shooter)


## Nearest `Node2D` in `candidates` to `origin`, excluding `exclude` (the
## shooter) and any non-`Node2D` entry, or null when none qualify. Pure so the
## homing target selection is unit-tested without a live scene tree.
static func select_nearest_target(candidates: Array, origin: Vector2, exclude: Node) -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for node in candidates:
		if node == exclude or not (node is Node2D):
			continue
		var d: float = origin.distance_squared_to((node as Node2D).global_position)
		if d < best:
			best = d
			nearest = node
	return nearest


# --- Friendly-fire / team target filtering (#62) ----------------------------
# A shot may damage a target only when they are hostile. With friendly fire on
# (the default, and the only setting that matters in Free-for-all) every target
# is hostile, so the historical behaviour is unchanged. With it off, a target on
# the shooter's own team — including the shooter itself on a bounce-back — is
# friendly: the direct hit is consumed, and homing / explosion splash skip it.
# The rule is a pure static so it is unit-tested without a scene; the live combat
# paths feed it `GameManager.friendly_fire` and `GameManager.team_of`.

## Whether a shot from `shooter_id` may damage a combatant with `target_id`.
## With `ff` true every target is hostile. With it off, sharing a team makes them
## friendly (a self-hit, `shooter_id == target_id`, is therefore friendly too).
## `team_map` is player_id -> team_id; an id absent from it is its own team, so
## distinct Free-for-all players stay mutual enemies. A `target_id` of -1 (a
## non-combatant such as a non-player target) is always hostile.
static func is_hostile(shooter_id: int, target_id: int, ff: bool, team_map: Dictionary) -> bool:
	if ff or shooter_id < 0 or target_id < 0:
		return true
	return team_map.get(shooter_id, shooter_id) != team_map.get(target_id, target_id)


## The `player_id` of a combatant node, or -1 when it exposes none (a non-player
## target or a lightweight test stub). Such a node is treated as always hostile.
static func combatant_id(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	var pid: Variant = node.get("player_id")
	return int(pid) if pid != null else -1


## The subset of `candidates` the shooter may target under the friendly-fire
## rule — shared by homing target selection and explosion splash. With `ff` true
## (or the shooter lacking an id) every candidate passes; with it off, the
## shooter's teammates are dropped while enemies and non-combatants are kept.
## Pure so the filter is unit-tested without a scene.
static func filter_hostile(candidates: Array, shooter_id: int, ff: bool, team_map: Dictionary) -> Array:
	if ff or shooter_id < 0:
		return candidates
	var out: Array = []
	for node in candidates:
		if is_hostile(shooter_id, combatant_id(node), ff, team_map):
			out.append(node)
	return out


## Whether this bullet may deal damage to `target`, reading the live friendly-fire
## rule and team map. Used by the direct-hit path to decide between dealing damage
## and consuming a friendly shot.
func _may_damage(target: Object) -> bool:
	return is_hostile(
		combatant_id(shooter), combatant_id(target),
		GameManager.friendly_fire, GameManager.team_of)

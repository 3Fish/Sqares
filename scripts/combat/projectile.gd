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
## Scene group of pushable physics blocks (#96). Explosion AoE sweeps this group
## so a blast imparts a radial impulse to nearby physics blocks (#52 A3), the
## same way it pushes one struck directly. Physics blocks join it at build time.
const PHYSICS_GROUP := "physics_blocks"

var damage: float = 25.0
var lifesteal: float = 0.0
var bounces_remaining: int = 0
var homing: float = 0.0
var knockback_force: float = 0.0
var explosion_radius: float = 0.0
## Explosion feel (#52): splash victims take `explosion_damage_factor × damage`
## and, when this bullet knocks back, a radial impulse of
## `explosion_knockback_factor × knockback_force`. Defaults match the registered
## stats (0.5) so an old call site / bare `Projectile.new()` behaves sanely.
var explosion_damage_factor: float = 0.5
var explosion_knockback_factor: float = 0.5
## Shield penetration (#138): the fraction of this bullet's damage that punches
## through a raised shield. `0` (the default) is fully reflected; `p != 0` is not
## deflected and lands `p × damage` on the shielded target (negative heals,
## `p > 1` exceeds the base hit), consuming the bullet like a normal hit.
var shield_penetration: float = 0.0
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
	p_explosion_damage_factor: float = 0.5,
	p_explosion_knockback_factor: float = 0.5,
) -> void:
	velocity          = direction.normalized() * speed
	damage            = p_damage
	scale             = Vector2.ONE * p_scale
	bounces_remaining = p_bounces
	lifesteal         = p_lifesteal
	homing            = p_homing
	knockback_force   = p_knockback
	explosion_radius  = p_explosion_radius
	explosion_damage_factor    = p_explosion_damage_factor
	explosion_knockback_factor = p_explosion_knockback_factor
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
		var shielded := _target_shielded(collider)
		if shielded and shield_penetration == 0.0:
			# Raised shield, no penetration (#138): reflect the bullet straight back
			# and hand it to the deflector, so a well-timed counter can turn the shot
			# on the original shooter (or, with FF off, across teams). The deflect
			# precedes the friendly-fire check on purpose, and the bullet keeps
			# flying rather than being consumed.
			velocity = reflect_velocity(velocity)
			shooter = collider
			SfxDirector.play(SfxDirector.SHIELD_REFLECT)
			# Reflection mutates this shot in place rather than spawning a new one, so
			# the spawn-time broadcast never announced the bounce-back — a pure client
			# would see its bullet vanish at the shield. Re-broadcast the reversed
			# trajectory under the same net_id, now owned by the deflector, so clients
			# spawn the visual bullet flying back instead (#158). Reuses the spawn
			# broadcast path and no-ops off the host / in local play; hits stay
			# host-authoritative. `shield_penetration` is never put on the wire, so only
			# the host can tell a reflection (vs a penetrating hit) actually happened —
			# hence a host re-broadcast rather than client-side prediction.
			NetReplicator.broadcast_projectile(self, combatant_id(collider))
			return
		if not _may_damage(collider):
			# Friendly fire is off and this is a teammate (or the shooter itself
			# on a bounce-back): the shot deals no damage and is consumed — no
			# knockback, explosion, lifesteal, HIT cue, or effect dispatch (#62).
			queue_free()
			return
		# A penetrating bullet against a raised shield (#138) lands `p × damage`
		# (negative heals); otherwise the full hit. The bullet is consumed either
		# way, and knockback / explosion / lifesteal / effects resolve as a normal
		# hit — explosion AoE in particular always damages, shield or not.
		var hit_damage: float = penetration_damage(damage, shield_penetration) if shielded else damage
		_apply_player_damage(collider, hit_damage)
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
## block (#97) in the blast (#103) and pushes every physics block (#96) in it
## (#52 A3). Splash victims take `explosion_damage_factor × damage` (#52 A1), and
## — when this bullet itself knocks back — a radial impulse away from the centre
## scaled by `explosion_knockback_factor` (#52 A2). With friendly fire off the
## shooter's teammates are dropped from the splash too, so an explosion only
## harms enemies (#62); blocks are never team-filtered.
func _detonate(center: Vector2, direct_target: Node) -> void:
	var victims := filter_hostile(
		get_tree().get_nodes_in_group(TARGET_GROUP),
		combatant_id(shooter), GameManager.friendly_fire, GameManager.team_of)
	splash_combatants(victims, center, direct_target)

	# #103: extend the blast to destructible blocks so an explosion near one
	# damages it, not just a bullet that strikes it directly.
	damage_blocks_in_blast(get_tree().get_nodes_in_group(DESTRUCTIBLE_GROUP), center, direct_target)
	# #52 A3: a knocking-back bullet's blast also pushes physics blocks in range.
	push_blocks_in_blast(get_tree().get_nodes_in_group(PHYSICS_GROUP), center)


## Applies the blast to every (already team-filtered) combatant in `victims`
## within `explosion_radius` of `center`, skipping the shooter and the
## directly-hit `direct_target`. Each victim takes `explosion_damage_factor ×
## damage` (#52 A1) and — when this bullet itself knocks back — a radial impulse
## scaled by `explosion_knockback_factor` (#52 A2). Split out from `_detonate` so
## the combatant splash is unit-tested with stub combatants without a live tree
## (the live group sweep + friendly-fire filter stays in `_detonate`).
func splash_combatants(victims: Array, center: Vector2, direct_target: Node) -> void:
	var splash_damage := explosion_damage(damage, explosion_damage_factor)
	for node in victims:
		if node == shooter or node == direct_target or not (node is Node2D):
			continue
		if not node.has_method("take_damage"):
			continue
		if not is_in_blast_radius(center, (node as Node2D).global_position, explosion_radius):
			continue
		node.take_damage(splash_damage, shooter if is_instance_valid(shooter) else null)
		# #52 A2: a knocking-back bullet's blast also shoves splash victims
		# radially outward; a non-knockback bullet's blast does not.
		if knockback_force > 0.0 and node.has_method("apply_knockback"):
			node.apply_knockback(explosion_impulse(
				center, (node as Node2D).global_position,
				knockback_force, explosion_knockback_factor))


## Applies the blast's explosion damage (`explosion_damage_factor × damage`, #52
## A1) to every destructible block in `candidates` within `explosion_radius` of
## `center`, skipping `direct_target` (already damaged by the impact). Split out
## from `_detonate` so the blast→block dispatch is unit-tested with real blocks
## without a live scene tree.
func damage_blocks_in_blast(candidates: Array, center: Vector2, direct_target: Node) -> void:
	var dmg := explosion_damage(damage, explosion_damage_factor)
	for node in blast_targets_in_radius(candidates, center, explosion_radius, direct_target):
		if node.has_method("damage_block"):
			node.damage_block(dmg)


## Imparts a radial impulse (away from `center`) to every physics block in
## `candidates` within `explosion_radius` (#52 A3), scaled by the bullet's own
## knockback like the player splash knockback. No-op for a non-knockback bullet
## (`knockback_force <= 0`). Split out from `_detonate` so the blast→block push is
## unit-tested with real blocks without a live scene tree.
func push_blocks_in_blast(candidates: Array, center: Vector2) -> void:
	if knockback_force <= 0.0:
		return
	for node in blast_targets_in_radius(candidates, center, explosion_radius, null):
		if node.has_method("receive_push"):
			node.receive_push(explosion_impulse(
				center, (node as Node2D).global_position,
				knockback_force, explosion_knockback_factor))


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


## Explosion splash damage: a fraction of the bullet's own `bullet_damage` (#52
## A1). `factor` is clamped to >= 0 so a malformed negative multiplier can't heal
## a victim. Pure so the maths is unit-tested without a scene.
static func explosion_damage(bullet_damage: float, factor: float) -> float:
	return bullet_damage * maxf(factor, 0.0)


## Radial blast impulse pushing `target_pos` away from the blast `center` (#52
## A2/A3): a unit vector along `center -> target_pos` scaled by `base_force ×
## factor`. Returns the zero vector when the magnitude is non-positive or the
## target sits exactly on the centre (no defined direction). Pure so the impulse
## maths is unit-tested without a scene.
static func explosion_impulse(center: Vector2, target_pos: Vector2, base_force: float, factor: float) -> Vector2:
	var magnitude := base_force * maxf(factor, 0.0)
	if magnitude <= 0.0:
		return Vector2.ZERO
	var dir := target_pos - center
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	return dir.normalized() * magnitude


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


# --- Reflecting shield (#138) -----------------------------------------------

## Whether `target` currently has a raised reflecting shield. A target exposing
## no `is_shielded` (a block already handled above, or a test stub) is unshielded.
func _target_shielded(target: Object) -> bool:
	return target.has_method("is_shielded") and target.is_shielded()


## Applies a penetrating/normal hit's damage to `target`, routing a negative
## amount (a `shield_penetration < 0` "heal through the shield" bullet) to `heal`
## so HP is correctly restored and capped rather than added uncapped.
func _apply_player_damage(target: Object, amount: float) -> void:
	if amount < 0.0 and target.has_method("heal"):
		target.heal(-amount)
	else:
		target.take_damage(amount, shooter if is_instance_valid(shooter) else null)


## A bullet's velocity after a shield deflects it: straight reversal (#138 A2) —
## the same speed, sent back the way it came. Pure so the reflection is unit-
## tested without a scene.
static func reflect_velocity(p_velocity: Vector2) -> Vector2:
	return -p_velocity


## The HP delta a penetrating bullet lands on a shielded target (#138): `damage ×
## penetration`. Unclamped, mirroring the stat — a negative fraction heals, a
## fraction above 1 exceeds the base hit. Pure so the maths is unit-tested
## without a scene.
static func penetration_damage(base_damage: float, penetration: float) -> float:
	return base_damage * penetration

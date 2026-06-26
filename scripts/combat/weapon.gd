extends Node2D
class_name Weapon

var damage: float = 25.0
## Seconds between shots (#125): the cooldown charged after each trigger pull.
## Lower = faster; `0` enforces no delay (fire as fast as the physics tick allows).
var fire_interval: float = 0.5
var bullet_speed: float = 800.0
var bullet_scale: float = 1.0
var bullet_bounces: int = 0
var bullet_homing: float = 0.0
var lifesteal: float = 0.0
var knockback_force: float = 0.0
var explosion_radius: float = 0.0
## Explosion feel (#52): the blast deals `explosion_damage_factor × damage` to
## splash victims, and — when the bullet itself knocks back — a radial impulse of
## `explosion_knockback_factor × knockback_force`. Both are registered, card-
## tunable stats (default 0.5) carried onto the ShotSpec so pre-shoot effects can
## override them per shot.
var explosion_damage_factor: float = 0.5
var explosion_knockback_factor: float = 0.5
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
## On a client, the host's authoritative idle-reload progress adopted from each
## snapshot (#123). A client never simulates its own reload (`_tick_reload`
## early-returns on clients), so its local `_idle_time` stays put; the HUD's
## reload indicator (#116) reads this replicated value instead, exactly like the
## ammo count is adopted (#117). `-1.0` means "not replicated" (the host, or a
## client before its first snapshot), so the readout falls back to the local
## computation. Cleared by `reset_ammo` so a stale value never bleeds into a new
## round.
var _replicated_reload_progress: float = -1.0
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
	fire_interval  = stats.get("fire_interval",    fire_interval)
	bullet_speed   = stats.get("bullet_speed",     bullet_speed)
	bullet_scale   = stats.get("bullet_scale",     bullet_scale)
	bullet_bounces = int(stats.get("bullet_bounces", float(bullet_bounces)))
	bullet_homing  = stats.get("bullet_homing",     bullet_homing)
	lifesteal      = stats.get("lifesteal",        lifesteal)
	knockback_force = stats.get("knockback_force",  knockback_force)
	explosion_radius = stats.get("explosion_radius", explosion_radius)
	explosion_damage_factor = stats.get("explosion_damage_factor", explosion_damage_factor)
	explosion_knockback_factor = stats.get("explosion_knockback_factor", explosion_knockback_factor)
	magazine_size  = int(stats.get("magazine_size", float(magazine_size)))
	reload_time    = stats.get("reload_time",       reload_time)


## Refills the magazine and clears any in-flight delayed shots. Called at round
## start so every player begins with a full magazine (#113) and no stale pending
## shots carried over from the previous round.
func reset_ammo() -> void:
	_ammo = magazine_size
	_idle_time = 0.0
	_pending.clear()
	# Drop any replicated reload progress from the previous round so a client
	# falls back to its (full-magazine) local computation until a fresh snapshot
	# arrives, rather than reporting a stale fraction (#123).
	_replicated_reload_progress = -1.0


## Rounds currently in the magazine. Exposed for the ammo HUD (#113 A4 / #116).
func get_ammo() -> int:
	return _ammo


## Idle-reload progress in [0, 1] for the ammo HUD (#116): how far the magazine
## has refilled toward full since the last shot. A full magazine reports 1.0.
## On a client this is host-authoritative (#123): the client never ticks its own
## reload, so it returns the progress adopted from the latest snapshot when one
## has arrived (`set_reload_progress`). On the host — or on a client before its
## first snapshot — it delegates to the pure `AmmoModel.reload_progress` so the
## maths stays testable.
func get_reload_progress() -> float:
	if _replicated_reload_progress >= 0.0:
		return _replicated_reload_progress
	return AmmoModel.reload_progress(_ammo, magazine_size, _idle_time, reload_time)


## Overwrites the magazine to an authoritative round count (#117). Ammo is
## host-authoritative (#113 A6): a client never simulates ammo, it adopts the
## host's count from each snapshot. Clamped to the magazine so a malformed or
## stale payload can never over- or under-fill it.
func set_ammo(value: int) -> void:
	_ammo = clampi(value, 0, magazine_size)


## Adopts the host's authoritative idle-reload progress on a client (#123),
## clamped to [0, 1]. Mirrors `set_ammo`: a client never simulates its own
## reload, so the HUD's reload indicator reads the host's value on every peer.
## A clamped `0.0` is a real "just fired" reading (distinct from the `-1.0`
## "not replicated" sentinel), so it correctly drives the readout too.
func set_reload_progress(value: float) -> void:
	_replicated_reload_progress = clampf(value, 0.0, 1.0)


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


## Fires in `direction` unless cooling down. Returns a [FireResult] tri-state
## (#121) so callers — chiefly the netcode fire-intent path — can tell the three
## outcomes apart:
## - [b]FIRED[/b]: a projectile spawned now; `result.projectile` is the first one
##   (the first bullet of a multi-shot), the value the old `Projectile` return
##   carried, so a caller can still replicate/track it (#27).
## - [b]SCHEDULED[/b]: the shot was accepted but deferred by `delay` seconds (#113);
##   `result.delay` carries the wait so the host can ack a predicting client (#121).
##   Previously this returned `null`, indistinguishable from a rejection.
## - [b]REJECTED[/b]: nothing fired (cooling down, no aim, cancelled, or out of ammo).
##
## `net_id` tags a host-confirmed shot with the shooter client's predicted-
## projectile id so the broadcast can echo it.
##
## Before anything spawns, card effects get to reshape the shot through a mutable
## `ShotSpec` (#68): they may change the bullet count, override the per-bullet
## stats, or cancel the shot entirely. A cancelled (or zero-count) shot is a true
## no-op — no projectile and no cooldown consumed.
func try_fire(direction: Vector2, net_id: String = "") -> FireResult:
	if _cooldown > 0.0 or direction == Vector2.ZERO:
		return FireResult.rejected()
	var spec := _build_shot_spec()
	# Pre-shoot effects run only where the shot is adjudicated (host/local), so a
	# client's predicted shot keeps the default single-bullet spec — mirroring how
	# on_shoot dispatch is host-only. (A client has no attached effects yet, #82.)
	# Ammo is authority-side for the same reason (#113 A6): a pure client predicts
	# its shots cooldown-gated and visual-only, and the host's ammo gate decides
	# truth (rejecting a predicted shot it had no rounds for), so the client never
	# tracks ammo locally. A consequence is that a pure client's `spec.delay` stays
	# 0 (no effects run), so SCHEDULED only ever arises on the authority side (#121).
	if not NetworkManager.is_client():
		EffectEngine.notify_before_shoot(get_parent(), self, spec, direction)
		if not AmmoModel.can_fire(_ammo, spec.ammo_cost):
			return FireResult.rejected()  # #113 A3: magazine can't cover the cost.
		if spec.ammo_cost > 0:
			# #113 A5: ammo is consumed by the chain's resulting cost even when an
			# effect cancels the shot (a free cancel must also zero ammo_cost).
			# Drawing rounds restarts the idle-reload clock.
			_ammo = AmmoModel.consume(_ammo, spec.ammo_cost)
			_idle_time = 0.0
	if not spec.fires():
		return FireResult.rejected()
	# Cooldown is charged from the trigger pull, never the (possibly delayed) spawn
	# (#113): a delayed shot still gates the next trigger from now. fire_interval is
	# the gap in seconds (#125), used directly; `maxf(_, 0.0)` guards a (clamped)
	# `0` interval — the next pull then fires on the very next physics tick.
	_cooldown = maxf(fire_interval, 0.0)
	if spec.delay > 0.0:
		# Schedule the spawn for `delay` seconds from now. The host carries the
		# shooter's `net_id` so the eventual broadcast echoes it (#121), letting a
		# predicting client adopt its re-timed prediction.
		_pending.append({
			"spec": spec, "direction": direction, "net_id": net_id, "remaining": spec.delay,
		})
		return FireResult.scheduled(spec.delay)
	return FireResult.fired(_fire_spec(spec, direction, net_id))


## Spawns a single visual-only predicted bullet for a client's re-timed delayed
## shot (#121): when the host acks a scheduled shot, the client drops its premature
## instant prediction and re-spawns through here once its mirrored delay elapses,
## tagging the bullet with `net_id` so the host's authoritative broadcast adopts
## it. Reuses the normal spawn path, so on a client every projectile is visual-
## only and the host-side effect/broadcast steps in `_spawn_projectile` are
## skipped — it is the shooter's default single-bullet shot, matching the spec the
## client predicts with locally (effects are authority-side, #82).
##
## `silent` defaults true (#140): a pure client doesn't know a shot will be delayed
## at trigger time, so it already played `SHOOT` on its premature instant
## prediction. Re-playing the cue here — at the re-timed spawn — would sound the
## shot twice for an online `delay > 0` shot, so the re-spawn is silent and the one
## cue stays at the trigger pull.
func spawn_predicted(direction: Vector2, net_id: String, silent: bool = true) -> Projectile:
	return _spawn_projectile(_build_shot_spec(), direction, net_id, silent)


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
	# Ammo is host-authoritative (#113 A6 / #117): a client adopts the host's
	# round count from each snapshot and never simulates its own reload, so the
	# replicated value isn't overwritten between snapshots. (Consumption is
	# already gated the same way in `try_fire`.)
	if NetworkManager.is_client():
		return
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
		explosion_damage_factor, explosion_knockback_factor,
	)


## `silent` suppresses the `SHOOT` cue for a re-timed delayed-shot re-spawn (#140);
## every normal/immediate shot leaves it false so the cue plays as the bullet
## appears.
func _spawn_projectile(spec: ShotSpec, direction: Vector2, net_id: String, silent: bool = false) -> Projectile:
	var proj: Projectile = _projectile_scene.instantiate()
	proj.setup(
		direction, spec.speed, spec.damage, spec.scale, spec.bounces, spec.lifesteal,
		get_parent(), spec.homing, spec.knockback, spec.explosion_radius,
		spec.explosion_damage_factor, spec.explosion_knockback_factor,
	)
	proj.net_id = net_id
	# Hit detection and damage are host-only (#27): every projectile spawned on
	# a client — its own predicted shots included — is purely visual.
	proj.visual_only = NetworkManager.is_client()
	proj.global_position = global_position + direction.normalized() * 48.0
	get_tree().current_scene.add_child(proj)
	if not silent:
		SfxDirector.play(SfxDirector.SHOOT)
	if not proj.visual_only:
		# Let card effects react to / mutate the freshly spawned shot. Effects
		# run where damage is adjudicated, so visual-only instances skip this.
		EffectEngine.notify_shoot(get_parent(), self, proj, direction)
	if NetworkManager.is_host():
		# Broadcast after effects so the wire carries the post-mutation shot.
		NetReplicator.broadcast_projectile(proj, get_parent().player_id)
	return proj

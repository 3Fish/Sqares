extends Node
class_name Health

signal damaged(amount: float, attacker: Node)
signal died(killer: Node)
## A shield was manually raised (#138): a charge was spent and the reflect window
## opened. Cosmetic hook for a future shield visual / HUD pip; no gameplay logic
## depends on it.
signal shield_raised()

var max_hp: float = 100.0
var current_hp: float = 100.0

## Reflecting shield (#138). `shield_charges` is the live count of available
## activations and `_max_shield_charges` the cap it recharges toward (both seeded
## from the registered `shield_charges` stat — the stat is the *max*). Raising the
## shield (`activate_shield`) spends one charge and opens a `shield_duration`
## reflect window (`_shield_active_remaining`); while up, `Projectile` deflects
## every incoming bullet. `shield_recharge` regenerates one charge at a time
## (`_recharge_remaining` counts down to the next +1) up to the max.
var shield_charges: int = 0
var _max_shield_charges: int = 0
var shield_duration: float = 0.0
var shield_recharge: float = 0.0
var _shield_active_remaining: float = 0.0
var _recharge_remaining: float = 0.0

var _dead: bool = false


func initialize(stats: Dictionary) -> void:
	max_hp = stats.get("max_health", 100.0)
	current_hp = max_hp
	_max_shield_charges = int(stats.get("shield_charges", 0.0))
	shield_charges = _max_shield_charges  # start a fresh life with a full shield clip
	shield_duration = float(stats.get("shield_duration", 0.0))
	shield_recharge = float(stats.get("shield_recharge", 0.0))
	_shield_active_remaining = 0.0
	_recharge_remaining = shield_recharge
	_dead = false


func apply_stats(stats: Dictionary) -> void:
	max_hp = stats.get("max_health", max_hp)
	current_hp = minf(current_hp, max_hp)
	# `shield_charges` is the cap. A mid-match card that raises it (e.g. Bulwark)
	# grants the extra charge immediately, so a defensive pick is felt right away;
	# a lower cap clamps the live count down.
	var new_max := int(stats.get("shield_charges", float(_max_shield_charges)))
	if new_max > _max_shield_charges:
		shield_charges += new_max - _max_shield_charges
	_max_shield_charges = new_max
	shield_charges = clampi(shield_charges, 0, _max_shield_charges)
	shield_duration = float(stats.get("shield_duration", shield_duration))
	shield_recharge = float(stats.get("shield_recharge", shield_recharge))


# ---------------------------------------------------------------------------
# Shield (#138)
# ---------------------------------------------------------------------------

## Raises the shield if a charge is available and one isn't already up: spends a
## charge and opens the reflect window. Returns whether it actually triggered, so
## the caller can fire the activation cue only on a real raise.
func activate_shield() -> bool:
	if _dead or is_shielded() or shield_charges <= 0:
		return false
	shield_charges -= 1
	_shield_active_remaining = shield_duration
	shield_raised.emit()
	return true


## Whether the reflecting shield is currently up (`Projectile` reads this to
## decide whether to deflect an incoming bullet).
func is_shielded() -> bool:
	return _shield_active_remaining > 0.0


## Forces the reflecting-shield up/down state on a puppet for replication (#158).
## A client's puppet never runs `Player._step`, so `advance_shield` never ticks
## and its shield clock can't follow the host. The per-player snapshot carries the
## host's `is_shielded()` and this stamps it onto the puppet, so `is_shielded()` —
## and any shield visual that reads it — mirrors the authority on every peer. A
## fresh raise re-emits `shield_raised`, so an edge-triggered visual fires on a
## remote shield-up just as it does locally. Purely cosmetic: puppets are
## visual-only and adjudicate no hits, so this has no gameplay effect.
func set_shielded(active: bool) -> void:
	if not active:
		_shield_active_remaining = 0.0
		return
	if not is_shielded():
		shield_raised.emit()
	# Puppets don't tick this down, so any positive value holds the window open
	# until the next snapshot clears it; prefer the real duration when known.
	_shield_active_remaining = shield_duration if shield_duration > 0.0 else 1.0


## Advances the shield clocks by one tick: closes the reflect window when its
## duration lapses and regenerates one charge every `shield_recharge` seconds
## while below the cap. Driven by `Player._step`, so it ticks in lockstep with
## the simulation and pauses with it between rounds.
func advance_shield(delta: float) -> void:
	if _shield_active_remaining > 0.0:
		_shield_active_remaining = maxf(_shield_active_remaining - delta, 0.0)
	if shield_charges >= _max_shield_charges or shield_recharge <= 0.0:
		_recharge_remaining = shield_recharge  # primed full so the next deficit waits the whole interval
		return
	_recharge_remaining -= delta
	if _recharge_remaining <= 0.0:
		shield_charges += 1
		_recharge_remaining = shield_recharge


func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	# The reflecting shield (#138) no longer blocks here — it deflects bullets at
	# the projectile layer. `take_damage` is the raw HP path used by penetrating
	# hits, explosion AoE (which always lands), and border damage (#84).
	current_hp = maxf(current_hp - amount, 0.0)
	damaged.emit(amount, attacker)
	if current_hp <= 0.0:
		_dead = true
		died.emit(attacker)


## Authoritative kill (#27): drops HP to zero and emits `died`, bypassing
## shields and local damage maths. Used when the host has already adjudicated
## this death and a client only needs to mirror the outcome.
func kill(killer: Node = null) -> void:
	if _dead:
		return
	current_hp = 0.0
	_dead = true
	died.emit(killer)


func heal(amount: float) -> void:
	if _dead:
		return
	current_hp = minf(current_hp + amount, max_hp)


func reset() -> void:
	_dead = false
	current_hp = max_hp
	# A fresh life starts with a full shield clip and no window open (#138).
	shield_charges = _max_shield_charges
	_shield_active_remaining = 0.0
	_recharge_remaining = shield_recharge


func is_dead() -> bool:
	return _dead

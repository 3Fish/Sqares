extends Node

## Central runtime that attaches `CardEffect`s to players and dispatches their
## lifecycle hooks (#20). Mirrors the registry-autoload pattern used by
## `StatRegistry` / `CardRegistry`.
##
## Round and combat code notify the engine through the `notify_*` methods (and
## the global `GameManager.round_started` signal); the engine fans each event
## out to the active effects of the relevant player(s). Effects are duck-typed:
## any object exposing the matching `on_apply` / `on_round_start` / `on_shoot` /
## `on_hit` method works, and each hook is invoked only if present, so an effect
## may implement just the hooks it needs.
##
## Effects persist across rounds by design (the rogue-like accumulates picks);
## `clear()` / `clear_player()` exist for match resets and tests.

# player (Object) -> Array of effect objects
var _effects: Dictionary = {}


func _ready() -> void:
	# Round start is a single global signal; the engine fans it out per-player.
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)


# ---------------------------------------------------------------------------
# Attachment
# ---------------------------------------------------------------------------

## Attaches `effect` to `player` and fires its `on_apply` hook. This is the
## card-pick → effect-application path. Duplicate attachments are permitted;
## stacking semantics are the effect's own concern.
func apply_effect(player: Object, effect: Object, event: Dictionary = {}) -> void:
	if player == null or effect == null:
		push_error("EffectEngine: apply_effect requires a non-null player and effect.")
		return
	var list: Array = _effects.get(player, [])
	list.append(effect)
	_effects[player] = list
	var ctx := EffectContext.new(player, _weapon_of(player), null, null, event)
	_dispatch(player, effect, "on_apply", ctx)


## Detaches a single effect instance from a player. No-op if not attached.
func remove_effect(player: Object, effect: Object) -> void:
	if not _effects.has(player):
		return
	_effects[player].erase(effect)
	if _effects[player].is_empty():
		_effects.erase(player)


## Active effects attached to `player` (a copy, safe to iterate while mutating).
func get_effects(player: Object) -> Array:
	return (_effects.get(player, []) as Array).duplicate()


func has_effects(player: Object) -> bool:
	return _effects.has(player) and not (_effects[player] as Array).is_empty()


## Removes every effect from a single player (e.g. on respawn-reset designs).
func clear_player(player: Object) -> void:
	_effects.erase(player)


## Removes all effects from all players. Used at match setup and in tests.
func clear() -> void:
	_effects.clear()


# ---------------------------------------------------------------------------
# Triggers (called from combat & round code)
# ---------------------------------------------------------------------------

## Notifies the engine that `player` fired `projectile` from `weapon` aiming in
## `direction`. Fans out to `player`'s `on_shoot` effects. Called by `Weapon`.
func notify_shoot(player: Object, weapon: Object, projectile: Object, direction: Vector2) -> void:
	var ctx := EffectContext.new(player, weapon, projectile, null, {"direction": direction})
	_dispatch_player(player, "on_shoot", ctx)


## Notifies the engine that `shooter`'s `projectile` hit `target` dealing
## `damage`. Fans out to `shooter`'s `on_hit` effects. Called by `Projectile`.
func notify_hit(shooter: Object, target: Object, projectile: Object, damage: float) -> void:
	var ctx := EffectContext.new(shooter, _weapon_of(shooter), projectile, target, {"damage": damage})
	_dispatch_player(shooter, "on_hit", ctx)


## Fans an `on_round_start` hook out to every active effect of every player.
## Wired to `GameManager.round_started` in `_ready`, but exposed directly so the
## fan-out can be unit-tested without standing up the autoload's signal path.
func dispatch_round_start(round_number: int) -> void:
	_prune_invalid()
	for player in _effects.keys():
		var ctx := EffectContext.new(player, _weapon_of(player), null, null, {"round": round_number})
		_dispatch_player(player, "on_round_start", ctx)


func _on_round_started(round_number: int) -> void:
	dispatch_round_start(round_number)


# ---------------------------------------------------------------------------
# Internal dispatch
# ---------------------------------------------------------------------------

func _dispatch_player(player: Object, hook: String, ctx: EffectContext) -> void:
	if player == null or not _effects.has(player):
		return
	# Iterate a copy so a hook may detach itself or others without skipping.
	for effect in (_effects[player] as Array).duplicate():
		_dispatch(player, effect, hook, ctx)


func _dispatch(player: Object, effect: Object, hook: String, ctx: EffectContext) -> void:
	if effect == null or not effect.has_method(hook):
		return
	ctx.player = player
	ctx.effect = effect if effect is CardEffect else null
	effect.call(hook, ctx)


## Reads the `weapon` property off a player object if it exposes one, else null.
## Tolerant of plain stubs (tests) and freed nodes.
func _weapon_of(player: Object) -> Object:
	if player == null or not is_instance_valid(player):
		return null
	return player.get("weapon")


## Drops any keys whose player node has been freed, so a stale corpse never
## receives round-start dispatch.
func _prune_invalid() -> void:
	for player in _effects.keys():
		if not is_instance_valid(player):
			_effects.erase(player)

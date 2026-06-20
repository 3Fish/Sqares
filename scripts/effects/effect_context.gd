class_name EffectContext extends RefCounted

## Bundle of references handed to every `CardEffect` hook (#20).
##
## Fields are populated on a best-effort basis depending on which hook fires —
## unrelated fields stay `null`. `event` carries the hook-specific scalar data
## (e.g. `{"round": 3}`, `{"direction": Vector2(...)}`, `{"damage": 25.0}`).
##
## References are typed as `Object` rather than `Node` so the engine stays
## decoupled from concrete scene types and so effects can be exercised with
## lightweight stubs in tests.

## The effect's owner — the player the effect is attached to.
var player: Object = null

## The owner's weapon, when relevant (e.g. `on_shoot`, `on_hit`).
var weapon: Object = null

## The bullet involved, for `on_shoot` / `on_hit`.
var projectile: Object = null

## What was struck, for `on_hit`.
var target: Object = null

## The mutable `ShotSpec` for `on_before_shoot` — the shot an effect may reshape
## (bullet count, cancel, per-bullet stats) before the weapon fires. `null` for
## every other hook.
var shot: Object = null

## Back-reference to the `CardEffect` currently being invoked. Set by the engine
## per-effect just before each hook call.
var effect: CardEffect = null

## Hook-specific extra data. Keys depend on the hook (see `CardEffect`).
var event: Dictionary = {}


func _init(
	p_player: Object = null,
	p_weapon: Object = null,
	p_projectile: Object = null,
	p_target: Object = null,
	p_event: Dictionary = {},
	p_shot: Object = null,
) -> void:
	player = p_player
	weapon = p_weapon
	projectile = p_projectile
	target = p_target
	event = p_event
	shot = p_shot


## Reads a value from the `event` payload, returning `fallback` if absent.
func get_event(key: String, fallback: Variant = null) -> Variant:
	return event.get(key, fallback)

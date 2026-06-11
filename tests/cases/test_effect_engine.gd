extends TestCase

## Integration tests for the EffectEngine autoload — attachment + hook dispatch
## from the card-apply, combat, and round paths (#20). State is process-wide, so
## each case clears the engine first.


func before_each() -> void:
	EffectEngine.clear()


# --- Test doubles ----------------------------------------------------------

## A CardEffect that snapshots every hook invocation for inspection. Fields are
## copied at call time because the engine reuses one EffectContext per dispatch.
class _Recorder extends CardEffect:
	var hits: Array = []
	func _snap(hook: String, ctx: EffectContext) -> void:
		hits.append({
			"hook": hook,
			"player": ctx.player,
			"effect": ctx.effect,
			"weapon": ctx.weapon,
			"projectile": ctx.projectile,
			"target": ctx.target,
			"event": ctx.event.duplicate(),
		})
	func on_apply(ctx: EffectContext) -> void: _snap("on_apply", ctx)
	func on_round_start(ctx: EffectContext) -> void: _snap("on_round_start", ctx)
	func on_shoot(ctx: EffectContext) -> void: _snap("on_shoot", ctx)
	func on_hit(ctx: EffectContext) -> void: _snap("on_hit", ctx)
	func on_take_damage(ctx: EffectContext) -> void: _snap("on_take_damage", ctx)


## A duck-typed effect that is NOT a CardEffect and implements only one hook —
## exercises the engine's has_method guard.
class _ShootOnly extends RefCounted:
	var shots: int = 0
	func on_shoot(_ctx: EffectContext) -> void:
		shots += 1


## Minimal player stand-in exposing a `weapon` property like the real Player.
class _StubPlayer extends RefCounted:
	var weapon: Object = null


# --- Cases -----------------------------------------------------------------

func _test_apply_effect_attaches_and_fires_on_apply() -> void:
	var player := _StubPlayer.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(player, effect)

	assert_true(EffectEngine.has_effects(player), "player has effects after apply")
	assert_eq(EffectEngine.get_effects(player).size(), 1, "exactly one effect attached")
	assert_eq(effect.hits.size(), 1, "on_apply fired once")
	assert_eq(effect.hits[0]["hook"], "on_apply", "the apply hook fired")
	assert_eq(effect.hits[0]["player"], player, "context carries the owning player")
	assert_eq(effect.hits[0]["effect"], effect, "context back-references the effect")


func _test_apply_effect_rejects_nulls() -> void:
	# These intentionally emit push_error lines — they are expected.
	EffectEngine.apply_effect(null, _Recorder.new())
	EffectEngine.apply_effect(_StubPlayer.new(), null)
	assert_false(EffectEngine.has_effects(null), "null player attaches nothing")


func _test_notify_shoot_dispatches_with_context() -> void:
	var player := _StubPlayer.new()
	var weapon := RefCounted.new()
	var proj := RefCounted.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(player, effect)
	effect.hits.clear()

	EffectEngine.notify_shoot(player, weapon, proj, Vector2.RIGHT)
	assert_eq(effect.hits.size(), 1, "on_shoot fired once")
	var h: Dictionary = effect.hits[0]
	assert_eq(h["hook"], "on_shoot", "shoot hook fired")
	assert_eq(h["weapon"], weapon, "context carries the weapon")
	assert_eq(h["projectile"], proj, "context carries the projectile")
	assert_eq(h["event"]["direction"], Vector2.RIGHT, "event carries the aim direction")


func _test_notify_hit_dispatches_with_context() -> void:
	var shooter := _StubPlayer.new()
	var target := RefCounted.new()
	var proj := RefCounted.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(shooter, effect)
	effect.hits.clear()

	EffectEngine.notify_hit(shooter, target, proj, 42.0)
	assert_eq(effect.hits.size(), 1, "on_hit fired once")
	var h: Dictionary = effect.hits[0]
	assert_eq(h["hook"], "on_hit", "hit hook fired")
	assert_eq(h["target"], target, "context carries the target")
	assert_eq(h["projectile"], proj, "context carries the projectile")
	assert_almost_eq(h["event"]["damage"], 42.0, "event carries the damage")


func _test_notify_take_damage_dispatches_to_victim() -> void:
	# The victim-side counterpart to on_hit (#50): a player's own effects fire
	# when *they* take damage, with the attacker carried as ctx.target.
	var victim := _StubPlayer.new()
	var attacker := _StubPlayer.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(victim, effect)
	effect.hits.clear()

	EffectEngine.notify_take_damage(victim, attacker, 17.0)
	assert_eq(effect.hits.size(), 1, "on_take_damage fired once")
	var h: Dictionary = effect.hits[0]
	assert_eq(h["hook"], "on_take_damage", "take-damage hook fired")
	assert_eq(h["player"], victim, "context owner is the victim")
	assert_eq(h["target"], attacker, "context target is the attacker")
	assert_almost_eq(h["event"]["damage"], 17.0, "event carries the damage taken")


func _test_notify_take_damage_only_hits_victim_not_attacker() -> void:
	# An attacker's own effects must NOT fire from the victim's take-damage event;
	# the dispatch is per-victim, mirroring on_hit's per-shooter dispatch.
	var victim := _StubPlayer.new()
	var attacker := _StubPlayer.new()
	var victim_effect := _Recorder.new()
	var attacker_effect := _Recorder.new()
	EffectEngine.apply_effect(victim, victim_effect)
	EffectEngine.apply_effect(attacker, attacker_effect)
	victim_effect.hits.clear()
	attacker_effect.hits.clear()

	EffectEngine.notify_take_damage(victim, attacker, 5.0)
	assert_eq(victim_effect.hits.size(), 1, "victim's effect receives the take-damage event")
	assert_eq(attacker_effect.hits.size(), 0, "attacker's effect is not touched")


func _test_notify_take_damage_tolerates_null_attacker() -> void:
	# Sourceless damage (e.g. a kill zone) carries no attacker; the hook must still
	# fire with ctx.target == null rather than crashing.
	var victim := _StubPlayer.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(victim, effect)
	effect.hits.clear()

	EffectEngine.notify_take_damage(victim, null, 99.0)
	assert_eq(effect.hits.size(), 1, "on_take_damage fires even without an attacker")
	assert_null(effect.hits[0]["target"], "null attacker yields a null target")


func _test_dispatch_is_per_player() -> void:
	var p1 := _StubPlayer.new()
	var p2 := _StubPlayer.new()
	var e1 := _Recorder.new()
	var e2 := _Recorder.new()
	EffectEngine.apply_effect(p1, e1)
	EffectEngine.apply_effect(p2, e2)
	e1.hits.clear()
	e2.hits.clear()

	EffectEngine.notify_shoot(p1, null, null, Vector2.UP)
	assert_eq(e1.hits.size(), 1, "p1's effect receives p1's shot")
	assert_eq(e2.hits.size(), 0, "p2's effect is not touched by p1's shot")


func _test_multiple_effects_all_fire() -> void:
	var player := _StubPlayer.new()
	var a := _Recorder.new()
	var b := _Recorder.new()
	EffectEngine.apply_effect(player, a)
	EffectEngine.apply_effect(player, b)
	a.hits.clear()
	b.hits.clear()

	EffectEngine.notify_hit(player, RefCounted.new(), null, 1.0)
	assert_eq(a.hits.size(), 1, "first effect on player fires")
	assert_eq(b.hits.size(), 1, "second effect on player fires")


func _test_round_start_fans_out_to_all_players() -> void:
	# dispatch_round_start is the fan-out invoked by the GameManager.round_started
	# signal handler; tested directly so it does not depend on autoload _ready.
	var p1 := _StubPlayer.new()
	var p2 := _StubPlayer.new()
	var e1 := _Recorder.new()
	var e2 := _Recorder.new()
	EffectEngine.apply_effect(p1, e1)
	EffectEngine.apply_effect(p2, e2)
	e1.hits.clear()
	e2.hits.clear()

	EffectEngine.dispatch_round_start(7)
	assert_eq(e1.hits.size(), 1, "round start reaches p1's effect")
	assert_eq(e2.hits.size(), 1, "round start reaches p2's effect")
	assert_eq(e1.hits[0]["hook"], "on_round_start", "round-start hook fired")
	assert_eq(e1.hits[0]["event"]["round"], 7, "event carries the round number")


func _test_duck_typed_effect_only_invokes_present_hooks() -> void:
	var player := _StubPlayer.new()
	var partial := _ShootOnly.new()
	EffectEngine.apply_effect(player, partial)

	# on_hit is absent — must be skipped silently, not crash.
	EffectEngine.notify_hit(player, RefCounted.new(), null, 5.0)
	assert_eq(partial.shots, 0, "absent on_hit hook is skipped")
	# on_shoot is present — must fire.
	EffectEngine.notify_shoot(player, null, null, Vector2.ZERO)
	assert_eq(partial.shots, 1, "present on_shoot hook fires")


func _test_remove_and_clear() -> void:
	var player := _StubPlayer.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(player, effect)
	EffectEngine.remove_effect(player, effect)
	assert_false(EffectEngine.has_effects(player), "remove_effect detaches the effect")

	EffectEngine.apply_effect(player, _Recorder.new())
	EffectEngine.clear_player(player)
	assert_false(EffectEngine.has_effects(player), "clear_player drops the player")

	EffectEngine.apply_effect(_StubPlayer.new(), _Recorder.new())
	EffectEngine.clear()
	assert_eq(EffectEngine.get_effects(player).size(), 0, "clear empties everything")

extends TestCase

## The victim-side effect wiring (#50): a Player forwards the damage it takes to
## the EffectEngine so its own `on_take_damage` effects fire, with itself as the
## victim and the attacker carried through. `_on_damaged` is the seam fed by
## `Health.damaged` (connected in `Player._ready`); it is exercised directly here
## so the test does not depend on the scene being in the tree.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")


## Records on_take_damage invocations for inspection.
class _Recorder extends CardEffect:
	var hits: Array = []
	func on_take_damage(ctx: EffectContext) -> void:
		hits.append({"player": ctx.player, "target": ctx.target, "damage": ctx.get_event("damage")})


func before_each() -> void:
	EffectEngine.clear()


func after_each() -> void:
	EffectEngine.clear()


func _test_player_forwards_taken_damage_to_its_effects() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	# `_on_damaged` (and `Health.damaged`) types the attacker as `Node`, so the
	# stand-in must be a Node, not a bare RefCounted.
	var attacker := Node.new()
	var effect := _Recorder.new()
	EffectEngine.apply_effect(player, effect)

	player._on_damaged(13.0, attacker)
	assert_eq(effect.hits.size(), 1, "the player's on_take_damage effect fired once")
	assert_eq(effect.hits[0]["player"], player, "the victim is this player")
	assert_eq(effect.hits[0]["target"], attacker, "the attacker is carried as the target")
	assert_almost_eq(effect.hits[0]["damage"], 13.0, "the damage taken is carried through")
	player.free()
	attacker.free()

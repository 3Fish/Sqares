extends TestCase

## Unit tests for EffectContext, the bundle passed to every CardEffect hook (#20).


func _test_defaults_are_empty() -> void:
	var ctx := EffectContext.new()
	assert_null(ctx.player, "player defaults to null")
	assert_null(ctx.weapon, "weapon defaults to null")
	assert_null(ctx.projectile, "projectile defaults to null")
	assert_null(ctx.target, "target defaults to null")
	assert_null(ctx.effect, "effect defaults to null")
	assert_eq(ctx.event.size(), 0, "event defaults to empty dict")


func _test_constructor_assigns_fields() -> void:
	var player := RefCounted.new()
	var weapon := RefCounted.new()
	var proj := RefCounted.new()
	var target := RefCounted.new()
	var ctx := EffectContext.new(player, weapon, proj, target, {"damage": 25.0})
	assert_eq(ctx.player, player, "player assigned")
	assert_eq(ctx.weapon, weapon, "weapon assigned")
	assert_eq(ctx.projectile, proj, "projectile assigned")
	assert_eq(ctx.target, target, "target assigned")
	assert_almost_eq(ctx.event["damage"], 25.0, "event payload assigned")


func _test_get_event_with_fallback() -> void:
	var ctx := EffectContext.new(null, null, null, null, {"round": 3})
	assert_eq(ctx.get_event("round"), 3, "get_event reads present key")
	assert_eq(ctx.get_event("missing", -1), -1, "get_event returns fallback for absent key")
	assert_null(ctx.get_event("missing"), "get_event fallback defaults to null")

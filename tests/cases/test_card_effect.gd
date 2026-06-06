extends TestCase

## Unit tests for the CardEffect base class (#20).


## A concrete effect overriding only the hooks it needs; the rest stay no-ops.
class _PartialEffect extends CardEffect:
	var applied: bool = false
	func on_apply(ctx: EffectContext) -> void:
		applied = true
		ctx.event["seen"] = true


func _test_base_hooks_are_callable_noops() -> void:
	var e := CardEffect.new()
	var ctx := EffectContext.new()
	# None of these should raise; they simply do nothing on the base class.
	e.on_apply(ctx)
	e.on_round_start(ctx)
	e.on_shoot(ctx)
	e.on_hit(ctx)
	assert_eq(ctx.event.size(), 0, "base hooks leave context untouched")
	assert_eq(e.id, "", "id defaults to empty string")


func _test_subclass_overrides_selected_hook() -> void:
	var e := _PartialEffect.new()
	var ctx := EffectContext.new()
	e.on_apply(ctx)
	assert_true(e.applied, "overridden on_apply runs")
	assert_true(ctx.get_event("seen", false), "overridden hook can mutate context")


func _test_assignable_to_card_effect_field() -> void:
	# Card.effect is typed Object; a CardEffect must slot in cleanly (#16 contract).
	var card := Card.new()
	card.id = "with_effect"
	var e := _PartialEffect.new()
	card.effect = e
	assert_eq(card.effect, e, "CardEffect is assignable to Card.effect")
	assert_true(card.effect is CardEffect, "Card.effect reports as CardEffect")

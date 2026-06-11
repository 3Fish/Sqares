extends TestCase

## Tests for the base-game card set (#18) and the StatCardEffect that backs it.
##
## Both the card factory (BaseCards.build) and the effect (StatCardEffect) are
## pure / scene-tree-free, so they are exercised directly without standing up the
## mod-loader autoload. One case drives the full card-pick path through the live
## EffectEngine autoload to confirm the card → engine → stat seam.


# The stats registered by the base game (mods/base_game/mod.gd). Hard-coded here
# rather than read from StatRegistry because the mod-loader runs deferred and is
# not guaranteed populated while the headless test harness runs.
const KNOWN_STATS := [
	"move_speed", "jump_force", "gravity_scale",
	"max_health", "damage", "fire_rate", "bullet_speed", "bullet_scale",
	"bullet_bounces", "bullet_homing", "lifesteal",
	"shield_charges", "knockback_force", "explosion_radius",
]


## Minimal Player stand-in satisfying the StatCardEffect contract: a `stats`
## PlayerStats plus an `apply_stats` that re-syncs (counted, like the real one).
class _StubPlayer extends RefCounted:
	var stats: PlayerStats
	var sync_calls: int = 0
	func _init(defaults: Dictionary = {}) -> void:
		stats = PlayerStats.new(defaults)
	func apply_stats(overrides: Dictionary) -> void:
		stats.merge(overrides)
		sync_calls += 1


func before_each() -> void:
	EffectEngine.clear()


# --- BaseCards.build -------------------------------------------------------

func _test_build_returns_a_dozen_valid_unique_cards() -> void:
	var cards := BaseCards.build()
	assert_eq(cards.size(), 12, "base set ships 12 cards")
	var ids := {}
	for card in cards:
		assert_true(card.is_valid(), "card '%s' is valid (non-empty id)" % card.id)
		assert_false(card.display_name.is_empty(), "card '%s' has a display name" % card.id)
		assert_false(card.description.is_empty(), "card '%s' has a description" % card.id)
		assert_false(ids.has(card.id), "card id '%s' is unique" % card.id)
		ids[card.id] = true


func _test_every_card_carries_a_stat_effect_with_known_stats() -> void:
	for card in BaseCards.build():
		assert_true(card.effect is StatCardEffect, "card '%s' has a StatCardEffect" % card.id)
		var effect: StatCardEffect = card.effect
		assert_eq(effect.id, card.id, "effect id mirrors the card id")
		assert_false(effect.deltas.is_empty(), "card '%s' grants at least one stat" % card.id)
		for stat_name in effect.deltas:
			assert_true(
				KNOWN_STATS.has(stat_name),
				"card '%s' references registered stat '%s'" % [card.id, stat_name])
			assert_true(
				typeof(effect.deltas[stat_name]) == TYPE_FLOAT,
				"card '%s' delta for '%s' is numeric" % [card.id, stat_name])


func _test_rarity_distribution_is_commons_heavy() -> void:
	var counts := {}
	for card in BaseCards.build():
		counts[card.rarity] = counts.get(card.rarity, 0) + 1
	assert_eq(counts.get(Card.Rarity.COMMON, 0), 4, "four common cards")
	assert_eq(counts.get(Card.Rarity.UNCOMMON, 0), 3, "three uncommon cards")
	assert_eq(counts.get(Card.Rarity.RARE, 0), 3, "three rare cards")
	assert_eq(counts.get(Card.Rarity.EPIC, 0), 1, "one epic card")
	assert_eq(counts.get(Card.Rarity.LEGENDARY, 0), 1, "one legendary card")
	# Commons must out-weigh the rest so the weighted draw skews common.
	assert_true(
		counts[Card.Rarity.COMMON] >= counts[Card.Rarity.RARE],
		"commons are at least as numerous as rares")


func _test_set_spans_all_three_pillars() -> void:
	# A union of every stat touched by the set must include a representative
	# from movement, offense, and defense — so no pillar is empty.
	var touched := {}
	for card in BaseCards.build():
		for stat_name in (card.effect as StatCardEffect).deltas:
			touched[stat_name] = true
	assert_true(touched.has("move_speed"), "movement pillar represented")
	assert_true(touched.has("damage"), "offense pillar represented")
	assert_true(touched.has("max_health"), "defense pillar represented")


# --- StatCardEffect --------------------------------------------------------

func _test_on_apply_adds_deltas_and_resyncs() -> void:
	var player := _StubPlayer.new({"move_speed": 300.0, "damage": 25.0})
	var effect := StatCardEffect.new({"move_speed": 60.0, "damage": 10.0}, "combo")
	effect.on_apply(EffectContext.new(player))
	assert_almost_eq(player.stats.get_stat("move_speed"), 360.0, "move_speed gains the delta")
	assert_almost_eq(player.stats.get_stat("damage"), 35.0, "damage gains the delta")
	assert_eq(player.sync_calls, 1, "components are re-synced once")


func _test_deltas_stack_additively_across_picks() -> void:
	# Picking the same card twice stacks (rogue-like accumulation, #43).
	var player := _StubPlayer.new({"move_speed": 300.0})
	var effect := StatCardEffect.new({"move_speed": 60.0}, "swift")
	effect.on_apply(EffectContext.new(player))
	effect.on_apply(EffectContext.new(player))
	assert_almost_eq(player.stats.get_stat("move_speed"), 420.0, "two picks stack")
	assert_eq(player.sync_calls, 2, "each pick re-syncs")


func _test_on_apply_tolerates_player_without_stats() -> void:
	# A player object lacking a stats bag must not crash. This intentionally
	# emits one expected push_error line — it is the guard firing, not a failure.
	var effect := StatCardEffect.new({"move_speed": 60.0})
	effect.on_apply(EffectContext.new(RefCounted.new()))
	effect.on_apply(EffectContext.new(null))
	assert_true(true, "missing stats / null player are handled without raising")


func _test_negative_delta_reduces_stat() -> void:
	var player := _StubPlayer.new({"gravity_scale": 1.0})
	StatCardEffect.new({"gravity_scale": -0.25}).on_apply(EffectContext.new(player))
	assert_almost_eq(player.stats.get_stat("gravity_scale"), 0.75, "negative delta lowers the stat")


# --- Card → EffectEngine → stat seam ---------------------------------------

func _test_applying_a_base_card_through_the_engine_mutates_stats() -> void:
	var player := _StubPlayer.new({"max_health": 100.0, "shield_charges": 0.0})
	var bulwark: Card = null
	for card in BaseCards.build():
		if card.id == "bulwark":
			bulwark = card
	assert_not_null(bulwark, "bulwark card exists in the set")

	EffectEngine.apply_effect(player, bulwark.effect)
	assert_true(EffectEngine.has_effects(player), "engine retains the attached effect")
	assert_almost_eq(player.stats.get_stat("max_health"), 175.0, "bulwark grants +75 max health")
	assert_almost_eq(player.stats.get_stat("shield_charges"), 1.0, "bulwark grants a shield charge")

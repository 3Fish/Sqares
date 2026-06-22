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

func _test_build_returns_the_full_valid_unique_set() -> void:
	var cards := BaseCards.build()
	assert_eq(cards.size(), 14, "base set ships 14 cards")
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
	assert_eq(counts.get(Card.Rarity.UNCOMMON, 0), 5, "five uncommon cards")
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


func _test_previously_uncarded_combat_stats_now_have_a_card() -> void:
	# Regression for #60: bullet_scale and knockback_force are registered and
	# consumed by Weapon/Projectile but had no card to grant them. Both must now
	# be reachable through the base set.
	var touched := {}
	for card in BaseCards.build():
		for stat_name in (card.effect as StatCardEffect).deltas:
			touched[stat_name] = true
	assert_true(touched.has("bullet_scale"), "a card now grants bullet_scale (Buckshot)")
	assert_true(touched.has("knockback_force"), "a card now grants knockback_force (Heavy Rounds)")


func _test_buckshot_and_heavy_rounds_carry_positive_deltas() -> void:
	# The two new offense cards must hand out positive bonuses for the stat they
	# advertise (a negative/zero delta would be a no-op or a downgrade).
	var by_id := {}
	for card in BaseCards.build():
		by_id[card.id] = card

	assert_true(by_id.has("buckshot"), "Buckshot card exists")
	assert_true(by_id.has("heavy_rounds"), "Heavy Rounds card exists")

	var buckshot: StatCardEffect = by_id["buckshot"].effect
	assert_true(buckshot.deltas.get("bullet_scale", 0.0) > 0.0, "Buckshot grows bullet_scale")

	var heavy: StatCardEffect = by_id["heavy_rounds"].effect
	assert_true(heavy.deltas.get("knockback_force", 0.0) > 0.0, "Heavy Rounds adds knockback_force")


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


func _test_on_apply_clamps_to_registered_bounds() -> void:
	# A delta that would push a bounded stat past its floor/cap is clamped to the
	# registered bound right after the mutation (#43). The probe stat is uniquely
	# named so it doesn't collide with the base game's stats.
	StatRegistry.register("clamp_card_floor", 10.0, 0.0)
	StatRegistry.register("clamp_card_cap", 10.0, -INF, 20.0)
	var player := _StubPlayer.new({"clamp_card_floor": 5.0, "clamp_card_cap": 18.0})
	# -8 would take the floor stat to -3 (clamped to 0); +9 would take the cap
	# stat to 27 (clamped to 20).
	StatCardEffect.new({"clamp_card_floor": -8.0, "clamp_card_cap": 9.0}).on_apply(EffectContext.new(player))
	assert_almost_eq(player.stats.get_stat("clamp_card_floor"), 0.0, "below-floor delta clamps up to the min")
	assert_almost_eq(player.stats.get_stat("clamp_card_cap"), 20.0, "above-cap delta clamps down to the max")


func _test_on_apply_leaves_unbounded_stat_unclamped() -> void:
	# A stat with no registered bound is never altered by clamping — the delta
	# applies in full (the modding-freedom default).
	StatRegistry.register("clamp_card_free", 10.0)
	var player := _StubPlayer.new({"clamp_card_free": 5.0})
	StatCardEffect.new({"clamp_card_free": -50.0}).on_apply(EffectContext.new(player))
	assert_almost_eq(player.stats.get_stat("clamp_card_free"), -45.0,
		"an unbounded stat takes the full (even negative) delta")


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

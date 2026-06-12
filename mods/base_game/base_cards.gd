class_name BaseCards extends RefCounted

## Authoring of the base-game card set (#18).
##
## `build()` is a pure static factory that returns the full set of base cards,
## each already wired to a `StatCardEffect`. Keeping it a static, scene-tree-free
## helper (the project's preferred pattern) lets the set be unit-tested directly
## without standing up the mod-loader autoload. The base-game mod calls `build()`
## from `_on_load()` and registers each card.
##
## The set spans the three rogue-like pillars — movement, offense, defense — and
## is distributed across rarities so #17's weighted draw (which consumes
## `Card.RARITY_WEIGHTS`) produces a sensible commons-heavy distribution without
## any per-card weight overrides:
##   COMMON x4, UNCOMMON x5, RARE x3, EPIC x1, LEGENDARY x1.
## Every card uses only stats already registered by the base game, so picking one
## has a real gameplay effect today. The offense pillar now covers every
## registered combat stat — including `bullet_scale` (Buckshot) and
## `knockback_force` (Heavy Rounds), which previously had no card (deferred in
## #60) even though `Weapon`/`Projectile` already consume them.


## A single card spec: id, name, rarity, flavour, and the additive stat deltas
## the card grants when picked.
class _Spec:
	var id: String
	var name: String
	var rarity: Card.Rarity
	var desc: String
	var deltas: Dictionary

	func _init(p_id: String, p_name: String, p_rarity: Card.Rarity, p_desc: String, p_deltas: Dictionary) -> void:
		id = p_id
		name = p_name
		rarity = p_rarity
		desc = p_desc
		deltas = p_deltas


## The authored specs. Edit here to tune the base set.
static func specs() -> Array:
	return [
		# --- Movement ----------------------------------------------------------
		_Spec.new(
			"swift_boots", "Swift Boots", Card.Rarity.COMMON,
			"Lighter on your feet. +60 move speed.",
			{"move_speed": 60.0}),
		_Spec.new(
			"spring_heels", "Spring Heels", Card.Rarity.COMMON,
			"Coiled legs launch you higher. +120 jump force.",
			{"jump_force": 120.0}),
		_Spec.new(
			"feather_fall", "Feather Fall", Card.Rarity.UNCOMMON,
			"Drift like a leaf. -25% gravity and a little extra hang time.",
			{"gravity_scale": -0.25, "jump_force": 40.0}),

		# --- Offense -----------------------------------------------------------
		_Spec.new(
			"sharp_rounds", "Sharp Rounds", Card.Rarity.COMMON,
			"Honed projectiles bite harder. +10 damage.",
			{"damage": 10.0}),
		_Spec.new(
			"rapid_fire", "Rapid Fire", Card.Rarity.UNCOMMON,
			"Squeeze the trigger faster. +0.75 shots per second.",
			{"fire_rate": 0.75}),
		_Spec.new(
			"high_velocity", "High-Velocity Rounds", Card.Rarity.UNCOMMON,
			"Flatter, faster shots. +250 bullet speed.",
			{"bullet_speed": 250.0}),
		_Spec.new(
			"buckshot", "Buckshot", Card.Rarity.UNCOMMON,
			"Chunkier rounds with a fatter hitbox. +0.5 bullet size.",
			{"bullet_scale": 0.5}),
		_Spec.new(
			"heavy_rounds", "Heavy Rounds", Card.Rarity.UNCOMMON,
			"Shots hit like a truck and shove foes back. +350 knockback force.",
			{"knockback_force": 350.0}),
		_Spec.new(
			"ricochet", "Ricochet", Card.Rarity.RARE,
			"Shots carom off geometry. +2 bullet bounces.",
			{"bullet_bounces": 2.0}),
		_Spec.new(
			"heat_seeker", "Heat Seeker", Card.Rarity.RARE,
			"Rounds curve toward the nearest foe. +0.5 homing.",
			{"bullet_homing": 0.5}),
		_Spec.new(
			"demolitionist", "Demolitionist", Card.Rarity.EPIC,
			"Impacts erupt. +60 explosion radius.",
			{"explosion_radius": 60.0}),

		# --- Defense -----------------------------------------------------------
		_Spec.new(
			"iron_hide", "Iron Hide", Card.Rarity.COMMON,
			"Tougher skin. +40 max health.",
			{"max_health": 40.0}),
		_Spec.new(
			"vampiric_rounds", "Vampiric Rounds", Card.Rarity.RARE,
			"Kills mend your wounds. +15 health restored per kill.",
			{"lifesteal": 15.0}),
		_Spec.new(
			"bulwark", "Bulwark", Card.Rarity.LEGENDARY,
			"An unbreakable wall. +75 max health and a shield charge.",
			{"max_health": 75.0, "shield_charges": 1.0}),
	]


## Builds the full base card set as ready-to-register `Card` instances, each
## wired to a `StatCardEffect` carrying its stat deltas.
static func build() -> Array[Card]:
	var cards: Array[Card] = []
	for spec in specs():
		var card := Card.new()
		card.id = spec.id
		card.display_name = spec.name
		card.description = spec.desc
		card.rarity = spec.rarity
		card.effect = StatCardEffect.new(spec.deltas, spec.id)
		cards.append(card)
	return cards

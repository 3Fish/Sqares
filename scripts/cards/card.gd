extends Resource
class_name Card

## Data definition for a single roguelike card.
##
## A card is the unit a losing player picks between rounds (#11). It carries the
## display metadata, a rarity used for weighted draws (#17), and a reference to
## the effect that runs when the card is applied. The effect engine itself is
## built in #20 — this class only holds a reference to it, so a card may be
## fully defined before the engine exists (`effect` stays null).
##
## Cards are registered with `CardRegistry`, usually from a mod's `_on_load()`,
## mirroring the `StatRegistry` / `LevelRegistry` pattern.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Default draw weight per rarity, consumed by the weighted-random draw in #17.
## A card may override its own weight via `weight` (see `get_weight`).
const RARITY_WEIGHTS: Dictionary = {
	Rarity.COMMON: 100.0,
	Rarity.UNCOMMON: 50.0,
	Rarity.RARE: 25.0,
	Rarity.EPIC: 10.0,
	Rarity.LEGENDARY: 3.0,
}

## Stable, unique identifier (e.g. "swift_boots"). Used as the registry key and
## as the override key when a mod replaces a built-in card.
@export var id: String = ""

## Human-readable name shown in the pick UI.
@export var display_name: String = ""

## Flavour / mechanical description shown in the pick UI.
@export var description: String = ""

## Drives default draw weight and UI styling.
@export var rarity: Rarity = Rarity.COMMON

## Optional per-card draw-weight override. Negative means "use the rarity
## default" (see `get_weight`); zero or above overrides it.
@export var weight: float = -1.0

## Reference to the effect this card applies. The concrete type is defined by
## the effect engine (#20); kept as a generic Object here so cards can be
## authored before the engine lands. May be null (metadata-only card).
var effect: Object = null


## Returns the effective draw weight: the per-card override when set, otherwise
## the rarity default. Never returns a negative value.
func get_weight() -> float:
	if weight >= 0.0:
		return weight
	return float(RARITY_WEIGHTS.get(rarity, 0.0))


## A card is valid for registration once it has a non-empty id.
func is_valid() -> bool:
	return not id.is_empty()


## Serialises the data fields to a plain, JSON-safe dictionary. The runtime
## `effect` reference is intentionally omitted — it is wired up at registration,
## not persisted as data.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"rarity": rarity_to_string(rarity),
		"weight": weight,
	}


## Populates this card from a dictionary (the inverse of `to_dict`). Missing
## keys fall back to defaults so partial/hand-authored data does not crash.
func from_dict(data: Dictionary) -> Card:
	id = String(data.get("id", id))
	display_name = String(data.get("display_name", display_name))
	description = String(data.get("description", description))
	rarity = rarity_from_string(String(data.get("rarity", rarity_to_string(rarity))))
	weight = float(data.get("weight", weight))
	return self


## Builds a new Card from a dictionary. Convenience for mods that prefer to
## declare cards as data rather than construct the object by hand.
static func create(data: Dictionary) -> Card:
	return Card.new().from_dict(data)


static func rarity_to_string(value: int) -> String:
	match value:
		Rarity.COMMON: return "common"
		Rarity.UNCOMMON: return "uncommon"
		Rarity.RARE: return "rare"
		Rarity.EPIC: return "epic"
		Rarity.LEGENDARY: return "legendary"
		_: return "common"


static func rarity_from_string(value: String) -> Rarity:
	match value.strip_edges().to_lower():
		"common": return Rarity.COMMON
		"uncommon": return Rarity.UNCOMMON
		"rare": return Rarity.RARE
		"epic": return Rarity.EPIC
		"legendary": return Rarity.LEGENDARY
		_: return Rarity.COMMON

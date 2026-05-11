extends Node

## Loads and indexes all card definitions from every active mod's cards/ folder.
## Cards are defined in YAML files. Mods may override built-in cards by matching ID.
## Implemented fully in feature/06-card-data-format.

# card_id -> card data Dictionary
var _cards: Dictionary = {}


func register_card(data: Dictionary) -> void:
	if not data.has("id"):
		push_error("CardRegistry: card data missing 'id' field.")
		return
	_cards[data["id"]] = data


func get_card(card_id: String) -> Dictionary:
	return _cards.get(card_id, {})


func get_all_cards() -> Array:
	return _cards.values()


func has_card(card_id: String) -> bool:
	return _cards.has(card_id)

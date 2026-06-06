extends Node

## Runtime registry of all card definitions. Cards are registered by mods at
## startup (mirroring the `StatRegistry` / `LevelRegistry` pattern) and indexed
## by their string id. Mods may override a built-in card by registering another
## card with the same id — last registration wins.

# card_id -> Card
var _cards: Dictionary = {}


## Registers a Card. A later registration with the same id overrides the
## previous one (the documented mod-override behaviour). Invalid cards (empty
## id) are rejected.
func register(card: Card) -> void:
	if card == null:
		push_error("CardRegistry: cannot register a null card.")
		return
	if not card.is_valid():
		push_error("CardRegistry: card missing 'id' field — skipping.")
		return
	_cards[card.id] = card


## Convenience entry point used by `SqaresModBase`. Accepts either a `Card` or a
## plain `Dictionary` (which is converted via `Card.create`), so existing
## dictionary-based callers keep working.
func register_card(data) -> void:
	if data is Card:
		register(data)
	elif data is Dictionary:
		register(Card.create(data))
	else:
		push_error("CardRegistry: register_card expects a Card or Dictionary.")


func get_card(card_id: String) -> Card:
	return _cards.get(card_id, null)


func get_all_cards() -> Array:
	return _cards.values()


## Returns every registered card of the given rarity.
func get_cards_by_rarity(rarity: Card.Rarity) -> Array:
	var result: Array = []
	for card in _cards.values():
		if card.rarity == rarity:
			result.append(card)
	return result


func has_card(card_id: String) -> bool:
	return _cards.has(card_id)


func get_card_ids() -> Array:
	return _cards.keys()


## Removes all registered cards. Primarily useful for tests and hot-reload.
func clear() -> void:
	_cards.clear()

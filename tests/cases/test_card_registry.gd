extends TestCase

## Integration tests for CardRegistry against the live autoload singleton (#16).
## Each case clears the registry first since its state is process-wide.

func before_each() -> void:
	CardRegistry.clear()


func _test_register_and_lookup() -> void:
	var c := Card.new()
	c.id = "alpha"
	CardRegistry.register(c)
	assert_true(CardRegistry.has_card("alpha"), "register then has_card")
	assert_eq(CardRegistry.get_card("alpha"), c, "get_card returns same instance")
	assert_eq(CardRegistry.get_all_cards().size(), 1, "get_all_cards count")
	assert_null(CardRegistry.get_card("missing"), "get_card returns null for missing id")


func _test_register_card_accepts_dictionary() -> void:
	CardRegistry.register_card({"id": "beta", "display_name": "Beta", "rarity": "rare"})
	assert_true(CardRegistry.has_card("beta"), "register_card builds Card from Dictionary")
	var c: Card = CardRegistry.get_card("beta")
	assert_eq(c.rarity, Card.Rarity.RARE, "dictionary rarity parsed to enum")


func _test_rejects_invalid_registrations() -> void:
	# The following intentionally emit push_error lines — they are expected.
	CardRegistry.register(null)
	CardRegistry.register(Card.new()) # empty id
	CardRegistry.register_card(42)    # wrong type
	assert_eq(CardRegistry.get_all_cards().size(), 0, "invalid registrations are rejected")


func _test_override_keeps_last_registration() -> void:
	var first := Card.new()
	first.id = "dup"
	first.display_name = "First"
	CardRegistry.register(first)
	var second := Card.new()
	second.id = "dup"
	second.display_name = "Second"
	CardRegistry.register(second)
	assert_eq(CardRegistry.get_all_cards().size(), 1, "override keeps a single entry")
	assert_eq(CardRegistry.get_card("dup").display_name, "Second", "override: last registration wins")


func _test_filters_by_rarity() -> void:
	var a := Card.new(); a.id = "a"; a.rarity = Card.Rarity.COMMON
	var b := Card.new(); b.id = "b"; b.rarity = Card.Rarity.RARE
	var c := Card.new(); c.id = "c"; c.rarity = Card.Rarity.RARE
	CardRegistry.register(a)
	CardRegistry.register(b)
	CardRegistry.register(c)
	assert_eq(CardRegistry.get_cards_by_rarity(Card.Rarity.RARE).size(), 2, "by_rarity filters RARE")
	assert_eq(CardRegistry.get_cards_by_rarity(Card.Rarity.COMMON).size(), 1, "by_rarity filters COMMON")
	assert_eq(CardRegistry.get_cards_by_rarity(Card.Rarity.EPIC).size(), 0, "by_rarity empty for absent rarity")

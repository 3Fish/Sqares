extends TestCase

## Unit tests for the Card resource (#16).


func _test_defaults_and_validity() -> void:
	var c := Card.new()
	assert_eq(c.rarity, Card.Rarity.COMMON, "default rarity is COMMON")
	assert_null(c.effect, "default effect is null")
	assert_false(c.is_valid(), "card without id is invalid")
	c.id = "x"
	assert_true(c.is_valid(), "card with id is valid")


func _test_weight_falls_back_to_rarity_default() -> void:
	var c := Card.new()
	c.rarity = Card.Rarity.RARE
	assert_eq(c.get_weight(), Card.RARITY_WEIGHTS[Card.Rarity.RARE], "weight falls back to rarity default")
	c.weight = 0.0
	assert_eq(c.get_weight(), 0.0, "explicit zero weight overrides rarity default")
	c.weight = 7.5
	assert_eq(c.get_weight(), 7.5, "explicit positive weight overrides rarity default")


func _test_rarity_string_round_trip() -> void:
	for r in [Card.Rarity.COMMON, Card.Rarity.UNCOMMON, Card.Rarity.RARE, Card.Rarity.EPIC, Card.Rarity.LEGENDARY]:
		var s := Card.rarity_to_string(r)
		assert_eq(Card.rarity_from_string(s), r, "rarity round-trips for %s" % s)
	assert_eq(Card.rarity_from_string("LEGENDARY"), Card.Rarity.LEGENDARY, "rarity parse is case-insensitive")
	assert_eq(Card.rarity_from_string("nonsense"), Card.Rarity.COMMON, "unknown rarity defaults to COMMON")


func _test_serialization_round_trip() -> void:
	var c := Card.new()
	c.id = "blaze"
	c.display_name = "Blaze"
	c.description = "Burn them."
	c.rarity = Card.Rarity.EPIC
	c.weight = 12.0

	var d := c.to_dict()
	assert_eq(d["rarity"], "epic", "to_dict serialises rarity as string")

	# Must be JSON-safe (no enum/object leakage).
	var json := JSON.stringify(d)
	assert_true(not json.is_empty(), "to_dict output is JSON-stringifiable")

	var round := Card.create(d)
	assert_eq(round.id, c.id, "round-trip preserves id")
	assert_eq(round.display_name, c.display_name, "round-trip preserves display_name")
	assert_eq(round.description, c.description, "round-trip preserves description")
	assert_eq(round.rarity, c.rarity, "round-trip preserves rarity")
	assert_eq(round.get_weight(), c.get_weight(), "round-trip preserves weight")


func _test_create_from_partial_dict_keeps_defaults() -> void:
	var partial := Card.create({"id": "only_id"})
	assert_eq(partial.id, "only_id", "create from partial dict sets id")
	assert_eq(partial.rarity, Card.Rarity.COMMON, "create from partial dict defaults rarity")

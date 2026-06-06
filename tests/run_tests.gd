extends SceneTree

## Minimal headless test harness for the card model + registry (#16).
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits with code 0 when all assertions pass, 1 otherwise. The project ships no
## third-party test framework, so this is a dependency-free SceneTree runner.
## Tests wait one idle frame so that ModLoader's deferred mod load completes
## before the base-game pipeline is asserted.

var _passed: int = 0
var _failed: int = 0
var _frames: int = 0

# Autoload singletons are not resolvable as global identifiers from the script
# that *is* the main loop, so we fetch the registry node by path at runtime.
var _reg: Node = null


func _process(_delta: float) -> bool:
	# Let the autoloads' deferred _ready() callbacks (ModLoader -> base_game) run.
	_frames += 1
	if _frames < 2:
		return false

	_reg = root.get_node("/root/CardRegistry")

	print("== Running card tests ==")
	_test_base_game_pipeline()
	_test_card_defaults_and_validity()
	_test_card_weights()
	_test_rarity_string_conversion()
	_test_card_serialization()
	_test_registry_register_and_lookup()
	_test_registry_dictionary_entry_point()
	_test_registry_rejects_invalid()
	_test_registry_override()
	_test_registry_by_rarity()

	print("\n== Results: %d passed, %d failed ==" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


# --- assertions -------------------------------------------------------------

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s" % label)


func _eq(actual, expected, label: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])


# --- pipeline ---------------------------------------------------------------

func _test_base_game_pipeline() -> void:
	# base_game/mod.gd must have registered the sample card via the public API.
	_check(_reg.has_card("swift_boots"), "base_game registers sample card")
	var c: Card = _reg.get_card("swift_boots")
	_check(c != null, "sample card retrievable")
	if c != null:
		_eq(c.display_name, "Swift Boots", "sample card display_name")
		_eq(c.rarity, Card.Rarity.COMMON, "sample card rarity")


# --- Card unit tests --------------------------------------------------------

func _test_card_defaults_and_validity() -> void:
	var c := Card.new()
	_eq(c.rarity, Card.Rarity.COMMON, "default rarity is COMMON")
	_eq(c.effect, null, "default effect is null")
	_check(not c.is_valid(), "card without id is invalid")
	c.id = "x"
	_check(c.is_valid(), "card with id is valid")


func _test_card_weights() -> void:
	var c := Card.new()
	c.rarity = Card.Rarity.RARE
	_eq(c.get_weight(), Card.RARITY_WEIGHTS[Card.Rarity.RARE], "weight falls back to rarity default")
	c.weight = 0.0
	_eq(c.get_weight(), 0.0, "explicit zero weight overrides rarity default")
	c.weight = 7.5
	_eq(c.get_weight(), 7.5, "explicit positive weight overrides rarity default")


func _test_rarity_string_conversion() -> void:
	for r in [Card.Rarity.COMMON, Card.Rarity.UNCOMMON, Card.Rarity.RARE, Card.Rarity.EPIC, Card.Rarity.LEGENDARY]:
		var s := Card.rarity_to_string(r)
		_eq(Card.rarity_from_string(s), r, "rarity round-trips for %s" % s)
	_eq(Card.rarity_from_string("LEGENDARY"), Card.Rarity.LEGENDARY, "rarity parse is case-insensitive")
	_eq(Card.rarity_from_string("nonsense"), Card.Rarity.COMMON, "unknown rarity defaults to COMMON")


func _test_card_serialization() -> void:
	var c := Card.new()
	c.id = "blaze"
	c.display_name = "Blaze"
	c.description = "Burn them."
	c.rarity = Card.Rarity.EPIC
	c.weight = 12.0

	var d := c.to_dict()
	_eq(d["rarity"], "epic", "to_dict serialises rarity as string")

	# Must be JSON-safe (no enum/object leakage).
	var json := JSON.stringify(d)
	_check(not json.is_empty(), "to_dict output is JSON-stringifiable")

	var round := Card.create(d)
	_eq(round.id, c.id, "round-trip preserves id")
	_eq(round.display_name, c.display_name, "round-trip preserves display_name")
	_eq(round.description, c.description, "round-trip preserves description")
	_eq(round.rarity, c.rarity, "round-trip preserves rarity")
	_eq(round.get_weight(), c.get_weight(), "round-trip preserves weight")

	# Defensive: missing keys keep defaults rather than crashing.
	var partial := Card.create({"id": "only_id"})
	_eq(partial.id, "only_id", "create from partial dict sets id")
	_eq(partial.rarity, Card.Rarity.COMMON, "create from partial dict defaults rarity")


# --- CardRegistry tests -----------------------------------------------------
# These mutate the shared registry, so each clears it first.

func _test_registry_register_and_lookup() -> void:
	_reg.clear()
	var c := Card.new()
	c.id = "alpha"
	_reg.register(c)
	_check(_reg.has_card("alpha"), "register then has_card")
	_eq(_reg.get_card("alpha"), c, "get_card returns same instance")
	_eq(_reg.get_all_cards().size(), 1, "get_all_cards count")
	_eq(_reg.get_card("missing"), null, "get_card returns null for missing id")


func _test_registry_dictionary_entry_point() -> void:
	_reg.clear()
	_reg.register_card({"id": "beta", "display_name": "Beta", "rarity": "rare"})
	_check(_reg.has_card("beta"), "register_card builds Card from Dictionary")
	var c: Card = _reg.get_card("beta")
	_eq(c.rarity, Card.Rarity.RARE, "dictionary rarity parsed to enum")


func _test_registry_rejects_invalid() -> void:
	_reg.clear()
	# The following intentionally emit push_error lines — they are expected.
	_reg.register(null)
	_reg.register(Card.new()) # empty id
	_reg.register_card(42)    # wrong type
	_eq(_reg.get_all_cards().size(), 0, "invalid registrations are rejected")


func _test_registry_override() -> void:
	_reg.clear()
	var first := Card.new()
	first.id = "dup"
	first.display_name = "First"
	_reg.register(first)
	var second := Card.new()
	second.id = "dup"
	second.display_name = "Second"
	_reg.register(second)
	_eq(_reg.get_all_cards().size(), 1, "override keeps a single entry")
	_eq(_reg.get_card("dup").display_name, "Second", "override: last registration wins")


func _test_registry_by_rarity() -> void:
	_reg.clear()
	var a := Card.new(); a.id = "a"; a.rarity = Card.Rarity.COMMON
	var b := Card.new(); b.id = "b"; b.rarity = Card.Rarity.RARE
	var c := Card.new(); c.id = "c"; c.rarity = Card.Rarity.RARE
	_reg.register(a)
	_reg.register(b)
	_reg.register(c)
	_eq(_reg.get_cards_by_rarity(Card.Rarity.RARE).size(), 2, "by_rarity filters RARE")
	_eq(_reg.get_cards_by_rarity(Card.Rarity.COMMON).size(), 1, "by_rarity filters COMMON")
	_eq(_reg.get_cards_by_rarity(Card.Rarity.EPIC).size(), 0, "by_rarity empty for absent rarity")

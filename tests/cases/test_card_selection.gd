extends TestCase

## Tests for the card-selection phase wiring (#17): the pure index-wrap helper
## used by the selection UI, and the GameManager state transition that opens the
## phase. The UI's input/scene-tree behaviour itself is boot-verified (the
## headless harness does not pump per-player Input), consistent with the
## autoload/scene-`_ready` limitation noted across the deferred-questions issues.
##
## Also covers the card draw/pick UI-cue wiring (#58, deferred from #30): the pure
## `has_drawable_cards` gate, plus the two trigger sites driven directly (present a
## hand → CARD_DRAW; lock in a pick → CARD_PICK) without simulating per-player Input.


func before_each() -> void:
	# Register the UI cue streams so play_ui hits the real (non-warning) path, and
	# clear the director's last-ui-cue so each case asserts from a known state.
	for cue: String in SfxDirector.ALL_UI_CUES:
		AudioManager.register_sound(cue, AudioStreamGenerator.new())
	SfxDirector._last_ui_cue = ""


func _make_card(id_str: String) -> Card:
	return Card.create({"id": id_str, "display_name": id_str, "description": "d", "rarity": "common"})


func _test_wrap_index_steps_and_wraps() -> void:
	assert_eq(CardSelectionUI.wrap_index(0, 1, 3), 1, "step right")
	assert_eq(CardSelectionUI.wrap_index(1, 1, 3), 2, "step right again")
	assert_eq(CardSelectionUI.wrap_index(2, 1, 3), 0, "wraps past the end to the front")
	assert_eq(CardSelectionUI.wrap_index(0, -1, 3), 2, "wraps before the start to the back")
	assert_eq(CardSelectionUI.wrap_index(1, -1, 3), 0, "step left")


func _test_wrap_index_single_and_degenerate() -> void:
	assert_eq(CardSelectionUI.wrap_index(0, 1, 1), 0, "single card: navigation is a no-op")
	assert_eq(CardSelectionUI.wrap_index(0, -1, 1), 0, "single card: left is a no-op")
	assert_eq(CardSelectionUI.wrap_index(0, 1, 0), 0, "empty list never indexes out of range")
	assert_eq(CardSelectionUI.wrap_index(3, 1, 0), 0, "empty list clamps to 0 regardless of input")


func _test_begin_card_selection_enters_state() -> void:
	GameManager.change_state(GameManager.State.ROUND_END)
	GameManager.begin_card_selection()
	assert_eq(GameManager.state, GameManager.State.CARD_SELECTION, "begin_card_selection enters CARD_SELECTION")


# --- card draw / pick UI cues (#58) ----------------------------------------

func _test_has_drawable_cards() -> void:
	assert_false(CardSelectionUI.has_drawable_cards({}), "no players → nothing to draw")
	assert_false(CardSelectionUI.has_drawable_cards({0: [], 1: []}), "all hands empty → nothing to draw")
	assert_true(CardSelectionUI.has_drawable_cards({0: [_make_card("a")]}), "one non-empty hand → drawable")
	assert_true(CardSelectionUI.has_drawable_cards({0: [], 1: [_make_card("a")]}), "any non-empty hand → drawable")


func _test_begin_with_cards_plays_draw_cue() -> void:
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	ui.begin({0: [_make_card("a"), _make_card("b")]})
	assert_eq(SfxDirector.last_ui_cue(), SfxDirector.CARD_DRAW, "presenting a hand plays the card-draw cue")
	ui.queue_free()


func _test_begin_without_cards_is_silent() -> void:
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	ui.begin({0: []})  # a loser whose hand is empty: nothing to pick
	assert_eq(SfxDirector.last_ui_cue(), "", "an empty round presents no card-draw cue")
	ui.queue_free()


func _test_confirm_plays_pick_cue() -> void:
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	ui.begin({0: [_make_card("a")]})
	SfxDirector._last_ui_cue = ""  # disregard the draw cue fired by begin()
	ui._confirm(0)
	assert_eq(SfxDirector.last_ui_cue(), SfxDirector.CARD_PICK, "locking in a card plays the card-pick cue")
	ui.queue_free()


# --- online single-slot pick screen (#82) ----------------------------------

func _test_begin_subset_slot_picks_correctly() -> void:
	# Online each peer shows only its own losing slot, with input remapped to p1.
	# The pick still resolves against that slot's hand regardless of the override.
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	# A holder dict is mutated (not reassigned) so the lambda's capture sees it.
	var holder: Dictionary = {"picks": {}}
	ui.selection_complete.connect(func(p: Dictionary) -> void: holder["picks"] = p)
	ui.begin({2: [_make_card("x"), _make_card("y")]}, {2: 0})
	ui._confirm(2)
	var captured: Dictionary = holder["picks"]
	assert_true(captured.has(2), "completion reports the shown slot")
	assert_eq(captured.size(), 1, "only the single shown panel is reported")
	assert_eq(captured[2].id, "x", "the highlighted (first) card is the pick")
	ui.queue_free()


# --- sequential ("One By One") mode (#169) ---------------------------------

func _test_sequential_hands_off_in_order_and_completes() -> void:
	# Only the active picker (first in `order`) is live; confirming hands off to the
	# next in order, and the screen completes once the last picker locks in.
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	var holder: Dictionary = {"picks": {}}
	ui.selection_complete.connect(func(p: Dictionary) -> void: holder["picks"] = p)
	ui.begin({0: [_make_card("a")], 1: [_make_card("b")]}, {},
		{"mode": CardPickMode.SEQUENTIAL, "order": [1, 0]})
	assert_eq(ui._active, 1, "first slot in the order is active")
	ui._confirm(1)
	assert_eq(ui._active, 0, "confirming hands off to the next slot in the order")
	assert_true(holder["picks"].is_empty(), "phase not complete until every picker has locked in")
	ui._confirm(0)
	assert_eq(ui._active, -1, "no active picker once all have confirmed")
	assert_eq((holder["picks"] as Dictionary).size(), 2, "completion reports both picks")
	ui.queue_free()


func _test_sequential_skips_empty_hands() -> void:
	# An empty-hand loser is auto-confirmed in begin() and skipped by the hand-off,
	# so the active picker lands on the first slot that actually has cards.
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	ui.begin({0: [], 1: [_make_card("b")]}, {},
		{"mode": CardPickMode.SEQUENTIAL, "order": [0, 1]})
	assert_eq(ui._active, 1, "the empty-hand slot is skipped; slot 1 is active")
	ui.queue_free()


func _test_auto_pick_confirms_a_card_from_the_hand() -> void:
	# A timeout auto-pick chooses a card from the hand (via the seeded rng) and
	# confirms the panel, so the phase settles even if nobody pressed a button.
	var ui := CardSelectionUI.new()
	runner.root.add_child(ui)
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var holder: Dictionary = {"picks": {}}
	ui.selection_complete.connect(func(p: Dictionary) -> void: holder["picks"] = p)
	ui.begin({0: [_make_card("a"), _make_card("b"), _make_card("c")]}, {},
		{"mode": CardPickMode.PARALLEL, "timeout": 5.0, "rng": rng})
	ui._auto_pick(0)
	var captured: Dictionary = holder["picks"]
	assert_true(captured.has(0), "auto-pick confirms the panel")
	assert_not_null(captured[0], "auto-pick chose a real card from the hand")
	ui.queue_free()

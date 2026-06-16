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

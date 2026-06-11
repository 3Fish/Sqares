extends TestCase

## Tests for the card-selection phase wiring (#17): the pure index-wrap helper
## used by the selection UI, and the GameManager state transition that opens the
## phase. The UI's input/scene-tree behaviour itself is boot-verified (the
## headless harness does not pump per-player Input), consistent with the
## autoload/scene-`_ready` limitation noted across the deferred-questions issues.


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

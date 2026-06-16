extends TestCase

## Covers `EditorUndoHistory` (#72, deferred from #35): the pure snapshot-stack
## discipline behind the arena editor's undo/redo — push/undo/redo ordering,
## redo invalidation on a new edit, the no-op filter, the depth cap, and the
## per-document reset.

var _history: EditorUndoHistory


func before_each() -> void:
	_history = EditorUndoHistory.new()


## A tiny distinct state; shaped like (but not required to be) a to_dict() blob.
func _state(n: int) -> Dictionary:
	return {"id": "arena_%d" % n, "platforms": [{"position": [float(n), 0.0]}]}


func _test_empty_history_has_nothing_to_undo_or_redo() -> void:
	assert_false(_history.can_undo(), "fresh history has no undo")
	assert_false(_history.can_redo(), "fresh history has no redo")
	assert_true(_history.undo(_state(0)).is_empty(), "undo on empty returns {}")
	assert_true(_history.redo(_state(0)).is_empty(), "redo on empty returns {}")
	# Failed undo/redo must not corrupt the stacks (no phantom redo step).
	assert_false(_history.can_redo(), "failed undo records nothing")
	assert_false(_history.can_undo(), "failed redo records nothing")


func _test_undo_returns_pushed_state_and_enables_redo() -> void:
	_history.push(_state(1))
	assert_true(_history.can_undo(), "push enables undo")
	var restored := _history.undo(_state(2))
	assert_eq(restored, _state(1), "undo returns the pre-edit state")
	assert_false(_history.can_undo(), "single step used up")
	assert_true(_history.can_redo(), "undone step is redoable")
	assert_eq(_history.redo(restored), _state(2), "redo returns the undone state")


func _test_multi_step_walk_back_and_forward() -> void:
	# Edits: 1 -> 2 -> 3 (current). Pushes record the state *before* each edit.
	_history.push(_state(1))
	_history.push(_state(2))
	var current := _history.undo(_state(3))
	assert_eq(current, _state(2), "first undo -> state 2")
	current = _history.undo(current)
	assert_eq(current, _state(1), "second undo -> state 1")
	assert_false(_history.can_undo(), "walked back to the oldest state")
	current = _history.redo(current)
	assert_eq(current, _state(2), "first redo -> state 2")
	current = _history.redo(current)
	assert_eq(current, _state(3), "second redo -> state 3")
	assert_false(_history.can_redo(), "walked forward to the newest state")


func _test_new_push_clears_redo() -> void:
	_history.push(_state(1))
	_history.undo(_state(2))
	assert_true(_history.can_redo(), "undo made a redo step")
	_history.push(_state(4))
	assert_false(_history.can_redo(), "a new edit invalidates redo")


func _test_push_if_changed_skips_equal_states() -> void:
	# Deep equality: a real to_dict() round-trip produces nested arrays/dicts.
	var arena := ArenaData.new().add_platform(Vector2(10, 20), Vector2(64, 16))
	var before := arena.to_dict()
	var same := ArenaData.from_dict(before).to_dict()
	assert_false(_history.push_if_changed(before, same), "no-op edit not recorded")
	assert_false(_history.can_undo(), "no step pushed for a no-op")

	arena.add_spawn_point(Vector2(0, -50))
	assert_true(_history.push_if_changed(before, arena.to_dict()), "real change recorded")
	assert_eq(_history.undo(arena.to_dict()), before, "undo restores the pre-edit snapshot")


func _test_oldest_steps_dropped_beyond_cap() -> void:
	var extra := 5
	for i in EditorUndoHistory.MAX_STEPS + extra:
		_history.push(_state(i))
	var steps := 0
	var current := _state(EditorUndoHistory.MAX_STEPS + extra)
	while _history.can_undo():
		current = _history.undo(current)
		steps += 1
	assert_eq(steps, EditorUndoHistory.MAX_STEPS, "depth capped at MAX_STEPS")
	assert_eq(current, _state(extra), "oldest states were the ones dropped")


func _test_clear_drops_both_stacks() -> void:
	_history.push(_state(1))
	_history.undo(_state(2))
	_history.push(_state(3))
	_history.clear()
	assert_false(_history.can_undo(), "clear drops undo steps")
	assert_false(_history.can_redo(), "clear drops redo steps")


# --- selection paired with each step (#79) ----------------------------------

func _sel(kind: int, index: int) -> Dictionary:
	return {"kind": kind, "index": index}


func _test_undo_restores_pre_edit_selection_and_redo_restores_edit_selection() -> void:
	# Edit recorded the pre-edit state (1) with its selection; the live state (2)
	# carries the selection that was current at the edit.
	_history.push(_state(1), _sel(1, 7))
	assert_eq(_history.undo(_state(2), _sel(2, 9)), _state(1), "undo returns the pre-edit state")
	assert_eq(_history.restored_selection, _sel(1, 7), "undo restores the pre-edit selection")
	assert_eq(_history.redo(_state(1), _sel(1, 7)), _state(2), "redo returns the undone state")
	assert_eq(_history.restored_selection, _sel(2, 9), "redo restores the selection current at the edit")


func _test_selection_defaults_to_empty_when_not_supplied() -> void:
	# The existing callers/tests that pass no selection must still work; the
	# restored selection is then empty (the caller clears the selection).
	_history.push(_state(1))
	_history.undo(_state(2))
	assert_eq(_history.restored_selection, {}, "no recorded selection -> empty")


func _test_failed_undo_redo_clears_restored_selection() -> void:
	_history.push(_state(1), _sel(1, 1))
	_history.undo(_state(2), _sel(2, 2))
	assert_eq(_history.restored_selection, _sel(1, 1), "precondition: a selection was restored")
	# Nothing left to undo: the stale selection must not linger.
	assert_true(_history.undo(_state(1)).is_empty(), "no further undo")
	assert_eq(_history.restored_selection, {}, "failed undo clears restored selection")


func _test_clear_resets_restored_selection() -> void:
	_history.push(_state(1), _sel(1, 0))
	_history.undo(_state(2), _sel(2, 0))
	_history.clear()
	assert_eq(_history.restored_selection, {}, "clear resets restored selection")


func _test_selection_stays_aligned_through_depth_cap() -> void:
	# Selections are dropped in lockstep with their snapshots when the cap trims
	# the oldest steps, so the surviving selection still matches its state.
	var extra := 3
	for i in EditorUndoHistory.MAX_STEPS + extra:
		_history.push(_state(i), _sel(1, i))
	var current := _state(EditorUndoHistory.MAX_STEPS + extra)
	var current_sel := _sel(1, EditorUndoHistory.MAX_STEPS + extra)
	while _history.can_undo():
		current = _history.undo(current, current_sel)
		current_sel = _history.restored_selection
	assert_eq(current, _state(extra), "oldest kept state")
	assert_eq(current_sel, _sel(1, extra), "its selection survived the cap drop alignment")

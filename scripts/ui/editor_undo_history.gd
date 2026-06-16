extends RefCounted
class_name EditorUndoHistory

## Snapshot-based undo/redo history for the arena editor (#72, deferred from
## #35; selection restore #79). States are the plain dictionaries produced by
## `ArenaData.to_dict()`: the canvas captures one snapshot per completed edit
## gesture and restores a popped state via `ArenaData.from_dict()`. Pure data
## container with no scene-tree dependency, so the whole stack discipline is
## unit-testable headlessly.
##
## Each step also carries the *selection* that was active alongside its snapshot
## (a `{ "kind", "index" }` dictionary). The selection is opaque to the history
## — stored and returned verbatim — so the canvas can restore it instead of
## dropping it on every undo/redo (#79). After a successful `undo()`/`redo()`,
## the selection paired with the returned snapshot is exposed via
## `restored_selection` (the caller validates the index against the restored
## arena before applying it). Change detection still compares snapshots only, so
## a selection-only change never records an undo step.
##
## `undo()`/`redo()` take the *current* state and return the state to restore,
## or an empty Dictionary when there is no step in that direction (a real
## `to_dict()` snapshot is never empty — it always carries the schema keys).

## Oldest steps are dropped once the undo stack grows beyond this many states.
const MAX_STEPS: int = 100

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
# Selections paired positionally with the snapshots in the stacks above.
var _undo_sel: Array[Dictionary] = []
var _redo_sel: Array[Dictionary] = []

## Selection ({ "kind", "index" }) paired with the snapshot returned by the most
## recent successful `undo()`/`redo()`; an empty Dictionary when there was no
## step to restore or no selection was recorded with it.
var restored_selection: Dictionary = {}


## Record `before` as an undo step only when the edit actually changed
## something. `before_sel` is the selection that was active in `before`.
## Returns true when a step was recorded.
func push_if_changed(before: Dictionary, after: Dictionary, before_sel: Dictionary = {}) -> bool:
	if before == after:
		return false
	push(before, before_sel)
	return true


## Record the state (and its selection) that preceded an edit. Any redoable
## steps are invalidated, matching the universal "new edit clears redo"
## convention.
func push(before: Dictionary, before_sel: Dictionary = {}) -> void:
	_undo_stack.append(before)
	_undo_sel.append(before_sel)
	if _undo_stack.size() > MAX_STEPS:
		_undo_stack.pop_front()
		_undo_sel.pop_front()
	_redo_stack.clear()
	_redo_sel.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Step back once: `current` (with `current_sel`) becomes redoable and the
## preceding state is returned, with its selection exposed via
## `restored_selection`. Returns an empty Dictionary when there is nothing to undo.
func undo(current: Dictionary, current_sel: Dictionary = {}) -> Dictionary:
	if _undo_stack.is_empty():
		restored_selection = {}
		return {}
	_redo_stack.append(current)
	_redo_sel.append(current_sel)
	restored_selection = _undo_sel.pop_back()
	return _undo_stack.pop_back()


## Step forward once: `current` (with `current_sel`) becomes undoable and the
## undone state is returned, with its selection exposed via `restored_selection`.
## Returns an empty Dictionary when there is nothing to redo.
func redo(current: Dictionary, current_sel: Dictionary = {}) -> Dictionary:
	if _redo_stack.is_empty():
		restored_selection = {}
		return {}
	_undo_stack.append(current)
	_undo_sel.append(current_sel)
	restored_selection = _redo_sel.pop_back()
	return _redo_stack.pop_back()


## Drop all history (used when the edited document is replaced via New/Load).
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_undo_sel.clear()
	_redo_sel.clear()
	restored_selection = {}

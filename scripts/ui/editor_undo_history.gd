extends RefCounted
class_name EditorUndoHistory

## Snapshot-based undo/redo history for the arena editor (#72, deferred from
## #35). States are the plain dictionaries produced by `ArenaData.to_dict()`:
## the canvas captures one snapshot per completed edit gesture and restores a
## popped state via `ArenaData.from_dict()`. Pure data container with no
## scene-tree dependency, so the whole stack discipline is unit-testable
## headlessly.
##
## `undo()`/`redo()` take the *current* state and return the state to restore,
## or an empty Dictionary when there is no step in that direction (a real
## `to_dict()` snapshot is never empty — it always carries the schema keys).

## Oldest steps are dropped once the undo stack grows beyond this many states.
const MAX_STEPS: int = 100

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []


## Record `before` as an undo step only when the edit actually changed
## something. Returns true when a step was recorded.
func push_if_changed(before: Dictionary, after: Dictionary) -> bool:
	if before == after:
		return false
	push(before)
	return true


## Record the state that preceded an edit. Any redoable steps are invalidated,
## matching the universal "new edit clears redo" convention.
func push(before: Dictionary) -> void:
	_undo_stack.append(before)
	if _undo_stack.size() > MAX_STEPS:
		_undo_stack.pop_front()
	_redo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Step back once: `current` becomes redoable and the preceding state is
## returned. Returns an empty Dictionary when there is nothing to undo.
func undo(current: Dictionary) -> Dictionary:
	if _undo_stack.is_empty():
		return {}
	_redo_stack.append(current)
	return _undo_stack.pop_back()


## Step forward once: `current` becomes undoable and the undone state is
## returned. Returns an empty Dictionary when there is nothing to redo.
func redo(current: Dictionary) -> Dictionary:
	if _redo_stack.is_empty():
		return {}
	_undo_stack.append(current)
	return _redo_stack.pop_back()


## Drop all history (used when the edited document is replaced via New/Load).
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()

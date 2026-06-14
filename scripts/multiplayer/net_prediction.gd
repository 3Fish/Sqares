extends RefCounted
class_name NetPrediction

## Client-side prediction history for input reconciliation (#27).
##
## A networked client applies its own input immediately (prediction) and
## records the input plus the post-step state here, keyed by the input's
## sequence number. When an authoritative snapshot arrives, the client:
##   1. looks up its recorded state at the snapshot's acked `last_input_seq`,
##   2. drops everything up to and including that ack,
##   3. if the authoritative position disagrees beyond a small tolerance,
##      rewinds to the authoritative state and replays the still-pending inputs.
##
## Pure data bookkeeping with no scene-tree dependency — the replay itself
## (re-running the movement step) lives on `Player.reconcile`, which owns the
## physics body. Entries are plain Dictionaries so the replay can update the
## re-predicted state in place.

## Hard cap on retained history. At 60 ticks/s this is two seconds of inputs —
## far beyond any ack gap a live connection produces; beyond it the oldest
## entries are dropped (they could no longer be acked meaningfully anyway).
const MAX_HISTORY := 120

## Ordered oldest→newest: { "seq": int, "input": NetPlayerInput,
## "position": Vector2, "velocity": Vector2 } (state is post-step).
var _entries: Array[Dictionary] = []


## Records one predicted tick: the input applied and the resulting state.
func record(input: NetPlayerInput, position: Vector2, velocity: Vector2) -> void:
	_entries.append({
		"seq": input.seq,
		"input": input,
		"position": position,
		"velocity": velocity,
	})
	while _entries.size() > MAX_HISTORY:
		_entries.pop_front()


## Drops every entry the host has acknowledged (seq <= `acked_seq`).
func ack(acked_seq: int) -> void:
	while not _entries.is_empty() and int(_entries[0]["seq"]) <= acked_seq:
		_entries.pop_front()


## The recorded entry for `seq`, or null when it was never recorded or has
## already been acked/evicted. Returned as the live Dictionary so replay can
## refresh it in place.
func state_at(seq: int) -> Variant:
	for entry in _entries:
		if int(entry["seq"]) == seq:
			return entry
	return null


## All not-yet-acked entries, oldest first — the inputs a correction replays.
func pending() -> Array[Dictionary]:
	return _entries


## The newest `max_count` pending inputs, oldest first. Each input send
## re-sends this window so the unreliable input stream tolerates packet loss.
func pending_inputs(max_count: int) -> Array:
	var inputs: Array = []
	var start: int = maxi(_entries.size() - max_count, 0)
	for i in range(start, _entries.size()):
		inputs.append(_entries[i]["input"])
	return inputs


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()


## Whether the authoritative position disagrees with the prediction by more
## than `tolerance` pixels — the trigger for a rewind + replay. Pure so the
## threshold behaviour is unit-testable.
static func needs_correction(predicted: Vector2, authoritative: Vector2, tolerance: float) -> bool:
	return predicted.distance_squared_to(authoritative) > tolerance * tolerance

extends Node

## Central state machine for round and match flow.
## Implemented fully in feature/05-round-match-flow.

enum State { MENU, LOBBY, ROUND, CARD_SELECTION, MATCH_END }

var state: State = State.MENU
var round_number: int = 0
var rounds_to_win: int = 5
# player_id -> wins
var win_counts: Dictionary = {}

signal state_changed(new_state: State)
signal round_started(round_num: int)
signal round_ended(loser_ids: Array)
signal match_ended(winner_id: int)


func change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)

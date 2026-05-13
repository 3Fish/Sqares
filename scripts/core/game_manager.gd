extends Node

## Central state machine for round and match flow.

enum State { MENU, ROUND_INTRO, ROUND, ROUND_END, CARD_SELECTION, MATCH_END }

var state: State = State.MENU
var round_number: int = 0
var rounds_to_win: int = 5
var current_arena_id: String = "crossroads"
# player_id (int) -> win count
var win_counts: Dictionary[int, int] = {}

signal state_changed(new_state: State)
signal round_started(round_num: int)
signal round_ended(loser_ids: Array)
signal match_ended(winner_id: int)


func setup_match(arena_id: String, player_count: int, wins_needed: int = 5) -> void:
	current_arena_id = arena_id
	rounds_to_win = wins_needed
	round_number = 0
	win_counts.clear()
	for i in player_count:
		win_counts[i] = 0


func begin_round() -> void:
	round_number += 1
	change_state(State.ROUND_INTRO)


func begin_fight() -> void:
	change_state(State.ROUND)
	round_started.emit(round_number)


## Records a win for player_id. Returns true if they won the match.
func record_win(player_id: int) -> bool:
	win_counts[player_id] = win_counts.get(player_id, 0) + 1
	if win_counts[player_id] >= rounds_to_win:
		change_state(State.MATCH_END)
		match_ended.emit(player_id)
		return true
	return false


func end_round(loser_ids: Array) -> void:
	change_state(State.ROUND_END)
	round_ended.emit(loser_ids)


func change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)

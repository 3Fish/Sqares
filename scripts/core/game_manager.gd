extends Node

## Central state machine for round and match flow.

enum State { MENU, ROUND_INTRO, ROUND, ROUND_END, CARD_SELECTION, MATCH_END }

var state: State = State.MENU
var round_number: int = 0
var rounds_to_win: int = 5
var current_arena_id: String = "crossroads"
var mode_id: StringName = &"ffa"
# team_id (int) -> win count. In Free-for-all every player is their own team,
# so team_id == player_id and this stays keyed per player.
var win_counts: Dictionary[int, int] = {}
# player_id (int) -> team_id (int)
var team_of: Dictionary[int, int] = {}

signal state_changed(new_state: State)
signal round_started(round_num: int)
signal round_ended(loser_ids: Array)
signal match_ended(winner_team_id: int)


## Initialises a match. `team_assignment` maps player_id -> team_id; when empty
## the match is Free-for-all (each player is their own team). Win counts are
## tracked per distinct team, so FFA naturally tracks per player.
func setup_match(arena_id: String, player_count: int, wins_needed: int = 5,
		team_assignment: Dictionary = {}, mode: StringName = &"ffa") -> void:
	current_arena_id = arena_id
	rounds_to_win = wins_needed
	mode_id = mode
	round_number = 0
	win_counts.clear()
	team_of.clear()
	if team_assignment.is_empty():
		for i in player_count:
			team_of[i] = i
	else:
		for player_id: int in team_assignment:
			team_of[player_id] = int(team_assignment[player_id])
	for player_id: int in team_of:
		win_counts[team_of[player_id]] = 0


func begin_round() -> void:
	round_number += 1
	change_state(State.ROUND_INTRO)


func begin_fight() -> void:
	change_state(State.ROUND)
	round_started.emit(round_number)


## Records a round win for the team the given player belongs to. Returns true
## if that team reached the win threshold (match over). In FFA the team is the
## player, so this is identical to the old per-player behaviour.
func record_win(player_id: int) -> bool:
	var team := team_for(player_id)
	win_counts[team] = win_counts.get(team, 0) + 1
	if win_counts[team] >= rounds_to_win:
		change_state(State.MATCH_END)
		match_ended.emit(team)
		return true
	return false


func end_round(loser_ids: Array) -> void:
	change_state(State.ROUND_END)
	round_ended.emit(loser_ids)


## Enters the between-rounds card-selection phase (#17). Kept as its own method
## (rather than an inline `change_state`) so the round-flow caller and tests
## have a named seam; it carries no card logic itself — drawing and applying
## cards is driven by `MatchDirector` / the selection UI.
func begin_card_selection() -> void:
	change_state(State.CARD_SELECTION)


func change_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(new_state)


# ---------------------------------------------------------------------------
# Team helpers (pure — covered by tests/)
# ---------------------------------------------------------------------------

## Team id for a player. Defaults to the player's own id when unassigned, so an
## un-set-up player behaves as a one-person FFA team.
func team_for(player_id: int) -> int:
	return team_of.get(player_id, player_id)


## Win count for the team a player belongs to. The HUD uses this so teammates
## share one pip count without needing to know the team layout.
func wins_for_player(player_id: int) -> int:
	return win_counts.get(team_for(player_id), 0)


## True only while a round is actively in progress: the pre-fight "Round N"
## intro (where players already position themselves today) and the fight itself.
## Every between/after-round state — the "wins the round" message (ROUND_END),
## the card-selection overlay (CARD_SELECTION), the victory screen (MATCH_END) —
## and the menu return false, so combatants freeze and the surviving player can
## no longer keep moving while losers pick cards (#70, deferred from #17).
## Static + pure so the state-to-simulation rule is unit-tested without a match.
static func is_gameplay_active(s: State) -> bool:
	return s == State.ROUND_INTRO or s == State.ROUND


## Distinct team ids that still have at least one living player, given a list of
## alive player ids and a player_id -> team_id map. The round is over when this
## drops to one team (or zero, a draw). Static + pure for easy testing.
static func teams_remaining(alive_ids: Array, team_map: Dictionary) -> Array:
	var teams: Array = []
	for player_id: int in alive_ids:
		var team: int = team_map.get(player_id, player_id)
		if not teams.has(team):
			teams.append(team)
	return teams

extends RefCounted
class_name GameMode

## Base game mode. A mode describes how players are grouped into teams and how
## the match is framed. Modes are indexed by string id in GameModeRegistry and
## mods can register their own using the same API the base game uses.
##
## The base class IS Free-for-all: every player is their own one-person team, so
## last-player-standing and per-player win tracking fall out of the generic
## team machinery with no special-casing.

var id: StringName = &"ffa"
var display_name: String = "Free-for-all"


## Returns a `player_id -> team_id` assignment for `player_count` players.
## Base (FFA): each player is their own team, so team_id == player_id.
func assign_teams(player_count: int) -> Dictionary:
	var teams: Dictionary = {}
	for i in player_count:
		teams[i] = i
	return teams


## Human-readable label for a team id, used in HUD pips and round/match
## announcements. FFA teams are single players, so the label is the player.
func team_label(team_id: int) -> String:
	return "Player %d" % (team_id + 1)

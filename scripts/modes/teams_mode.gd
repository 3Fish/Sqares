extends GameMode
class_name TeamsMode

## Splits players across a fixed number of teams (default 2), assigned
## round-robin so the teams stay as balanced as possible across the supported
## 2-4 local players:
##   4 players -> {0,2} vs {1,3}  (2v2)
##   3 players -> {0,2} vs {1}    (2v1)
##   2 players -> {0}   vs {1}    (1v1)

var team_count: int = 2


func _init(teams: int = 2) -> void:
	team_count = maxi(1, teams)
	id = &"teams"
	display_name = "Teams"


## Round-robin assignment keeps team sizes within one of each other for any
## player count, which is the fairest split without authoring per-count tables.
func assign_teams(player_count: int) -> Dictionary:
	var teams: Dictionary = {}
	for i in player_count:
		teams[i] = i % team_count
	return teams


func team_label(team_id: int) -> String:
	return "Team %d" % (team_id + 1)

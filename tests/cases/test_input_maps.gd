extends TestCase

## p1..p4 must each have the full action set so every local player can be
## driven from a shared keyboard/gamepad setup (#25).

const PLAYER_ACTIONS := [
	"move_left", "move_right", "jump", "shoot",
	"aim_left", "aim_right", "aim_up", "aim_down",
]


func _test_all_players_have_full_action_set() -> void:
	for player in range(1, 5):
		for action in PLAYER_ACTIONS:
			var action_name := "p%d_%s" % [player, action]
			assert_true(InputMap.has_action(action_name), "input action exists: %s" % action_name)

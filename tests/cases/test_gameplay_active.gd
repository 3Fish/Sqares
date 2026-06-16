extends TestCase

## GameManager.is_gameplay_active gates combatant simulation: players simulate
## only while a round is in progress (the "Round N" intro + the fight) and freeze
## in every between/after-round state, so the surviving winner can no longer keep
## moving during the "wins the round" message or under the card-selection overlay
## (#70, deferred from #17).
##
## is_gameplay_active is a pure static helper and is the substance of this change;
## it is tested exhaustively in isolation. One integration case confirms that a
## player in a frozen state short-circuits its physics step (no movement) — the
## same "pure helper is the substance, one live case" split used elsewhere.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")


func after_each() -> void:
	# This suite pokes the shared GameManager.state directly; leave it where the
	# harness expects it so later cases are not affected.
	GameManager.state = GameManager.State.MENU


# --- is_gameplay_active (pure mapping, the core of this change) -------------

func _test_round_intro_is_active() -> void:
	assert_true(GameManager.is_gameplay_active(GameManager.State.ROUND_INTRO),
		"combatants simulate during the round intro (pre-fight positioning, unchanged)")


func _test_round_is_active() -> void:
	assert_true(GameManager.is_gameplay_active(GameManager.State.ROUND),
		"combatants simulate during the fight")


func _test_round_end_is_frozen() -> void:
	assert_false(GameManager.is_gameplay_active(GameManager.State.ROUND_END),
		"combatants freeze during the 'wins the round' message")


func _test_card_selection_is_frozen() -> void:
	assert_false(GameManager.is_gameplay_active(GameManager.State.CARD_SELECTION),
		"combatants freeze under the card-selection overlay")


func _test_match_end_is_frozen() -> void:
	assert_false(GameManager.is_gameplay_active(GameManager.State.MATCH_END),
		"combatants freeze on the victory screen")


func _test_menu_is_frozen() -> void:
	assert_false(GameManager.is_gameplay_active(GameManager.State.MENU),
		"no live combatants in the menu")


func _test_exactly_the_round_states_are_active() -> void:
	# Exactly the intro + fight states drive simulation; everything else freezes.
	var active: int = 0
	for s in [GameManager.State.MENU, GameManager.State.ROUND_INTRO,
			GameManager.State.ROUND, GameManager.State.ROUND_END,
			GameManager.State.CARD_SELECTION, GameManager.State.MATCH_END]:
		if GameManager.is_gameplay_active(s):
			active += 1
	assert_eq(active, 2, "only the round intro and the fight are gameplay-active")


# --- live freeze (one integration case) ------------------------------------

func _test_player_does_not_move_in_a_frozen_state() -> void:
	# A LOCAL player whose physics step runs while the match is in a frozen state
	# must short-circuit before touching velocity / move_and_slide, so it holds
	# position. (Detached node, mirroring test_player_knockback — _physics_process
	# returns at the state gate, never reaching move_and_slide.)
	var p: Player = PLAYER_SCENE.instantiate()
	p.velocity = Vector2(200.0, 0.0)
	var before: Vector2 = p.global_position
	GameManager.state = GameManager.State.CARD_SELECTION
	p._physics_process(0.016)
	assert_true(p.global_position.is_equal_approx(before),
		"a player in CARD_SELECTION does not move")
	p.free()

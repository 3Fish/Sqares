extends Node
class_name MatchDirector

## Orchestrates round lifecycle: spawn → fight → end → next round / match end.
## Lives inside scenes/match.tscn; talks to GameManager for win tracking.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

@export var arena_id: String = "crossroads"
@export var player_count: int = 2
@export var wins_needed: int = 5

@onready var _arena_container: Node2D  = $"../ArenaContainer"
@onready var _players_container: Node2D = $"../PlayersContainer"
@onready var _hud: HUD                 = $"../HUD"

var _arena: Arena = null
var _players: Array[Player] = []
var _alive_ids: Array[int] = []
var _match_over: bool = false
var _round_ending: bool = false

var _player_scene: PackedScene


func _ready() -> void:
	_player_scene = load(PLAYER_SCENE)
	GameManager.setup_match(arena_id, player_count, wins_needed)
	_start_round()


func _start_round() -> void:
	_clear()
	GameManager.begin_round()
	_spawn_arena()
	_spawn_players()
	_hud.show_center("Round %d" % GameManager.round_number)
	await get_tree().create_timer(1.5).timeout
	if _match_over or _round_ending:
		return
	GameManager.begin_fight()
	_hud.hide_center()
	_hud.set_round(GameManager.round_number)


func _clear() -> void:
	_round_ending = false
	if is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	for p in _players:
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	_alive_ids.clear()


func _spawn_arena() -> void:
	var scene := LevelRegistry.get_level(arena_id)
	if not scene:
		push_error("MatchDirector: arena '%s' not registered" % arena_id)
		return
	_arena = scene.instantiate()
	_arena_container.add_child(_arena)


func _spawn_players() -> void:
	var spawn_points: Array[Vector2] = _arena.get_spawn_points() if _arena else []
	for i in player_count:
		var p: Player = _player_scene.instantiate()
		_players_container.add_child(p)
		_players.append(p)
		_alive_ids.append(i)
		if i < spawn_points.size():
			p.global_position = spawn_points[i]
		p.player_died.connect(_on_player_died.bind(i))
		_hud.register_player(i, p)


func _on_player_died(_player: Player, _killer: Node, player_id: int) -> void:
	_alive_ids.erase(player_id)
	if _alive_ids.size() <= 1 and not _round_ending:
		_end_round()


func _end_round() -> void:
	_round_ending = true
	var loser_ids: Array = []
	var winner_id := -1
	for i in _players.size():
		if _players[i].health.is_dead():
			loser_ids.append(i)
		else:
			winner_id = i

	GameManager.end_round(loser_ids)

	var match_over := false
	if winner_id >= 0:
		match_over = GameManager.record_win(winner_id)
		_hud.update_wins()

	if match_over:
		_match_over = true
		_hud.show_center(
			"Player %d wins the match!\n[any key to replay]" % (winner_id + 1)
		)
		return

	var msg := "Player %d wins the round!" % (winner_id + 1) if winner_id >= 0 else "Draw!"
	_hud.show_center(msg)
	await get_tree().create_timer(2.5).timeout
	_start_round()


func _unhandled_input(event: InputEvent) -> void:
	if not _match_over:
		return
	if event.is_pressed() and not event.is_echo():
		_match_over = false
		GameManager.setup_match(arena_id, player_count, wins_needed)
		_start_round()

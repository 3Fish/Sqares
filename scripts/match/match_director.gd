extends Node
class_name MatchDirector

## Orchestrates round lifecycle: spawn → fight → end → next round / match end.
## Lives inside scenes/match.tscn; talks to GameManager for win tracking.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

## Supported range for local couch play. Input maps exist for p1..p4 and the
## HUD lays out up to four readouts, so matches are clamped to this range.
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
## Horizontal gap used to fan players out when an arena ships fewer spawn
## points than players, so nobody stacks on top of another at the origin.
const FALLBACK_SPACING := 80.0

@export var arena_id: String = "crossroads"
@export var player_count: int = 2
@export var wins_needed: int = 5
## Game mode id, resolved against GameModeRegistry. "ffa" (default) is
## Free-for-all; "teams" splits players into balanced teams. A future
## match-setup screen will let players pick this; for now it is configurable
## here, mirroring how `player_count` is exposed.
@export var game_mode: String = "ffa"

@onready var _arena_container: Node2D  = $"../ArenaContainer"
@onready var _players_container: Node2D = $"../PlayersContainer"
@onready var _hud: HUD                 = $"../HUD"

var _arena: Arena = null
var _players: Array[Player] = []
var _alive_ids: Array[int] = []
var _match_over: bool = false
var _round_ending: bool = false
var _mode: GameMode = null


func _ready() -> void:
	player_count = clamp_player_count(player_count)
	_mode = resolve_mode(game_mode)
	_begin_match()
	_start_round.call_deferred()


## Builds the team assignment from the active mode and hands it to GameManager.
func _begin_match() -> void:
	var teams := _mode.assign_teams(player_count)
	GameManager.setup_match(arena_id, player_count, wins_needed, teams, _mode.id)


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
	var positions := resolve_spawn_positions(player_count, spawn_points)
	for i in player_count:
		var p: Player = PLAYER_SCENE.instantiate()
		p.player_id = i
		_players_container.add_child(p)
		_players.append(p)
		_alive_ids.append(i)
		p.global_position = positions[i]
		p.player_died.connect(_on_player_died.bind(i))
		_hud.register_player(i, p)


func _on_player_died(_player: Player, _killer: Node, player_id: int) -> void:
	_alive_ids.erase(player_id)
	# The round ends once a single team (or none) has survivors. In FFA each
	# player is their own team, so this reduces to "one player left".
	if GameManager.teams_remaining(_alive_ids, GameManager.team_of).size() <= 1 and not _round_ending:
		_end_round()


func _end_round() -> void:
	_round_ending = true
	var loser_ids: Array = []
	var winner_id := -1
	for i in _players.size():
		if _players[i].health.is_dead():
			loser_ids.append(i)
		else:
			winner_id = i  # any survivor; their team takes the round

	GameManager.end_round(loser_ids)

	var match_over := false
	var winning_team := -1
	if winner_id >= 0:
		winning_team = GameManager.team_for(winner_id)
		match_over = GameManager.record_win(winner_id)
		_hud.update_wins()

	if match_over:
		_match_over = true
		_hud.show_center(
			"%s wins the match!\n[any key to replay]" % _mode.team_label(winning_team)
		)
		return

	var msg := "%s wins the round!" % _mode.team_label(winning_team) if winner_id >= 0 else "Draw!"
	_hud.show_center(msg)
	await get_tree().create_timer(2.5).timeout
	_start_round()


func _unhandled_input(event: InputEvent) -> void:
	if not _match_over:
		return
	if event.is_pressed() and not event.is_echo():
		_match_over = false
		_begin_match()
		_start_round()


# ---------------------------------------------------------------------------
# Pure helpers (no scene-tree dependencies — covered by tests/)
# ---------------------------------------------------------------------------

## Clamps a requested player count into the supported local-play range.
static func clamp_player_count(count: int) -> int:
	return clampi(count, MIN_PLAYERS, MAX_PLAYERS)


## Resolves a mode id to a GameMode instance via GameModeRegistry, falling back
## to Free-for-all when the id is unknown or the registry is empty (e.g. before
## mods have loaded, or in the headless test harness).
static func resolve_mode(mode_id: String) -> GameMode:
	var script: GDScript = GameModeRegistry.get_mode(mode_id)
	if script:
		var mode: Object = script.new()
		if mode is GameMode:
			return mode
	return GameMode.new()


## Returns exactly `count` spawn positions. Available spawn points are used
## first; when an arena ships fewer spawns than players, the remainder reuse
## existing spawns nudged horizontally so players never overlap. With no spawn
## points at all, players are fanned out symmetrically around the origin.
static func resolve_spawn_positions(count: int, spawn_points: Array[Vector2]) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions
	if spawn_points.is_empty():
		for i in count:
			positions.append(Vector2((float(i) - float(count - 1) * 0.5) * FALLBACK_SPACING, 0.0))
		return positions
	for i in count:
		var base: Vector2 = spawn_points[i % spawn_points.size()]
		var reuse: int = i / spawn_points.size()  # 0 on first pass, grows when reused
		# Alternate nudge direction so reused spawns spread out rather than drift.
		var dir := 1.0 if i % 2 == 0 else -1.0
		positions.append(base + Vector2(FALLBACK_SPACING * reuse * dir, 0.0))
	return positions

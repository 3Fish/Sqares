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

## One-shot arena hand-off for the editor's playtest (#36). When the arena editor
## launches a playtest it registers the edited arena and sets this; the next
## MatchDirector to start consumes it (overriding the `arena_id` export) and
## clears it, so a normal "Play" from the menu is unaffected. A static var keeps
## the hand-off decoupled from node paths and scene arguments.
static var pending_arena_id: String = ""

@export var arena_id: String = "crossroads"
@export var player_count: int = 2
@export var wins_needed: int = 5
## Cards offered to each losing player between rounds (#17).
@export var cards_per_draw: int = CardDraw.DEFAULT_DRAW_COUNT
## Game mode id, resolved against GameModeRegistry. "ffa" (default) is
## Free-for-all; "teams" splits players into balanced teams. A future
## match-setup screen will let players pick this; for now it is configurable
## here, mirroring how `player_count` is exposed.
@export var game_mode: String = "ffa"
## Whether teammates can damage each other (#62). On by default — and moot in
## Free-for-all, where every distinct player is an enemy. Turning it off in a
## Teams match makes friendly shots (including the shooter's own bounce-back)
## consume harmlessly instead of dealing damage. Exposed here as an export until
## the deferred match-setup screen surfaces it, mirroring `game_mode`.
@export var friendly_fire: bool = true

@onready var _arena_container: Node2D  = $"../ArenaContainer"
@onready var _players_container: Node2D = $"../PlayersContainer"
@onready var _hud: HUD                 = $"../HUD"

var _arena: Arena = null
var _players: Array[Player] = []
var _alive_ids: Array[int] = []
var _match_over: bool = false
var _round_ending: bool = false
var _mode: GameMode = null
## True when this match's teams were extrapolated from the per-player colours (#134,
## local Teams play). Drives the colour-named round/match announcement. Set every
## time the team assignment is (re)built in `_begin_match`.
var _colors_drive_teams: bool = false

## Card effects accumulated per player slot over the match (#17). Players are
## re-instantiated each round, so a slot's picked effects are re-applied to its
## fresh player node at spawn — this is what makes picks persist (the rogue-like
## accumulation intent, #43). player_id -> Array of effect objects.
var _picked_effects: Dictionary = {}

## Client-side card-pick screen shown between rounds when this peer's square lost
## (#82). Tracked so it can be torn down on pick / next round start.
var _card_ui: CardSelectionUI = null


func _ready() -> void:
	# Adopt a staged match-setup configuration, if the setup screen left one (#26).
	# One-shot: a direct load of match.tscn (the editor playtest #36, or a test)
	# leaves nothing pending and keeps the @export defaults below.
	if MatchConfig.consume():
		game_mode = MatchConfig.game_mode
		player_count = MatchConfig.player_count
		wins_needed = MatchConfig.wins_needed
		arena_id = MatchConfig.arena_id
		friendly_fire = MatchConfig.friendly_fire
	# Consume a one-shot playtest arena, if the editor handed one over (#36). The
	# editor loads match.tscn directly (no setup config), and even if both were
	# set this keeps the playtest arena's precedence.
	arena_id = resolve_arena_id(pending_arena_id, arena_id)
	pending_arena_id = ""
	_mode = resolve_mode(game_mode)
	if NetworkManager.is_client():
		# A networked client mirrors the host's round flow via reliable match
		# events (#27) instead of driving its own lifecycle.
		_client_setup()
		return
	if NetworkManager.is_host():
		# Online, the roster is the player list: one slot per connected peer.
		player_count = NetworkManager.peer_count()
	player_count = clamp_player_count(player_count)
	_begin_match()
	_start_round.call_deferred()


## Builds the team assignment from the active mode and hands it to GameManager.
func _begin_match() -> void:
	var teams := _team_assignment()
	GameManager.setup_match(arena_id, player_count, wins_needed, teams, _mode.id, friendly_fire)
	if NetworkManager.is_host():
		# Agree the match RNG up front so synced draws/rolls (#24) derive the
		# same streams on every peer — the seed transport #64/#66 parked here.
		NetReplicator.broadcast_seed(RNGService.seed_match())


## The `player_id -> team_id` map for this match. In local Teams play with colours
## staged from the setup screen, the teams are extrapolated from the per-player
## colours (#134 / #132 A4): same colour -> same team. Every other case keeps the
## mode's own assignment so behaviour is unchanged — FFA (each player their own
## team, #134 A4), any networked match (a peer's chosen colour isn't replicated
## yet, #66/#82), and a direct/editor-playtest load (no colours staged) all fall
## back to `_mode.assign_teams`.
func _team_assignment() -> Dictionary:
	_colors_drive_teams = _mode.id == &"teams" \
		and not NetworkManager.is_networked() \
		and not MatchConfig.player_colors.is_empty()
	if _colors_drive_teams:
		return MatchConfig.teams_from_colors(MatchConfig.player_colors, player_count)
	return _mode.assign_teams(player_count)


## Display label for a team in round/match announcements. A colour-derived Teams
## match names the team by its colour ("Team Babyblue wins!", #134 / #132 A4) since
## the team id is the palette colour index; every other mode keeps its own label
## (FFA: "Player N"; round-robin Teams: "Team N").
func _team_label(team_id: int) -> String:
	if _colors_drive_teams:
		return "Team %s" % PlayerPalette.name_at(team_id)
	return _mode.team_label(team_id)


func _start_round() -> void:
	_clear()
	GameManager.begin_round()
	_spawn_arena()
	_spawn_players()
	_broadcast("round_start", {
		"round": GameManager.round_number,
		"arena_id": arena_id,
		"player_count": player_count,
	})
	_hud.show_center("Round %d" % GameManager.round_number)
	await get_tree().create_timer(1.5).timeout
	if _match_over or _round_ending:
		return
	GameManager.begin_fight()
	_broadcast("fight")
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
	var networked := NetworkManager.is_networked()
	var local_slot := NetworkManager.local_slot()
	if networked:
		NetReplicator.clear_players()
	for i in player_count:
		var p: Player = PLAYER_SCENE.instantiate()
		p.player_id = i
		p.net_role = resolve_net_role(networked, NetworkManager.is_host(), i, local_slot)
		# A networked client's own square answers to this machine's primary
		# (p1) bindings, whatever its slot; everything else keeps slot bindings.
		p.input_id = 0 if networked and i == local_slot else i
		_players_container.add_child(p)
		# Apply the per-player name + colour chosen in setup (#132). Falls back to
		# the palette defaults when nothing was staged (editor playtest, a client,
		# or a direct match load), so every spawn gets a sane, distinct appearance.
		p.apply_appearance(
			PlayerPalette.color_at(MatchConfig.color_index_for(MatchConfig.player_colors, i)),
			MatchConfig.name_for(MatchConfig.player_names, i))
		_players.append(p)
		_alive_ids.append(i)
		p.global_position = positions[i]
		if not NetworkManager.is_client():
			# Round-end detection and card effects are authority-side; clients
			# learn about deaths via the host's reliable events instead.
			p.player_died.connect(_on_player_died.bind(i))
			# Re-attach this slot's accumulated card effects to the fresh node so
			# picks carry across rounds (the node, and thus its stats, is new).
			for effect in _picked_effects.get(i, []):
				EffectEngine.apply_effect(p, effect)
		_hud.register_player(i, p)
		if networked:
			NetReplicator.register_player(p)


func _on_player_died(_player: Player, _killer: Node, player_id: int) -> void:
	_alive_ids.erase(player_id)
	_broadcast("player_died", {"player_id": player_id})
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
	_broadcast("round_end", {"winner_id": winner_id, "loser_ids": loser_ids})

	var match_over := false
	var winning_team := -1
	if winner_id >= 0:
		winning_team = GameManager.team_for(winner_id)
		match_over = GameManager.record_win(winner_id)
		_hud.update_wins()

	if match_over:
		_match_over = true
		_broadcast("match_end", {"winner_id": winner_id})
		_hud.show_center(
			"%s wins the match!\n[any key to replay]" % _team_label(winning_team)
		)
		return

	var msg := "%s wins the round!" % _team_label(winning_team) if winner_id >= 0 else "Draw!"
	_hud.show_center(msg)
	await get_tree().create_timer(2.5).timeout
	if _match_over:
		return
	await _run_card_selection(loser_ids)
	if _match_over:
		return
	_start_round()


## Between-rounds phase: each losing player is offered `cards_per_draw` cards
## and picks one (#17). Returns immediately (no UI) when there is nothing to
## pick — no losers, or no cards registered — so the round flow never stalls.
func _run_card_selection(loser_ids: Array) -> void:
	var cards: Array = CardRegistry.get_all_cards()
	if loser_ids.is_empty() or cards.is_empty():
		return
	GameManager.begin_card_selection()
	_hud.hide_center()

	# The host (and offline play) draws every loser's hand here so draws stay on
	# the synced, per-round seeded RNG stream (#24). Online the host broadcasts
	# these hands rather than having clients re-draw, which keeps picks robust
	# against any per-peer RNG-stream divergence (#82).
	var hands: Dictionary = {}
	for pid in loser_ids:
		hands[pid] = CardDraw.weighted_draw(cards, cards_per_draw, RNGService.generator())

	if NetworkManager.is_networked():
		await _run_networked_card_selection(loser_ids, hands)
		return

	var ui := CardSelectionUI.new()
	add_child(ui)
	ui.begin(hands)
	var picks: Dictionary = await ui.selection_complete
	_record_picks(picks)
	ui.queue_free()


## Host-side online pick phase (#82): broadcasts each loser its hand, picks the
## host's own square locally (if it lost), collects remote losers' picks over the
## reliable client→host channel, and returns once every loser has chosen — which
## gates the next `round_start`. Only the host reaches here (`_end_round` is
## authority/offline-only); clients mirror via `_client_card_selection`.
func _run_networked_card_selection(loser_ids: Array, hands: Dictionary) -> void:
	var serialized := CardPickSync.serialize_hands(hands)
	_broadcast("card_selection", {"hands": serialized})

	var picks: Dictionary = {}  # slot -> Card (or null for an empty hand)
	var local_slot := NetworkManager.local_slot()

	var on_remote_pick := func(slot: int, card_id: String) -> void:
		if not loser_ids.has(slot) or picks.has(slot):
			return
		if not CardPickSync.is_valid_pick(slot, card_id, serialized):
			return
		picks[slot] = CardRegistry.get_card(card_id) if card_id != "" else null
	NetReplicator.card_pick_received.connect(on_remote_pick)

	# If the host's own square lost, it picks on this screen (driven by p1).
	var host_ui: CardSelectionUI = null
	if loser_ids.has(local_slot) and hands.has(local_slot):
		host_ui = CardSelectionUI.new()
		add_child(host_ui)
		host_ui.begin({local_slot: hands[local_slot]}, {local_slot: 0})
		host_ui.selection_complete.connect(func(p: Dictionary) -> void:
			if p.has(local_slot) and not picks.has(local_slot):
				picks[local_slot] = p[local_slot])

	# Gate the next round on every loser's pick being in (no timeout — the same
	# indefinite wait as local play; a dropped peer is #28's resilience scope).
	while not CardPickSync.all_picked(loser_ids, picks):
		await get_tree().process_frame
		if _match_over:
			break

	if NetReplicator.card_pick_received.is_connected(on_remote_pick):
		NetReplicator.card_pick_received.disconnect(on_remote_pick)
	if is_instance_valid(host_ui):
		host_ui.queue_free()
	_record_picks(picks)


## Stores each pick's effect against its player slot; it is (re-)applied to the
## live player node at the next spawn. Metadata-only cards (no effect) are still
## a valid pick — they simply contribute nothing to apply.
func _record_picks(picks: Dictionary) -> void:
	for pid in picks:
		var card = picks[pid]
		if card == null or card.effect == null:
			continue
		var list: Array = _picked_effects.get(pid, [])
		list.append(card.effect)
		_picked_effects[pid] = list


func _unhandled_input(event: InputEvent) -> void:
	if not _match_over or NetworkManager.is_client():
		return  # online replay is host-driven; clients follow "match_restart"
	if event.is_pressed() and not event.is_echo():
		_match_over = false
		# Fresh match: drop accumulated picks and any effects still attached to
		# the previous match's (now-freed) player nodes.
		_picked_effects.clear()
		EffectEngine.clear()
		_begin_match()
		_broadcast("match_restart")
		_start_round()


# ---------------------------------------------------------------------------
# Networked round flow (#27)
# ---------------------------------------------------------------------------

## Host-side: mirrors a round-flow step to all clients (no-op offline).
func _broadcast(kind: String, data: Dictionary = {}) -> void:
	if NetworkManager.is_host():
		NetReplicator.broadcast_match_event(kind, data)


## Client-side: configure the local mirror and follow the host's events.
func _client_setup() -> void:
	player_count = clamp_player_count(NetworkManager.peer_count())
	_begin_match()
	NetReplicator.match_event.connect(_on_match_event)


func _on_match_event(kind: String, data: Dictionary) -> void:
	match kind:
		"round_start":
			_client_round_start(data)
		"fight":
			_client_fight()
		"round_end":
			_client_round_end(data)
		"match_end":
			_client_match_end(data)
		"match_restart":
			_client_match_restart()
		"player_died":
			_client_player_died(data)
		"card_selection":
			_client_card_selection(data)


func _client_round_start(data: Dictionary) -> void:
	# Tear down any lingering pick screen before the next round renders.
	if is_instance_valid(_card_ui):
		_card_ui.queue_free()
		_card_ui = null
	_clear()
	arena_id = str(data.get("arena_id", arena_id))
	player_count = clamp_player_count(int(data.get("player_count", player_count)))
	# Adopt the host's round number outright so a mirrored client can never
	# drift off by one.
	GameManager.round_number = int(data.get("round", GameManager.round_number + 1)) - 1
	GameManager.begin_round()
	_spawn_arena()
	_spawn_players()
	_hud.show_center("Round %d" % GameManager.round_number)


func _client_fight() -> void:
	GameManager.begin_fight()
	_hud.hide_center()
	_hud.set_round(GameManager.round_number)


func _client_round_end(data: Dictionary) -> void:
	_round_ending = true
	var loser_ids: Array = data.get("loser_ids", []) if data.get("loser_ids", []) is Array else []
	GameManager.end_round(loser_ids)
	var winner_id := int(data.get("winner_id", -1))
	var winning_team := -1
	if winner_id >= 0:
		winning_team = GameManager.team_for(winner_id)
		# Same deterministic tally as the host, so the HUD pips agree.
		if GameManager.record_win(winner_id):
			_match_over = true
		_hud.update_wins()
	var msg := "%s wins the round!" % _team_label(winning_team) if winner_id >= 0 else "Draw!"
	_hud.show_center(msg)


func _client_match_end(data: Dictionary) -> void:
	_match_over = true
	var winner_id := int(data.get("winner_id", -1))
	var team := GameManager.team_for(winner_id) if winner_id >= 0 else -1
	_hud.show_center("%s wins the match!\n[host decides on a replay]" % _team_label(team))


func _client_match_restart() -> void:
	_match_over = false
	EffectEngine.clear()
	_begin_match()


func _client_player_died(data: Dictionary) -> void:
	var dead_id := int(data.get("player_id", -1))
	for p in _players:
		if is_instance_valid(p) and p.player_id == dead_id:
			p.health.kill()
			return


## Client-side online pick phase (#82): shows the pick screen only when this
## peer's own square lost, driven by this machine's primary (p1) bindings, and
## replicates the chosen card back to the host. A non-losing peer just waits for
## the host's next `round_start`.
func _client_card_selection(data: Dictionary) -> void:
	if is_instance_valid(_card_ui):
		_card_ui.queue_free()
		_card_ui = null
	var raw = data.get("hands", {})
	var serialized: Dictionary = raw if raw is Dictionary else {}
	var my_slot := NetworkManager.local_slot()
	if not serialized.has(my_slot):
		return  # this peer's square didn't lose — nothing to pick
	GameManager.begin_card_selection()
	_hud.hide_center()
	var hand := _cards_from_ids(serialized[my_slot])
	_card_ui = CardSelectionUI.new()
	add_child(_card_ui)
	_card_ui.begin({my_slot: hand}, {my_slot: 0})
	var picks: Dictionary = await _card_ui.selection_complete
	var card = picks.get(my_slot, null)
	NetReplicator.send_card_pick(my_slot, String(card.id) if card != null else "")
	if is_instance_valid(_card_ui):
		_card_ui.queue_free()
		_card_ui = null


## Resolves a list of broadcast card ids back to Card instances via CardRegistry,
## dropping any id not registered on this peer.
func _cards_from_ids(ids) -> Array:
	var hand: Array = []
	if ids is Array:
		for id in ids:
			var card := CardRegistry.get_card(String(id))
			if card != null:
				hand.append(card)
	return hand


# ---------------------------------------------------------------------------
# Pure helpers (no scene-tree dependencies — covered by tests/)
# ---------------------------------------------------------------------------

## Clamps a requested player count into the supported local-play range.
static func clamp_player_count(count: int) -> int:
	return clampi(count, MIN_PLAYERS, MAX_PLAYERS)


## Resolves the arena id a fresh match should use: the one-shot `pending` id
## handed over by the editor's playtest takes precedence, else the configured
## `fallback` (the `arena_id` export). Pure so the hand-off precedence is
## unit-tested without booting a match.
static func resolve_arena_id(pending: String, fallback: String) -> String:
	return pending if not pending.strip_edges().is_empty() else fallback


## Simulation role for the player in `slot` (#27): offline matches are all
## LOCAL; on the host its own slot is LOCAL and every remote slot is SIMULATED
## (driven by replicated inputs); on a client its own slot is the PREDICTED
## player and every other slot is a snapshot-driven PUPPET. Pure so the
## control-assignment matrix is unit-tested without booting a match.
static func resolve_net_role(networked: bool, is_host: bool, slot: int, local_slot: int) -> Player.NetRole:
	if not networked:
		return Player.NetRole.LOCAL
	if slot == local_slot:
		return Player.NetRole.LOCAL if is_host else Player.NetRole.PREDICTED
	return Player.NetRole.SIMULATED if is_host else Player.NetRole.PUPPET


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

extends Node

## Combat-state replication + input reconciliation transport (#27).
##
## The manual RPC fan-out layer on top of the netcode foundation (#23):
## - Clients sample input every physics tick, apply it immediately to their own
##   (predicted) player, and stream the unacked input window to the host over
##   unreliable RPC.
## - The host simulates all players from received inputs and broadcasts one
##   authoritative NetSnapshot per net tick (all players, snapshot tick number,
##   per-player last-processed input seq) over unreliable RPC. Clients
##   reconcile their own player against it and apply it directly to puppets —
##   no smoothing; interpolation is #28's scope.
## - One-shot events that must not be lost — projectile spawns/rejections,
##   deaths, round transitions, the match RNG seed, the lobby roster mirror —
##   go over reliable RPCs.
## - Projectiles are shooter-predicted: the client spawns a visual-only
##   instance immediately and sends a fire intent carrying a client-generated
##   id; the host validates, fires the authoritative projectile, and
##   replicates it back echoing the id so the shooter adopts (or, on
##   rejection, frees) its predicted instance. All hit detection and damage
##   are host-only.
##
## MultiplayerSynchronizer is deliberately not used (decision on #27). All
## RPCs live on this autoload so every peer shares a stable node path.
## Decision-bearing helpers are pure/static for the headless harness.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

## Physics ticks per snapshot broadcast. 2 ticks at the 60 Hz physics rate is a
## 30 Hz net tick — the top of the 20–30 Hz range decided on #27.
const NET_TICK_INTERVAL := 2
## Most unprocessed inputs the host queues per player; beyond it the oldest are
## dropped so a stalling client can't accumulate unbounded simulation debt.
const MAX_INPUT_BACKLOG := 8
## How many unacked inputs a client re-sends per tick, so the unreliable input
## stream survives packet loss without a resend protocol.
const MAX_REDUNDANT_INPUTS := 8

## Reliable host→client match-flow events ("round_start", "fight",
## "round_end", "match_end", "match_restart", "player_died"), consumed by the
## client MatchDirector to mirror the host's round lifecycle.
signal match_event(kind: String, data: Dictionary)

## Host physics tick counter driving the snapshot cadence.
var _tick: int = 0
## Live player nodes in the current round: player_id -> Player.
var _players: Dictionary = {}
## Host: received-but-unprocessed inputs per player: player_id -> Array[NetPlayerInput].
var _input_queues: Dictionary = {}
## Host: last input seq simulated per player (echoed in snapshots as the ack).
var _last_processed: Dictionary = {}
## Client: predicted projectiles awaiting host confirmation: net_id -> Projectile.
var _predicted_projectiles: Dictionary = {}
## Client: counter feeding client-generated projectile ids.
var _projectile_counter: int = 0
## Newest snapshot applied on this client (stale packets are dropped by tick).
var latest_snapshot: NetSnapshot = null


func _ready() -> void:
	# Host mirrors the roster to clients whenever it changes, so every peer
	# knows the full slot assignment (the client-side lobby mirror #66 parked
	# on this issue).
	if not NetworkManager.lobby_changed.is_connected(_on_lobby_changed):
		NetworkManager.lobby_changed.connect(_on_lobby_changed)


func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_host() or _players.is_empty():
		return
	_tick += 1
	if _tick % NET_TICK_INTERVAL != 0:
		return
	var live: Array = []
	for player in _players.values():
		if is_instance_valid(player):
			live.append(player)
	if live.is_empty():
		return
	var snap := NetSnapshot.capture(live, _tick, _last_processed)
	_client_receive_snapshot.rpc(snap.to_dict())


# ---------------------------------------------------------------------------
# Player registry (fed by MatchDirector each round)
# ---------------------------------------------------------------------------

func register_player(player: Node) -> void:
	_players[int(player.get("player_id"))] = player


## Drops all round-scoped state (player nodes, input queues, predicted
## projectiles). Called when a round re-spawns players and on teardown; the
## input acks survive a round so late packets from the old round stay stale.
func clear_players() -> void:
	_players.clear()
	_input_queues.clear()
	for net_id in _predicted_projectiles:
		var proj = _predicted_projectiles[net_id]
		if is_instance_valid(proj):
			proj.queue_free()
	_predicted_projectiles.clear()


## Full reset to the offline state (e.g. after a disconnect).
func reset() -> void:
	clear_players()
	_last_processed.clear()
	_tick = 0
	_projectile_counter = 0
	latest_snapshot = null


# ---------------------------------------------------------------------------
# Input stream: client -> host (unreliable, redundant window)
# ---------------------------------------------------------------------------

## Sends the calling (predicted) player's unacked input window to the host.
## Duck-typed (`prediction` / `player_id`) so a test stub stands in for Player.
func send_player_inputs(player) -> void:
	if not NetworkManager.is_client():
		return
	var payloads: Array = []
	for input in player.prediction.pending_inputs(MAX_REDUNDANT_INPUTS):
		payloads.append(input.to_dict())
	if not payloads.is_empty():
		_host_receive_inputs.rpc_id(NetworkManager.HOST_PEER_ID, player.get("player_id"), payloads)


@rpc("any_peer", "call_remote", "unreliable")
func _host_receive_inputs(player_id: int, payloads: Array) -> void:
	if not NetworkManager.is_host():
		return
	# Trust the lobby, not the payload: a peer may only drive its own slot.
	var slot := NetworkManager.slot_of(multiplayer.get_remote_sender_id())
	if slot < 0 or slot != int(player_id):
		return
	queue_inputs(slot, payloads)


## Folds a redundant input window into a player's pending queue. Direct seam
## for the RPC handler so the queue semantics are unit-testable.
func queue_inputs(player_id: int, payloads: Array) -> void:
	var queue: Array = _input_queues.get(player_id, [])
	var last := int(_last_processed.get(player_id, 0))
	for payload in payloads:
		if payload is Dictionary:
			queue = merge_input(queue, NetPlayerInput.from_dict(payload), last, MAX_INPUT_BACKLOG)
	_input_queues[player_id] = queue


## Pops the next unsimulated input for a host-simulated player and records its
## seq as processed (the ack echoed in snapshots). Null when none is pending —
## the caller holds the previous stick state for that tick.
func pull_input(player_id: int) -> NetPlayerInput:
	var queue: Array = _input_queues.get(player_id, [])
	if queue.is_empty():
		return null
	var input: NetPlayerInput = queue.pop_front()
	_last_processed[player_id] = input.seq
	return input


## Appends `input` to `queue` if it is new (not yet processed, not already
## queued), trimming the oldest entries beyond `max_backlog`. Inputs arrive in
## redundant overlapping windows, so duplicates and stale seqs are the norm,
## not an error. Pure — returns the updated queue.
static func merge_input(queue: Array, input: NetPlayerInput, last_processed: int, max_backlog: int) -> Array:
	if input == null or input.seq <= last_processed:
		return queue
	if not queue.is_empty() and input.seq <= int(queue.back().seq):
		return queue
	queue.append(input)
	while queue.size() > max_backlog:
		queue.pop_front()
	return queue


# ---------------------------------------------------------------------------
# Snapshots: host -> clients (unreliable, newest wins)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable")
func _client_receive_snapshot(data: Dictionary) -> void:
	var snap := NetSnapshot.from_dict(data)
	if latest_snapshot != null and snap.tick <= latest_snapshot.tick:
		return  # out-of-order packet; a newer snapshot already applied
	latest_snapshot = snap
	for state in snap.players:
		var player = _players.get(state.player_id)
		if player == null or not is_instance_valid(player):
			continue
		if player.net_role == Player.NetRole.PREDICTED:
			player.reconcile(state)
		else:
			# PUPPET: adopt authoritative health immediately, but buffer the
			# transform so the physics step can render a smoothed, slightly
			# delayed point between snapshots instead of stepping at the net
			# tick rate (#28). Stamped with local receive time so interpolation
			# needs no host-clock sync.
			player.health.current_hp = state.health
			player.interpolation.push(net_time_seconds(), state.position, state.velocity)


# ---------------------------------------------------------------------------
# Projectiles: shooter-side prediction, host-authoritative resolution
# ---------------------------------------------------------------------------

## Registers a freshly fired predicted projectile and sends the fire intent to
## the host (reliable). The client-generated id lets the host's confirmation
## or rejection find the predicted instance again.
func send_fire_intent(player: Node, predicted: Node, direction: Vector2) -> void:
	if not NetworkManager.is_client():
		return
	_projectile_counter += 1
	var net_id := make_projectile_id(multiplayer.get_unique_id(), _projectile_counter)
	predicted.set("net_id", net_id)
	_predicted_projectiles[net_id] = predicted
	_host_receive_fire_intent.rpc_id(NetworkManager.HOST_PEER_ID, {
		"net_id": net_id,
		"player_id": player.get("player_id"),
		"direction": [direction.x, direction.y],
	})


@rpc("any_peer", "call_remote", "reliable")
func _host_receive_fire_intent(data: Dictionary) -> void:
	if not NetworkManager.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var slot := NetworkManager.slot_of(sender)
	var net_id := str(data.get("net_id", ""))
	var player = _players.get(slot)
	var direction := NetPlayerInput.to_vec2(data.get("direction", null))
	var valid: bool = (
		slot >= 0 and int(data.get("player_id", -1)) == slot
		and player != null and is_instance_valid(player)
		and not player.health.is_dead() and direction != Vector2.ZERO
	)
	# try_fire re-checks the host-side cooldown, so a rate-hacked client still
	# fires no faster than its authoritative weapon allows.
	var proj = player.weapon.try_fire(direction.normalized(), net_id) if valid else null
	if proj == null and net_id != "":
		_client_reject_projectile.rpc_id(sender, net_id)
	# On success the weapon's spawn path broadcasts the projectile to everyone
	# (the same path the host's own shots take), echoing `net_id`.


## Replicates a host-spawned authoritative projectile to every client.
## Called by `Weapon` after effects have mutated the fresh shot, so the
## broadcast carries the post-effect state.
func broadcast_projectile(proj: Node, player_id: int) -> void:
	if not NetworkManager.is_host():
		return
	_client_spawn_projectile.rpc(projectile_payload(proj, player_id))


## Flattens the render-relevant state of a projectile for the spawn broadcast.
## Damage/lifesteal/knockback/explosion stay host-side: client instances are
## visual-only and never adjudicate hits. Pure — unit-testable with a stub.
static func projectile_payload(proj: Object, player_id: int) -> Dictionary:
	var pos: Vector2 = proj.get("global_position")
	var vel: Vector2 = proj.get("velocity")
	var proj_scale: Vector2 = proj.get("scale")
	return {
		"net_id": str(proj.get("net_id")),
		"player_id": player_id,
		"position": [pos.x, pos.y],
		"velocity": [vel.x, vel.y],
		"scale": proj_scale.x,
		"bounces": int(proj.get("bounces_remaining")),
		"homing": float(proj.get("homing")),
	}


@rpc("authority", "call_remote", "reliable")
func _client_spawn_projectile(data: Dictionary) -> void:
	var net_id := str(data.get("net_id", ""))
	var pos := NetPlayerInput.to_vec2(data.get("position", null))
	var vel := NetPlayerInput.to_vec2(data.get("velocity", null))
	if net_id != "" and _predicted_projectiles.has(net_id):
		# Our own predicted shot, confirmed: adopt the authoritative state onto
		# the existing instance instead of spawning a duplicate.
		var predicted = _predicted_projectiles[net_id]
		_predicted_projectiles.erase(net_id)
		if is_instance_valid(predicted):
			predicted.global_position = pos
			predicted.velocity = vel
		return
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	var direction := vel.normalized() if vel != Vector2.ZERO else Vector2.RIGHT
	proj.setup(
		direction, vel.length(), 0.0, float(data.get("scale", 1.0)),
		int(data.get("bounces", 0)), 0.0,
		_players.get(int(data.get("player_id", -1))),
		float(data.get("homing", 0.0)),
	)
	proj.visual_only = true
	proj.net_id = net_id
	get_tree().current_scene.add_child(proj)
	proj.global_position = pos
	proj.velocity = vel


@rpc("authority", "call_remote", "reliable")
func _client_reject_projectile(net_id: String) -> void:
	# The host refused the shot (cooldown / dead / invalid): undo the prediction.
	var predicted = _predicted_projectiles.get(net_id)
	_predicted_projectiles.erase(net_id)
	if predicted != null and is_instance_valid(predicted):
		predicted.queue_free()


## Globally unique client-generated projectile id: peer id + local counter.
static func make_projectile_id(peer_id: int, counter: int) -> String:
	return "%d_%d" % [peer_id, counter]


## Monotonic local clock (seconds) shared by the PUPPET interpolation path
## (#28): snapshots are stamped with it on receive, and the physics step renders
## `PUPPET_INTERP_DELAY` behind it. One source of truth keeps the receive
## timestamps and the render time on the same time base.
static func net_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------------------
# Match-flow events: host -> clients (reliable, ordered)
# ---------------------------------------------------------------------------

func broadcast_match_event(kind: String, data: Dictionary = {}) -> void:
	if not NetworkManager.is_host():
		return
	_client_receive_match_event.rpc(kind, data)


@rpc("authority", "call_remote", "reliable")
func _client_receive_match_event(kind: String, data: Dictionary) -> void:
	match_event.emit(kind, data)


# ---------------------------------------------------------------------------
# Lobby roster mirror + RNG seed transport (host -> clients, reliable)
# ---------------------------------------------------------------------------

func _on_lobby_changed() -> void:
	if NetworkManager.is_host() and NetworkManager.peer_count() > 0:
		broadcast_roster()


func broadcast_roster() -> void:
	if not NetworkManager.is_host():
		return
	_client_receive_roster.rpc(NetworkManager.peers.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _client_receive_roster(roster: Dictionary) -> void:
	NetworkManager.adopt_roster(roster)


## Broadcasts the match RNG seed so every peer's RNGService derives identical
## streams — the host→client seed transport #64/#66 parked on this issue.
func broadcast_seed(match_seed: int) -> void:
	if not NetworkManager.is_host():
		return
	_client_receive_seed.rpc(match_seed)


@rpc("authority", "call_remote", "reliable")
func _client_receive_seed(match_seed: int) -> void:
	RNGService.apply_seed(match_seed)

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

## Reliable client→host card pick (#82): a remote loser replicates its
## between-rounds choice back to the host, which gates the next round on every
## loser's pick being in. Emitted on the host once a pick passes the
## slot-ownership check; the host MatchDirector validates it against the hands it
## broadcast and records it.
signal card_pick_received(slot: int, card_id: String)

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
## Client: aim + owner kept per predicted shot (net_id -> {aim, player_id}) so a
## shot the host turns out to be delaying (#121) can be re-spawned in the right
## direction once the host's "accepted-pending" ack arrives.
var _predicted_aims: Dictionary = {}
## Client: shots the host acked as delayed and we are re-timing locally (#121).
## Each entry is {net_id, aim, player_id, remaining}; advanced every physics tick
## and spawned (visual-only) when `remaining` hits zero, to be adopted by the
## host's later projectile broadcast under the same id.
var _client_pending: Array = []
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


func _physics_process(delta: float) -> void:
	# A client re-times its prediction of any host-delayed shot (#121); the host
	# drives the snapshot cadence below.
	if NetworkManager.is_client():
		_advance_client_pending(delta)
		return
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
	_predicted_aims.clear()
	_client_pending.clear()


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
			# Ammo, like health, is adopted outright (host-authoritative, #117) so
			# the ammo HUD reads true for remote players too.
			state.apply_ammo_to(player)
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
	# Remember the aim + shooter so that, if the host acks this shot as delayed
	# (#121), we can re-spawn the prediction in the same direction when our mirrored
	# timer elapses. Cleared once the shot is confirmed, rejected, or re-timed.
	_predicted_aims[net_id] = {"aim": direction, "player_id": int(player.get("player_id"))}
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
	var result: FireResult = player.weapon.try_fire(direction.normalized(), net_id) if valid else FireResult.rejected()
	match fire_intent_response(result.outcome, net_id):
		"accept_pending":
			# #121: the shot is accepted but delayed. Ack it (carrying the delay) so
			# the client keeps/re-times its prediction instead of dropping it; the
			# eventual projectile broadcast (echoing `net_id`) adopts it. Without
			# this ack a delayed shot looked identical to a rejection.
			_client_accept_pending_projectile.rpc_id(sender, net_id, result.delay)
		"reject":
			_client_reject_projectile.rpc_id(sender, net_id)
		_:
			# "broadcast": a FIRED shot already broadcast from the weapon's spawn
			# path (the same path the host's own shots take), echoing `net_id`.
			# "ignore": an invalid/host-own shot with no client prediction to answer.
			pass


## How the host should answer a fire intent given the `try_fire` outcome and the
## shot's `net_id` (#121). Pure so the protocol decision is unit-testable:
## - SCHEDULED -> "accept_pending" (ack the delay, keep the client's prediction)
## - REJECTED  -> "reject" when a client predicted it (`net_id` set), else "ignore"
## - FIRED     -> "broadcast" (the spawn path already replicated it)
static func fire_intent_response(outcome: int, net_id: String) -> String:
	match outcome:
		FireResult.Outcome.SCHEDULED:
			return "accept_pending"
		FireResult.Outcome.REJECTED:
			return "reject" if net_id != "" else "ignore"
		_:
			return "broadcast"


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
	# The authoritative shot has landed, so this id is resolved: drop any leftover
	# re-timing state for it (#121) in case the broadcast beat our mirrored delay
	# timer — otherwise the pending entry would spawn a duplicate later.
	_predicted_aims.erase(net_id)
	_drop_client_pending(net_id)
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
	_predicted_aims.erase(net_id)
	_drop_client_pending(net_id)
	if predicted != null and is_instance_valid(predicted):
		predicted.queue_free()


# ---------------------------------------------------------------------------
# Delayed shots: host-acked, client-re-timed prediction (#121)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _client_accept_pending_projectile(net_id: String, delay: float) -> void:
	# #121: the host accepted this shot but is delaying its spawn by `delay`
	# seconds. Our instant prediction fired too early, so drop it and re-time a
	# visual-only re-spawn (mirroring the host's scheduler) that the host's later
	# projectile broadcast adopts under the same id.
	var premature = _predicted_projectiles.get(net_id)
	_predicted_projectiles.erase(net_id)
	if premature != null and is_instance_valid(premature):
		premature.queue_free()
	var meta: Dictionary = _predicted_aims.get(net_id, {})
	_predicted_aims.erase(net_id)
	_client_pending.append({
		"net_id": net_id,
		"aim": meta.get("aim", Vector2.ZERO),
		"player_id": int(meta.get("player_id", -1)),
		"remaining": maxf(delay, 0.0),
	})


## Advances the client's re-timed delayed predictions and spawns the ones whose
## mirrored timer elapsed this tick (#121).
func _advance_client_pending(delta: float) -> void:
	if _client_pending.is_empty():
		return
	var stepped := advance_client_pending(_client_pending, delta)
	_client_pending = stepped["waiting"]
	for entry in stepped["ready"]:
		_spawn_client_pending(entry)


## Counts down each pending delayed prediction by `delta`, partitioning them into
## the ones ready to spawn (`remaining` reached zero) and the ones still waiting.
## Pure (entries are copied, the input array is untouched) so the re-timing
## cadence is unit-testable, mirroring the host-side `Weapon._advance_pending`.
static func advance_client_pending(pending: Array, delta: float) -> Dictionary:
	var ready: Array = []
	var waiting: Array = []
	for entry in pending:
		var e: Dictionary = (entry as Dictionary).duplicate()
		e["remaining"] = float(e.get("remaining", 0.0)) - delta
		if e["remaining"] <= 0.0:
			ready.append(e)
		else:
			waiting.append(e)
	return {"ready": ready, "waiting": waiting}


## Spawns one re-timed delayed prediction (visual-only) through the shooter's
## weapon, registering it under its `net_id` so the host's broadcast adopts it.
## A no-op if the host's authoritative shot already resolved this id first.
func _spawn_client_pending(entry: Dictionary) -> void:
	var net_id := str(entry.get("net_id", ""))
	if net_id == "" or _predicted_projectiles.has(net_id):
		return
	var player = _players.get(int(entry.get("player_id", -1)))
	if player == null or not is_instance_valid(player):
		return
	var aim: Vector2 = entry.get("aim", Vector2.ZERO)
	if aim == Vector2.ZERO:
		return
	var proj = player.weapon.spawn_predicted(aim, net_id)
	if proj != null:
		_predicted_projectiles[net_id] = proj


## Removes any pending re-timed prediction for `net_id` (it was resolved by an
## authoritative broadcast or cancelled), so it never spawns a duplicate. Pure
## bookkeeping, no scene effect.
func _drop_client_pending(net_id: String) -> void:
	if net_id == "" or _client_pending.is_empty():
		return
	var kept: Array = []
	for entry in _client_pending:
		if str(entry.get("net_id", "")) != net_id:
			kept.append(entry)
	_client_pending = kept


## Drops every re-timed delayed prediction (#121) — called when a client releases
## the trigger / its player dies / the round ends, mirroring the host abandoning
## its scheduled shots (`Weapon.clear_pending`) so no orphan bullet spawns that
## the host will never broadcast. Off a client this is a no-op.
func clear_client_pending() -> void:
	_client_pending.clear()


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


## Client→host: replicates this peer's between-rounds card pick (#82). `card_id`
## is empty when the loser had nothing to pick. No-op off a client.
func send_card_pick(slot: int, card_id: String) -> void:
	if not NetworkManager.is_client():
		return
	_host_receive_card_pick.rpc_id(NetworkManager.HOST_PEER_ID, slot, card_id)


@rpc("any_peer", "call_remote", "reliable")
func _host_receive_card_pick(slot: int, card_id: String) -> void:
	if not NetworkManager.is_host():
		return
	# Trust the lobby, not the payload: a peer may only pick for its own slot.
	var sender_slot := NetworkManager.slot_of(multiplayer.get_remote_sender_id())
	if sender_slot < 0 or sender_slot != int(slot):
		return
	card_pick_received.emit(slot, card_id)


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


# ---------------------------------------------------------------------------
# Mid-match slot reclaim (#151): a reconnecting client presents the reconnect
# token it cached from the roster mirror; the host rebinds it to its held slot.
# ---------------------------------------------------------------------------

## Client → host: ask to reclaim the slot held for this peer, identifying it by
## the cached reconnect token. Called once the client has reconnected to the host.
func request_slot_reclaim() -> void:
	if not NetworkManager.is_client() or NetworkManager.local_reconnect_token == "":
		return
	_host_reclaim_slot.rpc_id(NetworkManager.HOST_PEER_ID, NetworkManager.local_reconnect_token)


@rpc("any_peer", "call_remote", "reliable")
func _host_reclaim_slot(token: String) -> void:
	if not NetworkManager.is_host():
		return
	# The token is the credential: it only matches a slot held for a peer that
	# genuinely dropped, so the sender reclaims exactly that slot (or, if the
	# token is unknown/already reclaimed, is registered fresh). The roster mirror
	# then propagates the restored slot back to every peer.
	NetworkManager.register_peer(multiplayer.get_remote_sender_id(), String(token))
	broadcast_roster()


## Broadcasts the match RNG seed so every peer's RNGService derives identical
## streams — the host→client seed transport #64/#66 parked on this issue.
func broadcast_seed(match_seed: int) -> void:
	if not NetworkManager.is_host():
		return
	_client_receive_seed.rpc(match_seed)


@rpc("authority", "call_remote", "reliable")
func _client_receive_seed(match_seed: int) -> void:
	RNGService.apply_seed(match_seed)

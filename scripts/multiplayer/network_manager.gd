extends Node

## Netcode foundation (#23): ENet peer setup, lobby/role management, and the
## basic player-state replication seam.
##
## Model: Godot high-level multiplayer (ENetMultiplayerPeer + MultiplayerAPI)
## with an authoritative host. See docs/netcode.md for the rationale and how the
## later sync-sensitive work (RNG #24, combat-state replication #27) plugs in.

## ENet transport port and peer cap. MAX_PEERS is left above MAX_PLAYERS to
## leave room for future spectators.
const DEFAULT_PORT := 7777
const MAX_PEERS := 8
## Networked players map onto the same 0-based player_id space the input maps
## (p1..p4), the HUD, and team assignment already use, so the rest of the game
## needs no online-specific branches. This caps assignable slots.
const MAX_PLAYERS := 4
## Godot's authoritative host always has this multiplayer unique id.
const HOST_PEER_ID := 1

enum Role { OFFLINE, HOST, CLIENT }

var peer: ENetMultiplayerPeer = null
var role: Role = Role.OFFLINE
## Host-authoritative lobby registry: peer_id (int) -> { "slot": int }.
var peers: Dictionary[int, Dictionary] = {}

signal server_started
signal client_connected
signal connection_failed
signal peer_connected(id: int)
signal peer_disconnected(id: int)
## Fired whenever the lobby roster changes (peer joined / left / reset) so the
## lobby UI and match setup can refresh.
signal lobby_changed


# ---------------------------------------------------------------------------
# Connection lifecycle
# ---------------------------------------------------------------------------

func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	role = Role.HOST
	peers.clear()
	register_peer(HOST_PEER_ID)  # the host occupies slot 0
	server_started.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	peers.clear()
	multiplayer.connected_to_server.connect(func(): client_connected.emit(), CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_client_connection_failed, CONNECT_ONE_SHOT)
	return OK


func disconnect_game() -> void:
	if peer:
		peer.close()
		peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	reset_lobby()


# ---------------------------------------------------------------------------
# Role queries
# ---------------------------------------------------------------------------

func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_networked() -> bool:
	return role != Role.OFFLINE


# ---------------------------------------------------------------------------
# Lobby roster (host-authoritative)
# ---------------------------------------------------------------------------

## Registers a peer, assigning it the lowest free player slot. Returns the
## assigned slot, or -1 if the lobby is already full (slot not stored).
func register_peer(peer_id: int) -> int:
	if peers.has(peer_id):
		return peers[peer_id].get("slot", -1)
	var slot := next_player_slot(slots_in_use())
	if slot < 0:
		return -1
	peers[peer_id] = {"slot": slot}
	lobby_changed.emit()
	return slot


## Removes a peer from the lobby. No-op if it wasn't registered.
func unregister_peer(peer_id: int) -> void:
	if peers.erase(peer_id):
		lobby_changed.emit()


## Clears the roster and returns to the OFFLINE role.
func reset_lobby() -> void:
	role = Role.OFFLINE
	if not peers.is_empty():
		peers.clear()
		lobby_changed.emit()


## The player slot assigned to a peer, or -1 if it isn't registered.
func slot_of(peer_id: int) -> int:
	return peers[peer_id].get("slot", -1) if peers.has(peer_id) else -1


## The local machine's assigned player slot, or -1 when offline or the roster
## hasn't been mirrored yet. On the host this is always slot 0.
func local_slot() -> int:
	if not is_networked() or multiplayer == null or multiplayer.multiplayer_peer == null:
		return -1
	return slot_of(multiplayer.get_unique_id())


## Client side of the lobby mirror (#27): adopts the host's authoritative
## roster wholesale, replacing any local view. Values are coerced defensively
## since the payload crossed the wire.
func adopt_roster(roster: Dictionary) -> void:
	peers.clear()
	for peer_id in roster:
		var info = roster[peer_id]
		if info is Dictionary:
			peers[int(peer_id)] = {"slot": int(info.get("slot", -1))}
	lobby_changed.emit()


func peer_count() -> int:
	return peers.size()


## The set of slots currently in use, for slot assignment.
func slots_in_use() -> Array[int]:
	var taken: Array[int] = []
	for info in peers.values():
		taken.append(int(info.get("slot", -1)))
	return taken


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# Only the authoritative host assigns slots; clients learn the roster from
	# the host's replication (#27).
	if is_host():
		register_peer(id)
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		unregister_peer(id)
	peer_disconnected.emit(id)


func _on_client_connection_failed() -> void:
	reset_lobby()
	connection_failed.emit()


# ---------------------------------------------------------------------------
# Pure helpers (no scene-tree dependencies — covered by tests/)
# ---------------------------------------------------------------------------

## Lowest free 0-based player slot in [0, MAX_PLAYERS) not present in `taken`,
## or -1 when every slot is occupied. Reusing freed slots keeps the player_id
## space compact as peers come and go.
static func next_player_slot(taken: Array) -> int:
	for slot in MAX_PLAYERS:
		if not taken.has(slot):
			return slot
	return -1

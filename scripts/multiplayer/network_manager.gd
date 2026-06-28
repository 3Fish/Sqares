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
## Mid-match reconnect grace (#151): when a non-host peer drops during a match its
## slot is HELD for this long instead of being freed. If the peer reclaims it
## within the window it resumes the current round; otherwise the slot's player is
## counted dead for the round, but the slot stays reserved so the peer can rejoin
## from the next round onward.
const RECONNECT_WINDOW_MS := 10000

enum Role { OFFLINE, HOST, CLIENT }

var peer: ENetMultiplayerPeer = null
var role: Role = Role.OFFLINE
## Host-authoritative lobby registry: peer_id (int) -> entry, where an entry is
## { "slot": int, "token": String, "connected": bool, "hold_deadline_ms": int }.
## `token` is the stable reconnect key (#151): because ENet reassigns the peer id
## on reconnect, a returning peer is matched back to its slot by token, not id.
## `connected` is false while a slot is held for a dropped peer; `hold_deadline_ms`
## is the wall-clock (Time.get_ticks_msec) at which the reconnect grace lapses
## (0 once it has been consumed or while the peer is connected).
var peers: Dictionary[int, Dictionary] = {}
## Set by the match flow (host only) while a round-driving match is live, so a
## peer dropping is treated as a recoverable disconnect rather than a lobby leave.
var match_in_progress: bool = false
## The reconnect token this machine was assigned by the host, kept so it can be
## re-presented to reclaim the same slot after a reconnect. Empty when offline or
## host (the host never migrates to itself; that is host migration, deferred).
var local_reconnect_token: String = ""
## Monotonic salt so freshly assigned tokens stay unique within a session even as
## slots are freed and reused.
var _token_salt: int = 0

signal server_started
signal client_connected
signal connection_failed
signal peer_connected(id: int)
signal peer_disconnected(id: int)
## Fired whenever the lobby roster changes (peer joined / left / reset) so the
## lobby UI and match setup can refresh.
signal lobby_changed
## Host-side: a held slot was reclaimed by a returning peer (#151). Carries the
## reconnecting peer's new id and the restored slot.
signal peer_reconnected(peer_id: int, slot: int)
## Host-side: a held slot's reconnect grace lapsed (#151). The slot stays reserved
## for the rest of the match; the match flow counts this slot's player as dead for
## the current round.
signal slot_hold_expired(slot: int)


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
##
## When `token` matches a HELD slot (a peer that dropped mid-match), the peer
## reclaims that exact slot instead of being given a new one — restoring its team
## and accumulated `win_counts`, which key off the slot rather than the peer id
## (#151). A fresh registration without a token gets a newly minted stable token.
func register_peer(peer_id: int, token: String = "") -> int:
	if token != "":
		var held_id := _peer_with_token(token, false)
		if held_id != -1:
			return _rebind_peer(held_id, peer_id)
	if peers.has(peer_id):
		return peers[peer_id].get("slot", -1)
	var slot := next_player_slot(slots_in_use())
	if slot < 0:
		return -1
	_token_salt += 1
	peers[peer_id] = {
		"slot": slot,
		"token": token if token != "" else reconnect_token(slot, _token_salt),
		"connected": true,
		"hold_deadline_ms": 0,
	}
	lobby_changed.emit()
	return slot


## Removes a peer from the lobby. No-op if it wasn't registered.
func unregister_peer(peer_id: int) -> void:
	if peers.erase(peer_id):
		lobby_changed.emit()


## Clears the roster and returns to the OFFLINE role.
func reset_lobby() -> void:
	role = Role.OFFLINE
	match_in_progress = false
	local_reconnect_token = ""
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
			peers[int(peer_id)] = {
				"slot": int(info.get("slot", -1)),
				"token": String(info.get("token", "")),
				"connected": bool(info.get("connected", true)),
				"hold_deadline_ms": int(info.get("hold_deadline_ms", 0)),
			}
	# A client caches its own reconnect token from the adopted roster so it can
	# re-present it to reclaim this slot after a reconnect (#151). Never clear a
	# known token with an empty one (a roster snapshot from before assignment).
	if is_client() and multiplayer != null and multiplayer.multiplayer_peer != null:
		var mine := token_of(multiplayer.get_unique_id())
		if mine != "":
			local_reconnect_token = mine
	lobby_changed.emit()


func peer_count() -> int:
	return peers.size()


## The set of slots currently in use, for slot assignment. Held (disconnected but
## reserved) slots count as in use, so a mid-match reconnect window keeps the slot
## from being handed to a fresh joiner (#151).
func slots_in_use() -> Array[int]:
	var taken: Array[int] = []
	for info in peers.values():
		taken.append(int(info.get("slot", -1)))
	return taken


# ---------------------------------------------------------------------------
# Mid-match reconnect / slot hold (#151) — host-authoritative
# ---------------------------------------------------------------------------

## Marks a peer's slot as held: the peer is no longer connected, but its slot is
## reserved and a reconnect grace runs until `now_ms + RECONNECT_WINDOW_MS`. No-op
## if the peer isn't registered.
func hold_peer(peer_id: int, now_ms: int) -> void:
	if not peers.has(peer_id):
		return
	peers[peer_id]["connected"] = false
	peers[peer_id]["hold_deadline_ms"] = now_ms + RECONNECT_WINDOW_MS
	lobby_changed.emit()


## Emits `slot_hold_expired` for every held slot whose grace has lapsed by
## `now_ms`, and returns those slots. The slot stays reserved (its entry is kept,
## token still valid) so the peer can rejoin from the next round — only the
## per-round death-grace is consumed (`hold_deadline_ms` reset to 0).
func expire_due_holds(now_ms: int) -> Array[int]:
	var expired: Array[int] = []
	for peer_id in peers:
		var info: Dictionary = peers[peer_id]
		if is_hold_expired(now_ms, int(info.get("hold_deadline_ms", 0))):
			info["hold_deadline_ms"] = 0
			expired.append(int(info.get("slot", -1)))
	for slot in expired:
		slot_hold_expired.emit(slot)
	return expired


## The reconnect token assigned to a peer, or "" if it isn't registered. The host
## sends this to its client so the client can re-present it after a reconnect.
func token_of(peer_id: int) -> String:
	return String(peers[peer_id].get("token", "")) if peers.has(peer_id) else ""


## Whether a given slot is currently held (its peer dropped and hasn't reclaimed).
func is_slot_held(slot: int) -> bool:
	for info in peers.values():
		if int(info.get("slot", -1)) == slot and not bool(info.get("connected", true)):
			return true
	return false


## All slots currently held for a dropped peer, for the lobby/HUD to flag.
func held_slots() -> Array[int]:
	var out: Array[int] = []
	for info in peers.values():
		if not bool(info.get("connected", true)):
			out.append(int(info.get("slot", -1)))
	return out


## Drops every held (disconnected) entry, freeing its slot. Called when the match
## ends so reserved slots don't linger into the next lobby.
func release_holds() -> void:
	var changed := false
	for peer_id in peers.keys():
		if not bool(peers[peer_id].get("connected", true)):
			peers.erase(peer_id)
			changed = true
	if changed:
		lobby_changed.emit()


## Toggles the live-match flag (host only). Turning it off also releases any slots
## still held for peers that never came back.
func set_match_in_progress(active: bool) -> void:
	match_in_progress = active
	if not active:
		release_holds()


## Rebinds a held entry from its old peer id to the reconnecting peer's new id,
## restoring the slot and clearing the hold. If the reconnecting peer was given a
## throwaway fresh slot on raw connect (before presenting its token), that stray
## entry is dropped first.
func _rebind_peer(old_id: int, new_id: int) -> int:
	var info: Dictionary = peers[old_id]
	if new_id != old_id:
		peers.erase(new_id)
		peers.erase(old_id)
	info["connected"] = true
	info["hold_deadline_ms"] = 0
	peers[new_id] = info
	var slot := int(info.get("slot", -1))
	peer_reconnected.emit(new_id, slot)
	lobby_changed.emit()
	return slot


## The peer id whose entry carries `token` and whose connected state matches
## `want_connected`, or -1. Used to find a held slot to reclaim on reconnect.
func _peer_with_token(token: String, want_connected: bool) -> int:
	for peer_id in peers:
		var info: Dictionary = peers[peer_id]
		if String(info.get("token", "")) == token and bool(info.get("connected", true)) == want_connected:
			return int(peer_id)
	return -1


## Whether any slot is mid-grace (a reconnect window is ticking), so `_process`
## can stay idle the rest of the time.
func _has_pending_hold() -> bool:
	for info in peers.values():
		if int(info.get("hold_deadline_ms", 0)) > 0:
			return true
	return false


func _now_ms() -> int:
	return Time.get_ticks_msec()


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
		# Mid-match, hold the slot for a reconnect grace (#151); in the lobby a
		# leave just frees the slot.
		if match_in_progress:
			hold_peer(id, _now_ms())
		else:
			unregister_peer(id)
	peer_disconnected.emit(id)


## Host-only: drives the reconnect-grace clock (#151). Kept cheap — it only walks
## the roster while a match is live and at least one slot is actually being held.
func _process(_delta: float) -> void:
	if is_host() and match_in_progress and _has_pending_hold():
		expire_due_holds(_now_ms())


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


## A stable reconnect token for a slot (#151). Deterministic from the slot and a
## per-session salt, so it is unique within a session without needing RNG; the
## value is opaque — callers only ever compare it for equality.
static func reconnect_token(slot: int, salt: int) -> String:
	return "s%d-%d" % [slot, salt]


## Whether a hold's reconnect grace has lapsed by `now_ms`. A deadline of 0 means
## "not held / grace already consumed", so it never reads as expired.
static func is_hold_expired(now_ms: int, deadline_ms: int) -> bool:
	return deadline_ms > 0 and now_ms >= deadline_ms

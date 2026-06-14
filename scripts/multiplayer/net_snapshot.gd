extends RefCounted
class_name NetSnapshot

## Per-net-tick authoritative world snapshot (#27).
##
## The host packs the state of *all* players into one of these every net tick
## and broadcasts it over a single unreliable RPC; clients apply the newest one
## they have seen (stale out-of-order packets are dropped by tick number).
##
## `tick` is the host's physics tick at capture time. It is part of the wire
## format from day one so the latency-smoothing pass (#28) can buffer and
## interpolate snapshots without a format change — this issue's scope is
## deliberately "correct but unsmoothed".
##
## Plain and scene-free, like NetPlayerState: `to_dict` / `from_dict`
## round-trip through a JSON-portable Dictionary.

## Host physics tick this snapshot was captured on; strictly increasing.
var tick: int = 0
var players: Array[NetPlayerState] = []


## Serialises to a flat, JSON-portable dictionary.
func to_dict() -> Dictionary:
	var states: Array = []
	for state in players:
		states.append(state.to_dict())
	return {"tick": tick, "players": states}


## Rebuilds a snapshot from a dictionary produced by `to_dict`. Malformed
## player entries are skipped rather than crashing the client.
static func from_dict(data: Dictionary) -> NetSnapshot:
	var snap := NetSnapshot.new()
	snap.tick = int(data.get("tick", 0))
	var states = data.get("players", [])
	if states is Array:
		for entry in states:
			if entry is Dictionary:
				snap.players.append(NetPlayerState.from_dict(entry))
	return snap


## Captures every live player into one snapshot. `last_seqs` maps player_id to
## the last input sequence the host has processed for that player (absent for
## host-local players, which have no input stream to ack).
static func capture(p_players: Array, p_tick: int, last_seqs: Dictionary = {}) -> NetSnapshot:
	var snap := NetSnapshot.new()
	snap.tick = p_tick
	for player in p_players:
		if player == null:
			continue
		var pid := int(player.get("player_id"))
		snap.players.append(NetPlayerState.capture(player, int(last_seqs.get(pid, 0))))
	return snap


## The captured state for a player, or null when the snapshot doesn't carry it.
func state_for(p_player_id: int) -> NetPlayerState:
	for state in players:
		if state.player_id == p_player_id:
			return state
	return null

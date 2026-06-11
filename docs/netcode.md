# Netcode foundation — model & architecture

This is the architectural slice the multiplayer epic (#13) hangs on. It decides
*how* Sqares goes online and lays down the host/join + lobby + basic
player-state replication seam that the later sync-sensitive work (combat-state
replication #27, resilience #28) builds on. The deterministic RNG service (#24)
plugs into the seed-transport hook described below.

## The decision: Godot high-level multiplayer, authoritative host

Sqares uses **Godot 4's high-level multiplayer** — `ENetMultiplayerPeer` driving
the engine's `MultiplayerAPI` (RPCs + `MultiplayerSynchronizer`) — with an
**authoritative-host** model: one peer (the host, multiplayer id `1`) owns the
canonical game state; clients send input and render the state the host
replicates back.

### Why not lockstep?

Lockstep (every peer simulates the same world from shared inputs) was
considered and rejected:

- It requires **bit-deterministic simulation**. Sqares' movement is built on
  `CharacterBody2D` / `move_and_slide` and floating-point physics, which Godot
  does **not** guarantee to be identical across platforms or even CPU builds.
  Making the whole arena deterministic would be a large, fragile rewrite.
- High-level multiplayer is the **Godot-native** path and the existing
  `NetworkManager` already used `ENetMultiplayerPeer`, so this is the lower-risk,
  lower-effort foundation.

### Why authoritative host (not peer-to-peer / client-side authority)?

- A single source of truth removes whole classes of desync and cheating.
- It composes cleanly with the **deterministic RNG service (#24)**: the host
  calls `RNGService.seed_match()`, broadcasts the returned seed, and clients
  `apply_seed()` it, so card draws and effect rolls agree everywhere.
- It matches the game's couch-first / mod-first design: a host (often the same
  machine running local couch play) extends naturally to "host + remote
  clients."

## Player slots

Networked players map onto the **same 0-based `player_id` space** that local
couch play already uses (`p1..p4` input maps, the four HUD readouts, team
assignment). When a peer connects, the host assigns the lowest free slot
(`NetworkManager.next_player_slot`). This keeps a single notion of "player N"
across local and online play, so the rest of the game — input, HUD, win
tracking, cards — needs no online-specific branches.

`MAX_PLAYERS` (4) caps assignable slots; `MAX_PEERS` (8) is the ENet transport
cap, left higher to leave room for future spectators.

## Lobby / role management (`scripts/multiplayer/network_manager.gd`)

`NetworkManager` is the autoload that owns the connection lifecycle:

| API | Role |
| --- | --- |
| `host_game(port)` / `join_game(address, port)` | Stand up the ENet server / client. |
| `disconnect_game()` | Tear down and reset the lobby to `OFFLINE`. |
| `role` (`Role.OFFLINE/HOST/CLIENT`) | Current connection role. |
| `is_host()` / `is_client()` / `is_networked()` | Role queries. |
| `peers` | `peer_id -> { "slot": int }` registry (host-authoritative). |
| `register_peer(id)` / `unregister_peer(id)` | Add/remove a peer, assigning a slot. |
| `slot_of(id)` / `peer_count()` | Lobby lookups. |
| `next_player_slot(taken)` *(static)* | Pure slot-assignment helper. |

The host registers itself (`peer_id 1`, slot 0) on `host_game`, then assigns a
slot to each peer in `multiplayer.peer_connected`. The matching
`peer_connected` / `peer_disconnected` / `lobby_changed` signals let the lobby
UI and match setup react.

## Basic player-state replication (`scripts/multiplayer/player_state.gd`)

`NetPlayerState` is the **data contract** for the minimal state a client needs
to render a remote player: `player_id`, `position`, `velocity`, and `health`.
It is plain, scene-free, and JSON-portable (`to_dict` / `from_dict`), and offers
`capture(player)` / `apply_to(player)` to read from and write to a live `Player`
node (duck-typed, so a test stub works too).

The authority captures a snapshot per network tick and broadcasts it; clients
apply it. The transport itself (the RPC fan-out, tick rate, interpolation) and
the projectile / spawn / health-event replication and **input reconciliation**
are the explicit scope of **#27** — this issue establishes the model, the lobby,
and the snapshot contract they consume.

## What this foundation deliberately leaves to later issues

- **#24** — deterministic RNG: the service exists; wiring `seed_match()` over the
  host→client broadcast described above is its remaining "synced" half (#64).
- **#27** — full combat-state replication (projectiles, health events, spawns)
  and input reconciliation / prediction.
- **#28** — disconnect/reconnect handling and latency smoothing.

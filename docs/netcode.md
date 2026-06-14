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
apply it. The transport that drives this — the RPC fan-out, tick rate, and the
projectile / health-event / round replication plus **input reconciliation** —
is `NetReplicator` (#27), described next; this foundation establishes the
model, the lobby, and the snapshot contract it consumes.

## Combat-state replication + input reconciliation (`scripts/multiplayer/net_replicator.gd`)

`NetReplicator` is the autoload that runs an online match on top of the
foundation above. It is a **manual RPC fan-out** (no `MultiplayerSynchronizer`)
on the authoritative-host model: the host owns canonical state, clients predict
their own player locally and reconcile against the host.

### Roles

Every spawned `Player` carries a `net_role` (`Player.NetRole`) that
`MatchDirector.resolve_net_role` assigns from the lobby:

| Role | Where | Drives the player from |
| --- | --- | --- |
| `LOCAL` | offline play; the host's own square | this machine's input, simulated authoritatively |
| `PREDICTED` | a client's own square | local input applied immediately, corrected against host snapshots |
| `SIMULATED` | the host's view of a remote client | that client's replicated input stream |
| `PUPPET` | a client's view of any other square | host snapshots, applied directly (no simulation) |

### The three streams

- **Input (client → host, unreliable, redundant).** Each `PREDICTED` player
  samples a `NetPlayerInput` per physics tick — a monotonically increasing
  `seq`, the move axis, jump edge, shoot, and aim — applies it immediately, and
  records it in a `NetPrediction` history. Every tick it resends the newest
  unacked window (so loss self-heals). The host folds each window into a
  per-player queue (`merge_input` dedupes by `seq`), simulates `SIMULATED`
  players from it, and records the last processed `seq` as the per-player ack.
- **Snapshots (host → clients, unreliable, newest-wins).** Every
  `NET_TICK_INTERVAL` physics ticks the host packs all players into one
  `NetSnapshot` (a host `tick`, and per player position / velocity / health /
  `last_input_seq`) and broadcasts it. Clients drop stale ticks, apply state
  directly to `PUPPET`s, and **reconcile** their `PREDICTED` player: ack the
  history up to `last_input_seq`, and if the authoritative position disagrees by
  more than `RECONCILE_TOLERANCE`, rewind to it and replay the still-pending
  inputs. `tick` is on the wire from day one so #28 can add an interpolation
  buffer without a format change.
- **Events (host → clients, reliable, ordered).** One-shot things that must not
  be lost: projectile spawns/rejections, deaths (`player_died`), the round
  lifecycle (`round_start` / `fight` / `round_end` / `match_end` /
  `match_restart`), the lobby roster mirror, and the match RNG seed. The client
  `MatchDirector` mirrors the host's rounds off these instead of running its own
  round-end detection.

### Projectiles

Shooter-side prediction, host-authoritative resolution. A `PREDICTED` shot
spawns a **visual-only** projectile immediately and sends a fire intent with a
client-generated `net_id`; the host validates it (slot ownership, alive, weapon
cooldown), fires the authoritative projectile, and replicates it back echoing
the `net_id` so the shooter adopts its predicted instance (or frees it on
rejection). **All hit detection and damage are host-only** — every projectile a
client spawns is `visual_only` and never calls `take_damage`.

### Synced seed + roster

Two seams the foundation left open are wired here: on match start the host
broadcasts `RNGService.seed_match()` so card draws / effect rolls (#24) agree on
every peer, and whenever the lobby changes the host pushes its authoritative
roster to clients (`NetworkManager.adopt_roster`) so each client learns its slot.

## What this layer deliberately leaves to later issues

- **#28** — disconnect/reconnect handling and latency smoothing (snapshot
  interpolation/extrapolation of `PUPPET`s; this layer is "correct but
  unsmoothed", so remote squares step at the net tick rate).
- Online **card selection** (remote losers picking on their own screens) is not
  wired — networked matches skip the selection phase for now (see the #27
  deferred follow-up).

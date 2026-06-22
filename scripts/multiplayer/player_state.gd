extends RefCounted
class_name NetPlayerState

## Basic per-player replication snapshot (#23).
##
## The minimal authoritative state a client needs to render a remote player:
## which player it is, where it is, how it's moving, its current health, and its
## host-authoritative magazine count (#117, for the ammo HUD).
## This is the data *contract* for replication; the transport (RPC fan-out, tick
## rate, interpolation) and the richer projectile / spawn / health-event
## replication + input reconciliation are #27.
##
## Plain and scene-free: `to_dict` / `from_dict` round-trip through a
## JSON-portable Dictionary (matching the ArenaData serialisation convention),
## while `capture` / `apply_to` read from and write to a live `Player` node.
## Both node helpers are duck-typed, so a test stub exposing the same fields
## stands in for a real `Player` without a scene tree.

var player_id: int = 0
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var health: float = 0.0
## Sequence number of the last input the host had processed for this player
## when the snapshot was captured (#27). Clients use it to ack their prediction
## history; 0 means "no input processed yet" (e.g. host-simulated locals).
var last_input_seq: int = 0
## Rounds in the magazine, host-authoritative (#117): a client never tracks its
## own ammo, so the host surfaces the count here for the ammo HUD (#116) to read
## true on every peer. -1 means "not carried" (a player with no weapon, or an
## older payload) so a partial snapshot never wrongly empties a magazine.
var ammo: int = -1


## Serialises to a flat, JSON-portable dictionary. Vectors are flattened to
## `[x, y]` arrays (same shape ArenaData uses).
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"position": [position.x, position.y],
		"velocity": [velocity.x, velocity.y],
		"health": health,
		"last_input_seq": last_input_seq,
		"ammo": ammo,
	}


## Rebuilds a snapshot from a dictionary produced by `to_dict`. Missing or
## malformed fields fall back to defaults so a partial payload never crashes.
static func from_dict(data: Dictionary) -> NetPlayerState:
	var s := NetPlayerState.new()
	s.player_id = int(data.get("player_id", 0))
	s.position = _to_vec2(data.get("position", null))
	s.velocity = _to_vec2(data.get("velocity", null))
	s.health = float(data.get("health", 0.0))
	s.last_input_seq = int(data.get("last_input_seq", 0))
	s.ammo = int(data.get("ammo", -1))
	return s


## Reads a snapshot off a live `Player` node (or any object exposing
## `player_id`, `global_position`, `velocity`, and a `health` with `current_hp`).
## `last_input_seq` is bookkeeping the host owns (not player state), so it is
## passed in rather than read off the node.
static func capture(player: Object, p_last_input_seq: int = 0) -> NetPlayerState:
	var s := NetPlayerState.new()
	if player == null:
		return s
	s.player_id = int(player.get("player_id"))
	s.position = player.get("global_position")
	s.velocity = player.get("velocity")
	s.last_input_seq = p_last_input_seq
	var hp = player.get("health")
	if hp != null:
		s.health = float(hp.current_hp)
	var weapon = player.get("weapon")
	if weapon != null and weapon.has_method("get_ammo"):
		s.ammo = int(weapon.get_ammo())
	return s


## Writes this snapshot's transform/health onto a live `Player` node. Used by a
## client to mirror the authority's state for a remote player.
func apply_to(player: Object) -> void:
	if player == null:
		return
	player.set("global_position", position)
	player.set("velocity", velocity)
	var hp = player.get("health")
	if hp != null:
		hp.current_hp = health
	apply_ammo_to(player)


## Adopts just the authoritative magazine count onto a live player's weapon
## (#117), without touching its transform/health. Used by the snapshot path,
## which adopts health and ammo outright but reconciles position separately. A
## `-1` ammo (not carried) or a weaponless player is a no-op, so an old payload
## never clears a magazine.
func apply_ammo_to(player: Object) -> void:
	if player == null or ammo < 0:
		return
	var weapon = player.get("weapon")
	if weapon != null and weapon.has_method("set_ammo"):
		weapon.set_ammo(ammo)


static func _to_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

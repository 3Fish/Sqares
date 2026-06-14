extends RefCounted
class_name NetPlayerInput

## Per-tick sampled player input (#27).
##
## The unit of the client→host input stream: everything the host needs to
## simulate one physics tick of a remote player. Each input carries a
## monotonically increasing sequence number so the host can acknowledge how far
## it has simulated (echoed per player in snapshots as `last_input_seq`) and the
## client can reconcile its prediction history against that acknowledgement.
##
## Plain and scene-free: `to_dict` / `from_dict` round-trip through a
## JSON-portable Dictionary (vectors flattened to `[x, y]`, matching the
## NetPlayerState / ArenaData convention). Sampling from the live Input
## singleton lives on `Player._sample_input`, which owns the action-map prefix.

## Client-assigned sequence number; strictly increasing per player per match.
var seq: int = 0
## Horizontal move axis in [-1, 1] (`Input.get_axis` of the move actions).
var move_axis: float = 0.0
## True only on the tick the jump action was just pressed (one-shot edge).
var jump: bool = false
## True while the shoot action is held.
var shoot: bool = false
## Normalised aim direction; ZERO when not shooting.
var aim: Vector2 = Vector2.ZERO


## Serialises to a flat, JSON-portable dictionary.
func to_dict() -> Dictionary:
	return {
		"seq": seq,
		"move_axis": move_axis,
		"jump": jump,
		"shoot": shoot,
		"aim": [aim.x, aim.y],
	}


## Rebuilds an input from a dictionary produced by `to_dict`. Missing or
## malformed fields fall back to neutral defaults so a partial payload never
## crashes the host's simulation.
static func from_dict(data: Dictionary) -> NetPlayerInput:
	var input := NetPlayerInput.new()
	input.seq = int(data.get("seq", 0))
	input.move_axis = clampf(float(data.get("move_axis", 0.0)), -1.0, 1.0)
	input.jump = bool(data.get("jump", false))
	input.shoot = bool(data.get("shoot", false))
	input.aim = to_vec2(data.get("aim", null))
	return input


## Shared `[x, y]`-array → Vector2 coercion for net payloads.
static func to_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

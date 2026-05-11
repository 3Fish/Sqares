extends Node

## Allows mods to register new player actions (e.g. dash, wall-jump).
## All built-in actions are registered through mods/base_game/.
## Implemented fully in feature/02-player-movement.

# action_id -> GDScript
var _actions: Dictionary = {}


func register(action_id: String, script: GDScript) -> void:
	_actions[action_id] = script


func get_action(action_id: String) -> GDScript:
	return _actions.get(action_id, null)


func get_all_ids() -> Array:
	return _actions.keys()


func has_action(action_id: String) -> bool:
	return _actions.has(action_id)

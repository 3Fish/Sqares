extends Node

## Indexes game-mode scripts by string ID. Mods register custom modes here.
## Built-in modes (FFA, Teams) are registered through mods/base_game/.
## Implemented fully in feature/13-moddable-levels-gamemodes.

# mode_id -> GDScript
var _modes: Dictionary = {}


func register(mode_id: String, script: GDScript) -> void:
	_modes[mode_id] = script


func get_mode(mode_id: String) -> GDScript:
	return _modes.get(mode_id, null)


func get_all_ids() -> Array:
	return _modes.keys()


func has_mode(mode_id: String) -> bool:
	return _modes.has(mode_id)

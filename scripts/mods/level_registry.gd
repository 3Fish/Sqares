extends Node

## Indexes arena scenes by string ID. Mods register custom maps here.
## Built-in arenas are registered through mods/base_game/.
## Implemented fully in feature/13-moddable-levels-gamemodes.

# level_id -> PackedScene
var _levels: Dictionary = {}


func register(level_id: String, scene: PackedScene) -> void:
	_levels[level_id] = scene


func get_level(level_id: String) -> PackedScene:
	return _levels.get(level_id, null)


func get_all_ids() -> Array:
	return _levels.keys()


func has_level(level_id: String) -> bool:
	return _levels.has(level_id)

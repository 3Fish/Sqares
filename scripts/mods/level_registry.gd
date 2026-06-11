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


## Build a runtime arena from `data` and register it under its id, so custom
## arenas appear in match setup alongside built-in ones. Returns true on
## success. Like all registrations, last write wins — a custom arena may shadow
## a built-in one sharing its id.
func register_arena_data(data: ArenaData) -> bool:
	if data == null:
		push_error("LevelRegistry: cannot register a null arena.")
		return false
	if data.id.strip_edges().is_empty():
		push_error("LevelRegistry: cannot register an arena with an empty id.")
		return false
	var scene := ArenaBuilder.build_packed_scene(data)
	if scene == null:
		return false
	register(data.id, scene)
	return true


## Load every custom arena saved under `user://arenas/` (via [ArenaStore]) and
## register each. Returns the ids that were successfully registered. Called
## after mods load so built-in arenas exist first; custom arenas may override.
func load_custom_arenas() -> Array[String]:
	var registered: Array[String] = []
	for data in ArenaStore.load_all():
		if register_arena_data(data):
			registered.append(data.id)
	return registered

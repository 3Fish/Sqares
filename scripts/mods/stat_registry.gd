extends Node

## Runtime registry of all player stat names and their default values.
## Stats are registered by mods at startup — there is no fixed enum.
## Implemented fully in feature/08-card-effects-engine.

# stat_name -> default_value
var _defaults: Dictionary = {}


func register(stat_name: String, default_value: float) -> void:
	if _defaults.has(stat_name):
		push_warning("StatRegistry: stat '%s' already registered — skipping." % stat_name)
		return
	_defaults[stat_name] = default_value


func get_defaults() -> Dictionary:
	return _defaults.duplicate()


func has_stat(stat_name: String) -> bool:
	return _defaults.has(stat_name)

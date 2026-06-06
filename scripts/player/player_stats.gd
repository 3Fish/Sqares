class_name PlayerStats extends RefCounted

## Per-player runtime stat store, initialised from StatRegistry defaults at match start.
## Card effects mutate individual entries here, then call Player.apply_stats() to propagate.

var _data: Dictionary


func _init(defaults: Dictionary) -> void:
	_data = defaults.duplicate(true)


func get_stat(stat_name: String, fallback: Variant = 0.0) -> Variant:
	return _data.get(stat_name, fallback)


func set_stat(stat_name: String, value: Variant) -> void:
	_data[stat_name] = value


## Additively adjusts a numeric stat — useful for "+N" card effects.
func modify_stat(stat_name: String, delta: float) -> void:
	_data[stat_name] = float(_data.get(stat_name, 0.0)) + delta


## Merges overrides into the stat store, replacing existing values.
func merge(overrides: Dictionary) -> void:
	for key in overrides:
		_data[key] = overrides[key]


## Returns a shallow copy of all stats as a plain Dictionary for component propagation.
func to_dict() -> Dictionary:
	return _data.duplicate()

extends Node

## Runtime registry of all player stat names and their default values.
## Stats are registered by mods at startup — there is no fixed enum.
## Implemented fully in feature/08-card-effects-engine.
##
## A stat may optionally declare a lower and/or upper bound (#43). Bounds are
## stored alongside the default and are entirely optional: a stat with no bound
## is unconstrained (the default), favouring modding freedom over a "safe" game —
## a mod that registers a wild range is the mod's own concern. The effect engine
## clamps a mutated stat to its registered bound (see `StatCardEffect.on_apply`),
## so a "+N"/"-N" card can never drive, e.g., `move_speed` negative or
## `max_health` to an instant-death `0`.

# stat_name -> default_value
var _defaults: Dictionary = {}
# stat_name -> {"min": float, "max": float}. Omitted ends use -INF / INF, so an
# unbounded stat clamps to itself.
var _bounds: Dictionary = {}


## Registers a stat with its default and optional lower/upper bounds. `min_value`
## / `max_value` default to -INF / INF (unbounded). Existing two-argument callers
## are unaffected — they simply register an unbounded stat.
func register(stat_name: String, default_value: float, min_value: float = -INF, max_value: float = INF) -> void:
	if _defaults.has(stat_name):
		push_warning("StatRegistry: stat '%s' already registered — skipping." % stat_name)
		return
	_defaults[stat_name] = default_value
	_bounds[stat_name] = {"min": min_value, "max": max_value}


func set_default(stat_name: String, default_value: float) -> void:
	if not _defaults.has(stat_name):
		push_warning("StatRegistry: stat '%s' not registered — use register() first." % stat_name)
		return
	_defaults[stat_name] = default_value


func get_defaults() -> Dictionary:
	return _defaults.duplicate()


func has_stat(stat_name: String) -> bool:
	return _defaults.has(stat_name)


## The registered [min, max] bounds for a stat as a two-element array, or
## `[-INF, INF]` for an unbounded or unregistered stat.
func get_bounds(stat_name: String) -> Array:
	if not _bounds.has(stat_name):
		return [-INF, INF]
	var b: Dictionary = _bounds[stat_name]
	return [b["min"], b["max"]]


## Clamps `value` to `stat_name`'s registered bounds. An unregistered or
## unbounded stat returns the value unchanged (clamping to -INF/INF is a no-op),
## so this is always safe to call after mutating any stat.
func clamp_value(stat_name: String, value: float) -> float:
	if not _bounds.has(stat_name):
		return value
	var b: Dictionary = _bounds[stat_name]
	return clampf(value, b["min"], b["max"])

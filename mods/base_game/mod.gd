extends SqaresModBase

## Built-in game content. Registers all base stats, cards, arenas, and game modes
## using the same public API available to third-party mods.
## Content is populated progressively across feature branches.

func _on_load() -> void:
	_register_base_stats()
	_register_arenas()


func _register_arenas() -> void:
	LevelRegistry.register("crossroads", preload("res://scenes/arena/arena_crossroads.tscn"))
	LevelRegistry.register("highrise",   preload("res://scenes/arena/arena_highrise.tscn"))


func _register_base_stats() -> void:
	# Core movement stats
	StatRegistry.register("move_speed",      300.0)
	StatRegistry.register("jump_force",      550.0)
	StatRegistry.register("gravity_scale",   1.0)

	# Combat stats
	StatRegistry.register("max_health",      100.0)
	StatRegistry.register("damage",          25.0)
	StatRegistry.register("fire_rate",       1.0)   # shots per second
	StatRegistry.register("bullet_speed",    800.0)
	StatRegistry.register("bullet_scale",    1.0)
	StatRegistry.register("bullet_bounces",  0.0)
	StatRegistry.register("bullet_homing",   0.0)   # 0=none, 1=full
	StatRegistry.register("lifesteal",       0.0)   # HP per kill

	# Defensive stats
	StatRegistry.register("shield_charges",  0.0)

	# Physics extras (available for mod cards)
	StatRegistry.register("knockback_force", 0.0)
	StatRegistry.register("explosion_radius",0.0)

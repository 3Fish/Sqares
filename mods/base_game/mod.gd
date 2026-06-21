extends SqaresModBase

## Built-in game content. Registers all base stats, cards, arenas, and game modes
## using the same public API available to third-party mods.
## Content is populated progressively across feature branches.

func _on_load() -> void:
	_register_base_stats()
	_register_arenas()
	_register_cards()
	_register_modes()


func _register_modes() -> void:
	# Built-in game modes, registered through the same GameModeRegistry API a
	# third-party mod would use. "ffa" is the base GameMode (Free-for-all);
	# "teams" splits players into balanced teams.
	GameModeRegistry.register("ffa", preload("res://scripts/modes/game_mode.gd"))
	GameModeRegistry.register("teams", preload("res://scripts/modes/teams_mode.gd"))


func _register_cards() -> void:
	# The base-game card set (#18): movement / offense / defense cards spanning
	# all registered stats, each backed by a StatCardEffect. Authored as a pure
	# static factory (BaseCards.build) so the set is unit-testable on its own.
	for card in BaseCards.build():
		register_card(card)


func _register_arenas() -> void:
	LevelRegistry.register("crossroads", preload("res://scenes/arena/arena_crossroads.tscn"))
	LevelRegistry.register("highrise",   preload("res://scenes/arena/arena_highrise.tscn"))


func _register_base_stats() -> void:
	# Core movement stats
	StatRegistry.register("move_speed",      300.0)
	StatRegistry.register("jump_force",      550.0)
	StatRegistry.register("gravity_scale",   1.0)

	# Physics / body stats
	# Player body size — drives the player's mass in the physics system (#96):
	# mass = player_size * density. Registered (not a const) so cards can tune it.
	StatRegistry.register("player_size",     32.0)

	# Combat stats
	StatRegistry.register("max_health",      100.0)
	StatRegistry.register("damage",          25.0)
	StatRegistry.register("fire_rate",       1.0)   # shots per second
	StatRegistry.register("bullet_speed",    800.0)
	StatRegistry.register("bullet_scale",    1.0)
	StatRegistry.register("bullet_bounces",  0.0)
	StatRegistry.register("bullet_homing",   0.0)   # 0=none, 1=full
	StatRegistry.register("lifesteal",       0.0)   # HP per kill

	# Ammo / reload (#113). The weapon holds a magazine of discrete rounds; firing
	# draws it down by the shot's ammo_cost and an over-cost shot is denied. The
	# magazine snaps back to full once the player has not fired for `reload_time`
	# seconds (instant refill — the stat is the idle duration, so smaller reloads
	# sooner). Both are card-tunable.
	StatRegistry.register("magazine_size",   3.0)   # rounds per magazine
	StatRegistry.register("reload_time",     1.0)   # idle seconds before a full reload

	# Defensive stats
	StatRegistry.register("shield_charges",  0.0)

	# Physics extras (available for mod cards)
	StatRegistry.register("knockback_force", 0.0)
	StatRegistry.register("explosion_radius",0.0)

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
	# move_speed has a 0 floor (#43): a card can leave you unable to move, but
	# never drive the speed negative (which would invert movement). No upper cap —
	# runaway speed is left to modding freedom.
	StatRegistry.register("move_speed",      300.0, 0.0)
	StatRegistry.register("jump_force",      550.0)
	StatRegistry.register("gravity_scale",   1.0)

	# Physics / body stats
	# Player body size — drives the player's mass in the physics system (#96):
	# mass = player_size * density. Registered (not a const) so cards can tune it.
	StatRegistry.register("player_size",     32.0)

	# Combat stats
	# max_health has a 1 floor (#43): a card can chip away at survivability but
	# never drop the cap to 0 (an instant-death / un-spawnable state).
	StatRegistry.register("max_health",      100.0, 1.0)
	StatRegistry.register("damage",          25.0)
	# #125: fire_interval is the time in seconds between shots (lower = faster),
	# redefined from the old shots-per-second `fire_rate` so a `>= 0` floor is now
	# meaningful — `0` means no enforced delay (fire as fast as the physics tick /
	# input allows), and the weapon uses the value directly as its cooldown instead
	# of dividing by it. The Rapid Fire card grants a negative delta to speed up.
	StatRegistry.register("fire_interval",   0.5, 0.0)   # seconds between shots
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

	# Defensive stats — the reflecting shield (#138). A manually-raised shield
	# reflects every incoming bullet (straight reversal) for `shield_duration`
	# seconds; raising it consumes one of `shield_charges` (the max, ammo-clip
	# style), and `shield_recharge` regenerates +1 charge at a time up to that max.
	# Every player has one shield by default. `shield_penetration` is the *bullet*
	# stat that punches through a raised shield: unclamped, `p<0` heals through it,
	# `p=0` is fully reflected, `0<p` lands `p×damage` and consumes the bullet.
	StatRegistry.register("shield_charges",     1.0)   # max charges (default: one shield)
	StatRegistry.register("shield_duration",    0.5)   # seconds the raised shield reflects
	StatRegistry.register("shield_recharge",    2.0)   # seconds to regenerate one charge
	StatRegistry.register("shield_penetration", 0.0)   # offensive: fraction of damage through a shield

	# Physics extras (available for mod cards)
	StatRegistry.register("knockback_force", 0.0)
	StatRegistry.register("explosion_radius",0.0)
	# Explosion feel (#52). Splash damage is a multiple of the bullet's damage
	# (not a flat copy) and, when the bullet itself knocks back, the blast imparts
	# a radial impulse scaled from the bullet's knockback. Both are fractions an
	# effect/card can tune (e.g. a bigger-blast card might lower the damage factor
	# to 0.25); a `0.0` floor keeps a negative multiplier from inverting a blast.
	StatRegistry.register("explosion_damage_factor",    0.5, 0.0)  # × bullet damage
	StatRegistry.register("explosion_knockback_factor", 0.5, 0.0)  # × bullet knockback

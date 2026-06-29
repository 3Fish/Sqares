class_name ShotSpec extends RefCounted

## A mutable description of a shot, built by `Weapon` from its current stats and
## handed to pre-shoot card effects before any projectile spawns (#68).
##
## Effects mutate this spec in their `on_before_shoot(ctx)` hook — changing how
## many bullets fire, cancelling the shot, or overriding the per-bullet stats —
## and the weapon then fires according to the *final* spec. Effects run in
## pickup order (base-game effects first, then each picked card in the order it
## was selected), and they **stack**: each effect receives the running spec, so
## it sees every earlier effect's mutations and the next effect sees its own.
## That ordering reproduces the maintainer's worked example — a "bullets ×2"
## effect picked before a "bullets +2" effect yields 4 bullets, and the reverse
## pickup order yields 6.
##
## All bullets fire with the *same* spec (#68): `bullet_count` spawns that many
## identical projectiles in the aim direction; per-bullet variation (individual
## angles/speeds) is intentionally out of scope for now.
##
## Plain mutable fields plus the pure `fires()` predicate keep the spec scene-
## free and unit-testable, mirroring the rest of the combat helpers.

## How many identical projectiles to spawn. An effect may scale or add to this
## (the headline "fire 3 bullets instead of 1" case). A value of 0 (or less)
## means no projectile fires — the same outcome as `cancelled`.
var bullet_count: int = 1

## When true the shot is cancelled: no projectile spawns and the weapon does not
## consume its cooldown (a true no-op), so an effect such as "hold fire while
## charging" can fire the instant it stops cancelling rather than burning a shot.
## Note (#113): a cancelled shot still consumes `ammo_cost` rounds — cancel is a
## no-op for the *cooldown* but not for ammo, so an effect that wants a truly free
## cancel must also set `ammo_cost = 0`.
var cancelled: bool = false

## How many magazine rounds this shot consumes (#113). The effect chain may scale
## or add to it exactly like `bullet_count`, in pickup order — so a "×2 rounds"
## effect picked before a "+2 rounds" effect consumes 5, the reverse order 6. The
## shot is denied if the magazine can't cover this cost.
var ammo_cost: int = 1

## Seconds between pulling the trigger and the bullets actually spawning (#113).
## Default 0 fires immediately. The effect chain modifies it additively in pickup
## order (each effect gets the running value), matching the other shot attributes.
## The weapon's cooldown still starts at trigger time, not at the delayed spawn.
var delay: float = 0.0

# Per-bullet stats, seeded from the firing weapon and overridable before firing.
var damage: float = 25.0
var speed: float = 800.0
var scale: float = 1.0
var bounces: int = 0
var homing: float = 0.0
var lifesteal: float = 0.0
var knockback: float = 0.0
var explosion_radius: float = 0.0
## Explosion feel (#52), overridable per-shot like the other stats. The blast
## deals `explosion_damage_factor × damage` to splash victims and, when the
## bullet knocks back, a radial impulse of `explosion_knockback_factor ×
## knockback`. Defaults match the registered stat defaults (0.5).
var explosion_damage_factor: float = 0.5
var explosion_knockback_factor: float = 0.5
## Shield penetration (#138), overridable per-shot like the other stats. The
## fraction of damage the bullet lands through a raised shield (`0` = fully
## reflected). Default matches the registered stat default (0.0).
var shield_penetration: float = 0.0

## Friendly-fire multiplier (#112): scales the direct-hit damage dealt to a
## *same-team* target (an enemy always takes full damage regardless). `Weapon`
## seeds it from the match friendly-fire toggle — `1.0` when FF is on, `0.0` when
## off — and pre-shoot effects then reshape it in pickup order like every other
## shot attribute, so a card can grant "shots pass through teammates" (`0`),
## "reduced friendly fire" (`0.5`), or "harm everyone" (`> 0` while FF is off).
## Clamped to `>= 0` at the hit (no healing teammates); the default `1.0` keeps a
## bare `ShotSpec.new()` dealing full friendly damage.
var friendly_fire: float = 1.0


func _init(
	p_damage: float = 25.0,
	p_speed: float = 800.0,
	p_scale: float = 1.0,
	p_bounces: int = 0,
	p_homing: float = 0.0,
	p_lifesteal: float = 0.0,
	p_knockback: float = 0.0,
	p_explosion_radius: float = 0.0,
	p_explosion_damage_factor: float = 0.5,
	p_explosion_knockback_factor: float = 0.5,
	p_shield_penetration: float = 0.0,
	p_friendly_fire: float = 1.0,
) -> void:
	damage = p_damage
	speed = p_speed
	scale = p_scale
	bounces = p_bounces
	homing = p_homing
	lifesteal = p_lifesteal
	knockback = p_knockback
	explosion_radius = p_explosion_radius
	explosion_damage_factor = p_explosion_damage_factor
	explosion_knockback_factor = p_explosion_knockback_factor
	shield_penetration = p_shield_penetration
	friendly_fire = p_friendly_fire


## Whether this spec results in any projectile being fired. False when an effect
## cancelled the shot or drove the bullet count to zero. Pure so the fire/no-fire
## decision is unit-tested without a scene.
func fires() -> bool:
	return not cancelled and bullet_count > 0

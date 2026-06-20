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
var cancelled: bool = false

# Per-bullet stats, seeded from the firing weapon and overridable before firing.
var damage: float = 25.0
var speed: float = 800.0
var scale: float = 1.0
var bounces: int = 0
var homing: float = 0.0
var lifesteal: float = 0.0
var knockback: float = 0.0
var explosion_radius: float = 0.0


func _init(
	p_damage: float = 25.0,
	p_speed: float = 800.0,
	p_scale: float = 1.0,
	p_bounces: int = 0,
	p_homing: float = 0.0,
	p_lifesteal: float = 0.0,
	p_knockback: float = 0.0,
	p_explosion_radius: float = 0.0,
) -> void:
	damage = p_damage
	speed = p_speed
	scale = p_scale
	bounces = p_bounces
	homing = p_homing
	lifesteal = p_lifesteal
	knockback = p_knockback
	explosion_radius = p_explosion_radius


## Whether this spec results in any projectile being fired. False when an effect
## cancelled the shot or drove the bullet count to zero. Pure so the fire/no-fire
## decision is unit-tested without a scene.
func fires() -> bool:
	return not cancelled and bullet_count > 0

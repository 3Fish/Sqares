class_name AmmoModel extends RefCounted

## Pure, scene-free helpers for the weapon ammo model (#113).
##
## A weapon holds a magazine of discrete rounds. Firing draws down the magazine
## by the shot's `ammo_cost` (the per-shot consumption an effect chain computes on
## the `ShotSpec`); when the magazine can't cover the cost the shot is denied. The
## magazine refills on its own: once the player has not consumed ammo for
## `reload_time` seconds it snaps straight back to full (the reload is instant —
## the duration is just the idle time since the last shot, per the maintainer's
## answer on #113), and a fresh round always starts fully reloaded.
##
## All of that is expressed here as side-effect-free integer/float maths so the
## fire/deny/consume/reload decisions are unit-tested without a scene tree,
## mirroring `PhysicsModel` / `BlockHealth` / `MapBorder`.


## Whether a shot costing `ammo_cost` rounds may fire from a magazine currently
## holding `current_ammo`. A zero-or-negative cost never gates on ammo (an effect
## may make a shot free); otherwise the magazine must hold at least the cost
## (#113 A3: an over-cost shot is denied rather than fired partially).
static func can_fire(current_ammo: int, ammo_cost: int) -> bool:
	return ammo_cost <= 0 or current_ammo >= ammo_cost


## The magazine after a shot costing `ammo_cost` rounds. Clamped at zero so a
## (guarded) consumption never drives the count negative. A non-positive cost
## leaves the magazine untouched.
static func consume(current_ammo: int, ammo_cost: int) -> int:
	return maxi(current_ammo - maxi(ammo_cost, 0), 0)


## The magazine after `idle_time` seconds without firing. Once the idle time
## reaches `reload_time` the magazine is full again (instant refill, even from a
## partially-full magazine); before that it is unchanged. Already-full magazines
## (or a non-positive `reload_time`, treated as "always reloaded") are returned
## as-is, so this is idempotent once topped up.
static func reloaded(current_ammo: int, magazine_size: int, idle_time: float, reload_time: float) -> int:
	if current_ammo >= magazine_size:
		return current_ammo
	if idle_time >= reload_time:
		return magazine_size
	return current_ammo

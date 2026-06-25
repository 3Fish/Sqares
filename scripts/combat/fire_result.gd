class_name FireResult extends RefCounted

## The outcome of [method Weapon.try_fire], made an explicit tri-state so the
## netcode layer can tell an *accepted-but-delayed* shot apart from a *rejected*
## one (#121). Before this, `try_fire` returned the spawned projectile or `null`,
## and a scheduled delayed shot (#113, `delay > 0`) also returned `null` —
## indistinguishable from a refusal, so the host wrongly rejected a client's
## delayed shot instead of acking it.
##
## - [b]FIRED[/b]     — a projectile spawned this call; `projectile` is the first
##                      one (a multi-bullet shot returns its first bullet, exactly
##                      as the old `Projectile`-or-`null` return did).
## - [b]SCHEDULED[/b]  — the shot was accepted but its spawn is deferred by `delay`
##                      seconds (queued in the weapon's pending list); `delay`
##                      carries that wait so the host can ack the client with it.
## - [b]REJECTED[/b]   — nothing fired and nothing was scheduled (cooling down, no
##                      aim, cancelled by an effect, or out of ammo).
##
## Plain value type with pure predicates, so the contract is unit-testable
## without spawning anything.

enum Outcome { FIRED, SCHEDULED, REJECTED }

var outcome: int
## The spawned projectile for a FIRED result (the first bullet of a multi-shot);
## null for SCHEDULED / REJECTED.
var projectile: Projectile = null
## Seconds until a SCHEDULED shot spawns; 0.0 for FIRED / REJECTED.
var delay: float = 0.0


func _init(p_outcome: int, p_projectile: Projectile = null, p_delay: float = 0.0) -> void:
	outcome = p_outcome
	projectile = p_projectile
	delay = p_delay


static func fired(proj: Projectile) -> FireResult:
	return FireResult.new(Outcome.FIRED, proj)


static func scheduled(p_delay: float) -> FireResult:
	return FireResult.new(Outcome.SCHEDULED, null, p_delay)


static func rejected() -> FireResult:
	return FireResult.new(Outcome.REJECTED)


func is_fired() -> bool:
	return outcome == Outcome.FIRED


func is_scheduled() -> bool:
	return outcome == Outcome.SCHEDULED


func is_rejected() -> bool:
	return outcome == Outcome.REJECTED

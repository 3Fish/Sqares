class_name CardEffect extends RefCounted

## Base class for per-card custom effects (#20).
##
## A `Card` references one of these via its `effect` field. The `EffectEngine`
## attaches the effect to a player and invokes the lifecycle hooks below in
## response to round and combat events. Every hook is a no-op by default, so a
## concrete effect overrides only the moments it cares about.
##
## Each hook receives an `EffectContext` bundling the references relevant to
## that moment (player, weapon, projectile, target) plus an `event` dictionary
## of hook-specific scalars. See `docs/effect_engine.md` for the mod-author
## guide and worked examples.

## Optional stable identifier, mostly for debugging / inspection. Not required.
var id: String = ""


## Fired once, the moment the effect is attached to a player (e.g. when a losing
## player picks the card). Use it for one-shot stat grants — typically
## `ctx.player.apply_stats({...})`.
func on_apply(_ctx: EffectContext) -> void:
	pass


## Fired at the start of every round while the effect is active. Use it for
## per-round resets or bonuses that stack each round. `ctx.event.round` carries
## the round number.
func on_round_start(_ctx: EffectContext) -> void:
	pass


## Fired *before* the owning player's shot spawns, so an effect can reshape it:
## `ctx.shot` is a mutable `ShotSpec` carrying the bullet count, a `cancelled`
## flag, and the per-bullet stats. `ctx.weapon` is the firing weapon and
## `ctx.event.direction` the aim vector. Effects fire in pickup order and the
## same spec is threaded through each, so they **stack** — mutate `ctx.shot` in
## place (e.g. `ctx.shot.bullet_count += 2`, `ctx.shot.damage *= 1.5`, or
## `ctx.shot.cancelled = true`) and the next effect, and finally the weapon, see
## the result. Cancelling (or zeroing `bullet_count`) fires nothing and does not
## consume the weapon's cooldown.
func on_before_shoot(_ctx: EffectContext) -> void:
	pass


## Fired when the owning player fires a shot, immediately after the projectile
## spawns. `ctx.projectile` is the freshly spawned bullet (mutable),
## `ctx.weapon` the firing weapon, and `ctx.event.direction` the aim vector.
## With a multi-bullet shot (#68) this fires once per spawned bullet.
func on_shoot(_ctx: EffectContext) -> void:
	pass


## Fired when one of the owning player's projectiles strikes a target.
## `ctx.target` is what was hit, `ctx.projectile` the bullet, and
## `ctx.event.damage` the damage that was dealt.
func on_hit(_ctx: EffectContext) -> void:
	pass


## Fired when the owning player *takes* damage that reduces HP — the victim-side
## counterpart to `on_hit`. Use it for defensive / retaliation effects ("reflect
## damage when hit", "gain a shield on taking damage"). `ctx.player` is the
## victim, `ctx.target` is the attacker (may be `null` for sourceless damage such
## as a kill zone), and `ctx.event.damage` is the HP actually lost. Does not fire
## when a hit is fully absorbed by a shield charge (no HP is lost).
func on_take_damage(_ctx: EffectContext) -> void:
	pass

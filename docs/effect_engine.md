# Effect Engine — mod author guide

The effect engine lets a card run **arbitrary code** in response to game events,
rather than only applying flat stat deltas. A card references a single
`CardEffect`; when the card is picked, the `EffectEngine` attaches that effect to
the player and calls its lifecycle hooks as rounds and combat unfold.

This is the public API third-party mods build on. It mirrors the existing
registry-autoload pattern (`StatRegistry`, `CardRegistry`).

## The pieces

| Type            | File                                  | Role                                            |
| --------------- | ------------------------------------- | ----------------------------------------------- |
| `CardEffect`    | `scripts/effects/effect.gd`           | Base class you subclass; defines the hooks.     |
| `EffectContext` | `scripts/effects/effect_context.gd`   | Data bundle passed to every hook.               |
| `EffectEngine`  | `scripts/effects/effect_engine.gd`    | Autoload that attaches effects and dispatches.  |

## Hooks

Subclass `CardEffect` and override only the hooks you need — each one is a no-op
by default.

| Hook              | Fires when…                                            | Useful context fields                          |
| ----------------- | ------------------------------------------------------ | ---------------------------------------------- |
| `on_apply`        | the effect is first attached to a player (card picked) | `player`                                       |
| `on_round_start`  | every round begins, while the effect is active         | `player`, `event.round`                        |
| `on_shoot`        | the owning player fires, just after the bullet spawns  | `player`, `weapon`, `projectile`, `event.direction` |
| `on_hit`          | one of the player's projectiles strikes a target       | `player`, `projectile`, `target`, `event.damage`    |

Every hook receives one `EffectContext` argument. Unused fields are `null`;
`event` is a small `Dictionary` of hook-specific scalars (read it with
`ctx.get_event(key, fallback)`).

## Writing an effect

```gdscript
# my_mod/effects/momentum.gd
class_name MomentumEffect extends CardEffect

## +20 move speed each round, and a damage bump while moving fast.
func on_round_start(ctx: EffectContext) -> void:
    ctx.player.apply_stats({"move_speed": ctx.player.stats.get_stat("move_speed") + 20.0})

func on_hit(ctx: EffectContext) -> void:
    # Bonus damage handled here, e.g. spawn a follow-up, heal, etc.
    pass
```

## Attaching an effect to a card

Set the card's `effect` to an instance of your subclass when you register it from
your mod's `_on_load()`:

```gdscript
func _on_load() -> void:
    var card := Card.new()
    card.id = "momentum"
    card.display_name = "Momentum"
    card.description = "Faster every round."
    card.effect = MomentumEffect.new()
    register_card(card)
```

The card-pick flow (#17) then calls `EffectEngine.apply_effect(player, card.effect)`
when a losing player selects the card, which fires `on_apply` and registers the
effect for all later hooks.

## Triggering and lifetime

You normally do **not** call the engine yourself — the base game wires the
triggers for you:

- `Weapon` calls `EffectEngine.notify_shoot(...)` after spawning each bullet.
- `Projectile` calls `EffectEngine.notify_hit(...)` on impact.
- `GameManager.round_started` is fanned out to every effect's `on_round_start`.

Effects **persist across rounds** by design (the rogue-like accumulates picks).
The engine exposes `remove_effect`, `clear_player`, and `clear` for match resets
and tests.

## Duck typing

Hooks are dispatched by name and only if present, so an effect need not extend
`CardEffect` — any object exposing the relevant `on_*` methods works. Subclassing
`CardEffect` is still recommended for the documented defaults and editor support.

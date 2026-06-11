class_name StatCardEffect extends CardEffect

## A data-driven CardEffect that grants additive stat bonuses when its card is
## picked. This is the workhorse behind the base-game card set (#18): most
## rogue-like cards are simply a bundle of "+N stat" deltas applied once, at
## pick time, and accumulated across rounds.
##
## Deltas are applied additively (via `PlayerStats.modify_stat`) so repeated
## picks of the same card stack, matching the rogue-like accumulation intent
## (#43 — stats persist across rounds). After mutating the stat bag the effect
## re-syncs the player's components with `apply_stats({})` (an empty merge
## recomputes Health/Weapon from the current stats without overwriting them).
##
## The owning player must expose a `stats` (a `PlayerStats`) and an
## `apply_stats` method — the real `Player` provides both. Effects are
## duck-typed by the engine, so a lightweight stub satisfying that contract
## works in tests.

## stat_name (String) -> additive delta (float).
var deltas: Dictionary = {}


func _init(p_deltas: Dictionary = {}, p_id: String = "") -> void:
	deltas = p_deltas
	id = p_id


func on_apply(ctx: EffectContext) -> void:
	var player: Object = ctx.player
	if player == null:
		return
	var bag: Object = player.get("stats")
	if bag == null:
		push_error("StatCardEffect: player '%s' exposes no 'stats' to modify." % str(player))
		return
	for stat_name in deltas:
		bag.modify_stat(stat_name, float(deltas[stat_name]))
	# Empty merge re-syncs Health / Weapon from the freshly mutated stat bag.
	player.apply_stats({})

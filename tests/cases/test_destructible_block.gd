extends TestCase

## Tests for the Destructible flag on platform blocks (#97). The size-derived
## health maths live in the pure `BlockHealth` / `PhysicsModel`; the ArenaData
## flag round-trips and combines independently with `physics`; the builder
## dispatches the four flag combinations; and the block nodes take damage and
## emit a destroy event at zero health. Scene-tree-free where possible per
## `CLAUDE.md`.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")
const Model = preload("res://scripts/physics/physics_model.gd")
const Health = preload("res://scripts/physics/block_health.gd")


# --- Pure health model (BlockHealth) ----------------------------------------

func _test_health_derives_from_size_via_shared_model() -> void:
	var size := Vector2(200, 24)
	var h: BlockHealth = Health.new(size)
	assert_almost_eq(h.max_health, Model.block_health(size), "health from the shared formula")
	assert_almost_eq(h.health, h.max_health, "starts at full health")
	assert_false(h.is_destroyed(), "a fresh block is not destroyed")


func _test_taking_partial_damage_reduces_health_without_destroying() -> void:
	var h: BlockHealth = Health.new(Vector2(400, 400))  # large area -> plenty of health
	var before := h.health
	var destroyed := h.take(before * 0.25)
	assert_false(destroyed, "a partial hit does not destroy")
	assert_almost_eq(h.health, before * 0.75, "health reduced by the damage")


func _test_health_reaching_zero_reports_destroyed() -> void:
	var h: BlockHealth = Health.new(Vector2(100, 100))
	var destroyed := h.take(h.max_health)
	assert_true(destroyed, "exact-lethal damage destroys")
	assert_true(h.is_destroyed(), "and the block reads as destroyed")
	assert_almost_eq(h.health, 0.0, "health floored at zero")


func _test_overkill_floors_at_zero_and_stays_destroyed() -> void:
	var h: BlockHealth = Health.new(Vector2(100, 100))
	assert_true(h.take(h.max_health * 10.0), "overkill destroys")
	assert_almost_eq(h.health, 0.0, "health never goes negative")
	assert_true(h.take(5.0), "already-destroyed stays destroyed")


func _test_negative_damage_is_ignored() -> void:
	var h: BlockHealth = Health.new(Vector2(100, 100))
	var before := h.health
	assert_false(h.take(-50.0), "negative damage neither heals nor destroys")
	assert_almost_eq(h.health, before, "health unchanged by negative damage")


# --- ArenaData flag (independent of, and combinable with, physics) ----------

func _test_platform_defaults_to_non_destructible() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))
	assert_false(bool(data.platforms[0].get("destructible", false)), "default platform is indestructible")


func _test_flags_round_trip_independently_through_json() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))                                 # neither
	data.add_platform(Vector2(0, 50), Vector2(64, 64), Color.WHITE, true, false)       # physics only
	data.add_platform(Vector2(0, 100), Vector2(64, 64), Color.WHITE, false, true)      # destructible only
	data.add_platform(Vector2(0, 150), Vector2(64, 64), Color.WHITE, true, true)       # both

	var restored := ArenaDataScript.from_dict(data.to_dict())
	assert_eq(restored.platforms.size(), 4, "all platforms survive serialisation")
	assert_false(bool(restored.platforms[0]["destructible"]), "neither: not destructible")
	assert_false(bool(restored.platforms[1]["destructible"]), "physics-only: not destructible")
	assert_true(bool(restored.platforms[1]["physics"]), "physics-only: physics preserved")
	assert_true(bool(restored.platforms[2]["destructible"]), "destructible-only: destructible preserved")
	assert_false(bool(restored.platforms[2]["physics"]), "destructible-only: not physics")
	assert_true(bool(restored.platforms[3]["physics"]) and bool(restored.platforms[3]["destructible"]), "both flags preserved together")


# --- ArenaBuilder dispatch over the four flag combinations ------------------

func _test_builder_plain_platform_is_static_and_indestructible() -> void:
	var arena := _arena_with(false, false)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is StaticBody2D, "plain platform is a StaticBody2D")
	assert_false(p0 is DestructibleBlock, "and not a DestructibleBlock")
	assert_false(p0 is PhysicsBlock, "and not a PhysicsBlock")
	arena.free()


func _test_builder_destructible_only_is_a_static_destructible_block() -> void:
	var arena := _arena_with(false, true)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is DestructibleBlock, "destructible-only is a DestructibleBlock")
	assert_true(p0 is StaticBody2D, "which is a static body (not pushable)")
	assert_false(p0.has_method("receive_push"), "static destructible block takes no impulse")
	arena.free()


func _test_builder_physics_only_block_is_indestructible() -> void:
	var arena := _arena_with(true, false)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is PhysicsBlock, "physics-only is a PhysicsBlock")
	assert_false(p0.is_destructible(), "physics-only block is indestructible")
	arena.free()


func _test_builder_physics_and_destructible_block_is_both() -> void:
	var arena := _arena_with(true, true)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is PhysicsBlock, "physics+destructible is a PhysicsBlock")
	assert_true(p0.has_method("receive_push"), "and is pushable")
	assert_true(p0.is_destructible(), "and is destructible")
	arena.free()


# --- Helpers ----------------------------------------------------------------

## Builds a one-platform arena whose single block carries the given flags.
func _arena_with(physics: bool, destructible: bool) -> Arena:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, physics, destructible)
	return ArenaBuilder.build(data)


# --- DestructibleBlock node (static) ----------------------------------------

func _test_destructible_block_health_from_size() -> void:
	var block := DestructibleBlock.new()
	block.configure(Vector2(120, 40))
	assert_almost_eq(block.health(), Model.block_health(Vector2(120, 40)), "health from shared model")
	assert_false(block.is_destroyed(), "fresh block is alive")
	block.free()


func _test_destructible_block_destroyed_at_zero_health_emits_event() -> void:
	var block := DestructibleBlock.new()
	block.configure(Vector2(100, 100))
	var seen := [false]
	block.destroyed.connect(func(_b): seen[0] = true)
	# One overkill hit drives health to zero.
	block.damage_block(block.health() + 100.0)
	assert_true(block.is_destroyed(), "block is destroyed")
	assert_true(seen[0], "destroy event emitted")
	# Destroying already called queue_free(); the harness flushes the deletion
	# queue at end-of-run, so we must not free() it again here.


func _test_destructible_block_survives_a_partial_hit() -> void:
	var block := DestructibleBlock.new()
	block.configure(Vector2(400, 400))  # large -> survives a single 25-damage shot
	var before := block.health()
	block.damage_block(25.0)
	assert_false(block.is_destroyed(), "still standing after a partial hit")
	assert_almost_eq(block.health(), before - 25.0, "health reduced by the shot")
	block.free()


# --- Destructible PhysicsBlock ----------------------------------------------

func _test_physics_block_not_destructible_ignores_damage() -> void:
	var block := PhysicsBlock.new()
	block.configure(Vector2(64, 64))
	assert_false(block.is_destructible(), "physics-only block has no health")
	block.damage_block(9999.0)  # no-op, must not error or destroy
	assert_false(block.is_destroyed(), "indestructible block is never destroyed")
	block.free()


func _test_physics_block_made_destructible_takes_damage_and_destroys() -> void:
	var block := PhysicsBlock.new()
	block.configure(Vector2(80, 80))
	block.make_destructible()
	assert_true(block.is_destructible(), "now carries health")
	assert_almost_eq(block.health(), Model.block_health(Vector2(80, 80)), "health from shared model")
	var seen := [false]
	block.destroyed.connect(func(_b): seen[0] = true)
	block.damage_block(block.health())
	assert_true(block.is_destroyed(), "destroyed at zero health")
	assert_true(seen[0], "destroy event emitted")
	# queue_free() already requested; do not free() again (see note above).


# --- Destruction SFX hook (#103) --------------------------------------------
# Destroying a block fires the BLOCK_DESTROYED cue through SfxDirector, mirroring
# how Player fires DEATH and Projectile fires HIT at their own trigger sites. The
# director records the requested cue in `last_cue()` whether or not a stream is
# registered, so these assert the hook fires (and only on actual destruction)
# without standing up the audio playback pool.

func _clear_last_cue() -> void:
	# Isolate from cues left by earlier tests / autoload wiring.
	SfxDirector._last_cue = ""


func _test_destroying_a_static_block_fires_the_block_destroyed_cue() -> void:
	_clear_last_cue()
	var block := DestructibleBlock.new()
	block.configure(Vector2(100, 100))
	block.damage_block(block.health() + 100.0)  # overkill -> destroyed
	assert_eq(SfxDirector.last_cue(), SfxDirector.BLOCK_DESTROYED, "destruction fires the block-destroyed cue")
	# queue_free() already requested; do not free() again.


func _test_surviving_a_hit_fires_no_destruction_cue() -> void:
	_clear_last_cue()
	var block := DestructibleBlock.new()
	block.configure(Vector2(400, 400))  # large -> survives a single small hit
	block.damage_block(25.0)
	assert_false(block.is_destroyed(), "still standing after a partial hit")
	assert_eq(SfxDirector.last_cue(), "", "a survivable hit fires no cue")
	block.free()


func _test_destroying_a_destructible_physics_block_fires_the_cue() -> void:
	_clear_last_cue()
	var block := PhysicsBlock.new()
	block.configure(Vector2(80, 80))
	block.make_destructible()
	block.damage_block(block.health() + 100.0)  # overkill -> destroyed
	assert_eq(SfxDirector.last_cue(), SfxDirector.BLOCK_DESTROYED, "destruction fires the block-destroyed cue")
	# queue_free() already requested; do not free() again.


func _test_indestructible_physics_block_fires_no_cue() -> void:
	_clear_last_cue()
	var block := PhysicsBlock.new()
	block.configure(Vector2(64, 64))  # physics-only, no health
	block.damage_block(9999.0)  # no-op on an indestructible block
	assert_false(block.is_destroyed(), "indestructible block is never destroyed")
	assert_eq(SfxDirector.last_cue(), "", "damaging an indestructible block fires no cue")
	block.free()

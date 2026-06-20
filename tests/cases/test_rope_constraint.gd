extends TestCase

## Tests for the Chain/Rope constraint object (#98). The maximum-length distance
## constraint maths live in the pure, scene-free `RopeConstraint`; `ArenaData`
## round-trips ropes through JSON; and `ArenaBuilder` builds a `Rope` node that
## resolves its endpoints, derives inverse masses from the merged physics model,
## stays decorative without a physics endpoint, and severs when a destructible
## endpoint is destroyed. Scene-tree-free where possible per `CLAUDE.md`.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")
const Constraint = preload("res://scripts/physics/rope_constraint.gd")
const Model = preload("res://scripts/physics/physics_model.gd")


# --- Pure constraint: over-extension / taut ---------------------------------

func _test_slack_rope_has_no_over_extension() -> void:
	# 100 apart, but the rope is 150 long -> slack.
	assert_almost_eq(Constraint.over_extension(Vector2.ZERO, Vector2(0, 100), 150.0), 0.0, "slack rope")
	assert_false(Constraint.is_taut(Vector2.ZERO, Vector2(0, 100), 150.0), "slack rope is not taut")


func _test_taut_rope_reports_over_extension() -> void:
	# 100 apart with an 80-long rope -> stretched by 20.
	assert_almost_eq(Constraint.over_extension(Vector2.ZERO, Vector2(0, 100), 80.0), 20.0, "stretched by 20")
	assert_true(Constraint.is_taut(Vector2.ZERO, Vector2(0, 100), 80.0), "stretched rope is taut")


# --- Pure constraint: position solve ----------------------------------------

func _test_slack_rope_applies_no_correction() -> void:
	var c := Constraint.solve(Vector2.ZERO, Vector2(0, 100), 1.0, 1.0, 150.0)
	assert_eq(c["a"], Vector2.ZERO, "slack: a unmoved")
	assert_eq(c["b"], Vector2.ZERO, "slack: b unmoved")


func _test_world_anchor_endpoint_takes_all_the_correction() -> void:
	# Anchor a (inv mass 0) is fixed; the whole 20px pull lands on block b.
	var c := Constraint.solve(Vector2.ZERO, Vector2(0, 100), Constraint.FIXED_INV_MASS, 0.5, 80.0)
	assert_eq(c["a"], Vector2.ZERO, "fixed anchor never moves")
	assert_almost_eq(c["b"].y, -20.0, "block pulled inward by the full over-extension")
	assert_almost_eq(c["b"].x, 0.0, "no off-axis correction")


func _test_block_to_block_splits_correction_by_inverse_mass() -> void:
	# Equal inverse mass -> the 20px gap closes 10/10.
	var c := Constraint.solve(Vector2.ZERO, Vector2(0, 100), 0.5, 0.5, 80.0)
	assert_almost_eq(c["a"].y, 10.0, "a moves toward b by half")
	assert_almost_eq(c["b"].y, -10.0, "b moves toward a by half")
	# A heavier b (smaller inverse mass) moves less than a lighter a.
	var uneven := Constraint.solve(Vector2.ZERO, Vector2(0, 100), 0.75, 0.25, 80.0)
	assert_true(absf(uneven["a"].y) > absf(uneven["b"].y), "lighter endpoint moves more")
	assert_almost_eq(absf(uneven["a"].y) + absf(uneven["b"].y), 20.0, "together they close the full gap")


func _test_two_fixed_endpoints_cannot_move() -> void:
	var c := Constraint.solve(Vector2.ZERO, Vector2(0, 100), 0.0, 0.0, 50.0)
	assert_eq(c["a"], Vector2.ZERO, "both fixed: a unmoved")
	assert_eq(c["b"], Vector2.ZERO, "both fixed: b unmoved")


func _test_coincident_endpoints_are_safe() -> void:
	# No defined direction; must not divide by zero.
	var c := Constraint.solve(Vector2(5, 5), Vector2(5, 5), 1.0, 1.0, 10.0)
	assert_eq(c["a"], Vector2.ZERO, "coincident endpoints: no correction")
	assert_eq(c["b"], Vector2.ZERO, "coincident endpoints: no correction")


# --- Pure constraint: velocity correction -----------------------------------

func _test_velocity_correction_cancels_separating_speed() -> void:
	# b moving away from a along the rope; the anchor is fixed so b loses it all.
	var c := Constraint.velocity_correction(
		Vector2.ZERO, Vector2(0, 100), Vector2.ZERO, Vector2(0, 50),
		Constraint.FIXED_INV_MASS, 0.5)
	assert_almost_eq(c["b"].y, -50.0, "separating velocity removed from b")
	assert_eq(c["a"], Vector2.ZERO, "fixed anchor velocity unchanged")


func _test_velocity_correction_ignores_approaching_endpoints() -> void:
	# b moving toward a -> the rope is going slack, it must not resist.
	var c := Constraint.velocity_correction(
		Vector2.ZERO, Vector2(0, 100), Vector2.ZERO, Vector2(0, -50),
		Constraint.FIXED_INV_MASS, 0.5)
	assert_eq(c["a"], Vector2.ZERO, "approaching: no correction")
	assert_eq(c["b"], Vector2.ZERO, "approaching: no correction")


# --- ArenaData ropes round-trip ---------------------------------------------

func _test_arena_has_no_ropes_by_default() -> void:
	assert_eq(ArenaDataScript.new().ropes.size(), 0, "no ropes by default")


func _test_ropes_round_trip_through_json_in_all_endpoint_combinations() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)   # physics block 0
	data.add_platform(Vector2(100, 0), Vector2(64, 64))                            # static block 1
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO, 180.0)                     # anchor <-> block
	data.add_rope(0, Vector2.ZERO, 1, Vector2.ZERO)                                # block <-> block (auto length)
	data.add_rope(-1, Vector2(-50, -50), -1, Vector2(50, -50))                      # anchor <-> anchor

	var restored := ArenaDataScript.from_json(data.to_json())
	assert_not_null(restored, "json parsed back to an arena")
	assert_eq(restored.ropes.size(), 3, "all ropes survive the round-trip")

	assert_eq(int(restored.ropes[0]["a_block"]), -1, "anchor endpoint preserved")
	assert_eq(restored.ropes[0]["a_anchor"], Vector2(0, -200), "anchor point preserved")
	assert_eq(int(restored.ropes[0]["b_block"]), 0, "block endpoint preserved")
	assert_almost_eq(float(restored.ropes[0]["length"]), 180.0, "explicit length preserved")

	assert_eq(int(restored.ropes[1]["a_block"]), 0, "block <-> block: a")
	assert_eq(int(restored.ropes[1]["b_block"]), 1, "block <-> block: b")
	assert_almost_eq(float(restored.ropes[1]["length"]), -1.0, "auto length preserved as negative")

	assert_eq(int(restored.ropes[2]["a_block"]), -1, "anchor <-> anchor: a")
	assert_eq(int(restored.ropes[2]["b_block"]), -1, "anchor <-> anchor: b")
	assert_eq(restored.ropes[2]["b_anchor"], Vector2(50, -50), "second anchor preserved")


func _test_remove_rope_drops_the_entry() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_rope(-1, Vector2(0, -100), -1, Vector2(0, 100))
	data.remove_rope(0)
	assert_eq(data.ropes.size(), 0, "rope removed")
	data.remove_rope(5)  # out of range: must be a safe no-op
	assert_eq(data.ropes.size(), 0, "out-of-range remove is a no-op")


# --- ArenaBuilder / Rope node -----------------------------------------------

func _test_builder_resolves_block_endpoint_and_bakes_length() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)  # physics block 0
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)                          # auto length
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	# Length baked from the initial 200px separation between anchor and block.
	assert_almost_eq(rope.rope_length, 200.0, "auto length baked from endpoint separation")
	assert_false(rope.is_decorative(), "a physics-block endpoint makes the rope a real constraint")
	arena.free()


func _test_rope_between_two_static_blocks_is_decorative() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(-50, 0), Vector2(64, 64))   # static block 0
	data.add_platform(Vector2(50, 0), Vector2(64, 64))    # static block 1
	data.add_rope(0, Vector2.ZERO, 1, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	assert_true(rope.is_decorative(), "no physics endpoint -> decorative (no forces)")
	arena.free()


func _test_constraint_pulls_a_hanging_physics_block_back_to_length() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)  # physics block 0
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	var block := arena.get_node("Platform0") as PhysicsBlock
	# Shorten the rope so the block (200px from the anchor) is over-extended by
	# 100px; one constraint pass must pull it inward to exactly the rope length.
	rope.rope_length = 100.0
	rope._apply_constraint()
	assert_almost_eq(block.position.y, -100.0, "block pulled up to the rope length")
	assert_almost_eq(block.position.x, 0.0, "no sideways drift")
	assert_almost_eq(block.position.distance_to(Vector2(0, -200)), 100.0, "now exactly one rope length from the anchor")
	arena.free()


func _test_destroying_a_destructible_endpoint_severs_the_rope() -> void:
	var data: ArenaData = ArenaDataScript.new()
	# A physics + destructible block hung from a mid-air anchor.
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, true)
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	assert_false(rope.is_severed(), "rope starts intact")
	var block := arena.get_node("Platform0") as PhysicsBlock
	# Overkill the block: it emits `destroyed`, which the rope consumes to sever.
	block.damage_block(block.health() + 100.0)
	assert_true(rope.is_severed(), "destroying the endpoint severs the rope")
	# The block queue_free()'d itself; defer the arena's deletion too so both go
	# through the harness's deletion-queue flush (no immediate double-free of the
	# already-queued child).
	arena.queue_free()


func _test_world_anchor_endpoint_never_severs() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)
	data.add_rope(-1, Vector2(0, -200), -1, Vector2(0, 200))  # anchor <-> anchor
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	# Anchors are not destructible and the rope has no physics endpoint, so it is
	# inert decoration that never severs.
	assert_false(rope.is_severed(), "anchors never sever")
	assert_true(rope.is_decorative(), "anchor <-> anchor rope is decorative")
	arena.free()


# --- Sever SFX hook (#104, deferred from #98) -------------------------------
# Severing a rope fires the ROPE_SEVERED cue through SfxDirector — a discrete
# "the rope snaps" event, distinct from the endpoint block's own destruction —
# mirroring how Player fires DEATH and Weapon fires SHOOT at their own trigger
# sites. Like every cue it warns-and-no-ops until a mod registers a stream (no
# audio ships, #47), so these assert the hook fires (and only on a genuine, first
# sever) via SfxDirector.last_cue() without standing up the audio playback pool.

func _clear_last_cue() -> void:
	# Isolate from cues left by earlier tests / autoload wiring.
	SfxDirector._last_cue = ""


func _test_severing_a_rope_fires_the_rope_severed_cue() -> void:
	var data: ArenaData = ArenaDataScript.new()
	# A physics + destructible block hung from a mid-air anchor.
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, true)
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	var block := arena.get_node("Platform0") as PhysicsBlock
	_clear_last_cue()
	# Overkill the block: it emits `destroyed`, the rope consumes it and snaps.
	block.damage_block(block.health() + 100.0)
	assert_true(rope.is_severed(), "destroying the endpoint severs the rope")
	assert_eq(SfxDirector.last_cue(), SfxDirector.ROPE_SEVERED, "severing fires the rope-severed cue")
	arena.queue_free()


func _test_an_intact_rope_fires_no_sever_cue() -> void:
	var data: ArenaData = ArenaDataScript.new()
	# Anchor <-> anchor: not destructible, never severs.
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)
	data.add_rope(-1, Vector2(0, -200), -1, Vector2(0, 200))
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	_clear_last_cue()
	# Nothing destroys an endpoint, so no sever and no cue.
	assert_false(rope.is_severed(), "an intact rope has not severed")
	assert_eq(SfxDirector.last_cue(), "", "no sever, no cue")
	arena.free()


func _test_a_second_endpoint_destruction_does_not_refire_the_cue() -> void:
	var data: ArenaData = ArenaDataScript.new()
	# A block <-> block rope where BOTH endpoints are physics + destructible, so
	# this seam is connected to both `destroyed` signals.
	data.add_platform(Vector2(-50, 0), Vector2(64, 64), Color.WHITE, true, true)  # block 0
	data.add_platform(Vector2(50, 0), Vector2(64, 64), Color.WHITE, true, true)   # block 1
	data.add_rope(0, Vector2.ZERO, 1, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	var block0 := arena.get_node("Platform0") as PhysicsBlock
	var block1 := arena.get_node("Platform1") as PhysicsBlock
	_clear_last_cue()
	block0.damage_block(block0.health() + 100.0)  # first sever fires the cue
	assert_eq(SfxDirector.last_cue(), SfxDirector.ROPE_SEVERED, "first endpoint destruction snaps the rope")
	_clear_last_cue()
	block1.damage_block(block1.health() + 100.0)  # already severed -> no re-fire
	assert_true(rope.is_severed(), "rope stays severed")
	assert_eq(SfxDirector.last_cue(), "", "the already-snapped rope does not re-fire the cue")
	arena.queue_free()

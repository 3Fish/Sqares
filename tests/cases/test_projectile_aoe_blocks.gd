extends TestCase

## Explosion AoE reaching destructible blocks (#103, follow-up to #97). A bullet's
## blast already damages nearby players via `Projectile._detonate`; this extends it
## to destructible blocks. The selection maths live in the pure, scene-free
## `Projectile.blast_targets_in_radius`; destructible blocks join
## `Projectile.DESTRUCTIBLE_GROUP` at build time so the live sweep finds them; and
## `damage_blocks_in_blast` applies the bullet damage to the selected blocks.
## Scene-tree-free where possible per `CLAUDE.md` (the headless `--script` runner
## makes `get_tree()` unavailable, so the live group sweep itself is boot-verified,
## exactly like the existing player sweep).

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")


# --- Pure selection: blast_targets_in_radius --------------------------------

func _test_blast_selects_only_nodes_within_radius() -> void:
	var inside := Node2D.new()
	inside.position = Vector2(50, 0)
	var outside := Node2D.new()
	outside.position = Vector2(300, 0)
	var hit := Projectile.blast_targets_in_radius([inside, outside], Vector2.ZERO, 100.0, null)
	assert_eq(hit.size(), 1, "only the in-radius node is selected")
	assert_true(hit.has(inside), "in-radius node selected")
	assert_false(hit.has(outside), "out-of-radius node excluded")
	inside.free()
	outside.free()


func _test_blast_excludes_the_direct_target() -> void:
	var direct := Node2D.new()
	direct.position = Vector2(10, 0)
	var other := Node2D.new()
	other.position = Vector2(20, 0)
	var hit := Projectile.blast_targets_in_radius([direct, other], Vector2.ZERO, 100.0, direct)
	assert_false(hit.has(direct), "direct target (already hit) is excluded")
	assert_true(hit.has(other), "other in-radius node still selected")
	direct.free()
	other.free()


func _test_blast_edge_is_inclusive_and_zero_radius_selects_nothing() -> void:
	var edge := Node2D.new()
	edge.position = Vector2(100, 0)  # exactly one radius away
	assert_eq(Projectile.blast_targets_in_radius([edge], Vector2.ZERO, 100.0, null).size(), 1,
		"a node exactly on the blast edge is included")
	assert_eq(Projectile.blast_targets_in_radius([edge], Vector2.ZERO, 0.0, null).size(), 0,
		"a zero-radius blast selects nothing")
	edge.free()


func _test_blast_skips_non_node2d_and_empty_candidates() -> void:
	assert_eq(Projectile.blast_targets_in_radius([RefCounted.new()], Vector2.ZERO, 100.0, null).size(), 0,
		"non-Node2D candidates are ignored, not crashed on")
	assert_eq(Projectile.blast_targets_in_radius([], Vector2.ZERO, 100.0, null).size(), 0,
		"no candidates -> no targets")


# --- Group membership: destructible blocks join the AoE group ---------------

func _test_destructible_blocks_join_the_blast_group_others_do_not() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64))                              # 0: plain static
	data.add_platform(Vector2(100, 0), Vector2(64, 64), Color.WHITE, true, false) # 1: physics only
	data.add_platform(Vector2(200, 0), Vector2(64, 64), Color.WHITE, false, true) # 2: destructible static
	data.add_platform(Vector2(300, 0), Vector2(64, 64), Color.WHITE, true, true)  # 3: physics + destructible
	var arena := ArenaBuilder.build(data)

	assert_false(arena.get_node("Platform0").is_in_group(Projectile.DESTRUCTIBLE_GROUP),
		"a plain static platform is not in the blast group")
	assert_false(arena.get_node("Platform1").is_in_group(Projectile.DESTRUCTIBLE_GROUP),
		"a physics-only (indestructible) block is not in the blast group")
	assert_true(arena.get_node("Platform2").is_in_group(Projectile.DESTRUCTIBLE_GROUP),
		"a destructible static block joins the blast group")
	assert_true(arena.get_node("Platform3").is_in_group(Projectile.DESTRUCTIBLE_GROUP),
		"a physics + destructible block joins the blast group")
	arena.free()


func _test_physics_blocks_join_the_push_group_others_do_not() -> void:
	# Mirrors the destructible-group test for the AoE *push* sweep (#52 A3): only
	# pushable physics blocks join PHYSICS_GROUP, regardless of destructibility.
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64))                              # 0: plain static
	data.add_platform(Vector2(100, 0), Vector2(64, 64), Color.WHITE, true, false) # 1: physics only
	data.add_platform(Vector2(200, 0), Vector2(64, 64), Color.WHITE, false, true) # 2: destructible static
	data.add_platform(Vector2(300, 0), Vector2(64, 64), Color.WHITE, true, true)  # 3: physics + destructible
	var arena := ArenaBuilder.build(data)

	assert_false(arena.get_node("Platform0").is_in_group(Projectile.PHYSICS_GROUP),
		"a plain static platform is not in the push group")
	assert_true(arena.get_node("Platform1").is_in_group(Projectile.PHYSICS_GROUP),
		"a physics-only block joins the push group")
	assert_false(arena.get_node("Platform2").is_in_group(Projectile.PHYSICS_GROUP),
		"a destructible static (immovable) block is not in the push group")
	assert_true(arena.get_node("Platform3").is_in_group(Projectile.PHYSICS_GROUP),
		"a physics + destructible block joins the push group")
	arena.free()


# --- Dispatch: damage_blocks_in_blast damages the right blocks ---------------

func _test_blast_damages_in_range_blocks_and_spares_out_of_range() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, false, true)    # 0: in range
	data.add_platform(Vector2(80, 0), Vector2(64, 64), Color.WHITE, true, true)    # 1: in range (physics + destructible)
	data.add_platform(Vector2(400, 0), Vector2(64, 64), Color.WHITE, false, true)  # 2: out of range
	var arena := ArenaBuilder.build(data)
	var b_in_static := arena.get_node("Platform0")
	var b_in_physics := arena.get_node("Platform1")
	var b_out := arena.get_node("Platform2")

	var proj: Projectile = Projectile.new()
	proj.damage = 1000.0          # plenty to destroy a 64x64 block (health ~4)
	proj.explosion_radius = 150.0
	# Center at the origin: blocks 0 and 1 are within 150px, block 2 is not.
	proj.damage_blocks_in_blast([b_in_static, b_in_physics, b_out], Vector2.ZERO, null)

	assert_true(b_in_static.is_destroyed(), "in-range destructible static block is destroyed by the blast")
	assert_true(b_in_physics.is_destroyed(), "in-range physics+destructible block is destroyed by the blast")
	assert_false(b_out.is_destroyed(), "out-of-range block is untouched by the blast")

	proj.free()
	# Destroyed blocks queue_free()'d themselves; defer the arena so both go through
	# the harness's deletion-queue flush (no immediate double-free of a queued child).
	arena.queue_free()


func _test_blast_skips_the_direct_target_block() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, false, true)   # 0: the direct target
	data.add_platform(Vector2(40, 0), Vector2(64, 64), Color.WHITE, false, true)  # 1: a splash neighbour
	var arena := ArenaBuilder.build(data)
	var direct := arena.get_node("Platform0")
	var neighbour := arena.get_node("Platform1")

	var proj: Projectile = Projectile.new()
	proj.damage = 1000.0
	proj.explosion_radius = 150.0
	proj.damage_blocks_in_blast([direct, neighbour], Vector2.ZERO, direct)

	assert_false(direct.is_destroyed(), "the directly-hit block is not double-damaged by its own blast")
	assert_true(neighbour.is_destroyed(), "the neighbouring block still takes blast damage")

	proj.free()
	arena.queue_free()

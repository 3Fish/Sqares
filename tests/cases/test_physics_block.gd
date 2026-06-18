extends TestCase

## Tests for the Physics flag on platform blocks (#96): the ArenaData flag
## round-trips, the builder produces a pushable PhysicsBlock when set, and the
## block derives its mass + collision wiring from the shared model.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")
const Model = preload("res://scripts/physics/physics_model.gd")


# --- ArenaData flag ---------------------------------------------------------

func _test_platform_defaults_to_non_physics() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))
	assert_false(bool(data.platforms[0].get("physics", false)), "default platform is static")


func _test_physics_flag_round_trips_through_json() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))                       # static
	data.add_platform(Vector2(0, 50), Vector2(64, 64), Color.WHITE, true)    # physics

	var restored := ArenaDataScript.from_dict(data.to_dict())
	assert_eq(restored.platforms.size(), 2, "both platforms survive serialisation")
	assert_false(bool(restored.platforms[0]["physics"]), "static flag preserved")
	assert_true(bool(restored.platforms[1]["physics"]), "physics flag preserved")


# --- ArenaBuilder dispatch --------------------------------------------------

func _test_builder_makes_static_body_for_plain_platform() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 20))
	var arena := ArenaBuilder.build(data)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is StaticBody2D, "plain platform is a StaticBody2D")
	assert_false(p0 is PhysicsBlock, "plain platform is not a PhysicsBlock")
	arena.free()


func _test_builder_makes_physics_block_for_flagged_platform() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(10, 20), Vector2(64, 64), Color.WHITE, true)
	var arena := ArenaBuilder.build(data)
	var p0 := arena.get_node("Platform0")
	assert_true(p0 is PhysicsBlock, "flagged platform is a PhysicsBlock")
	assert_eq(p0.position, Vector2(10, 20), "block positioned from data")

	var shape := (p0.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	assert_eq(shape.size, Vector2(64, 64), "collision shape sized from data")
	arena.free()


# --- PhysicsBlock node ------------------------------------------------------

func _test_block_mass_derived_from_area() -> void:
	var block := PhysicsBlock.new()
	block.configure(Vector2(200, 24))
	assert_almost_eq(block.mass, Model.block_mass(Vector2(200, 24)), "mass from shared model")
	assert_almost_eq(block.area(), Model.rect_area(Vector2(200, 24)), "area from footprint")
	block.free()


func _test_block_collision_layers_wired() -> void:
	var block := PhysicsBlock.new()
	block.configure(Vector2(32, 32))
	assert_eq(block.collision_layer, PhysicsBlock.LAYER_BLOCK, "lives on the block layer")
	# Collides with static geometry, players, and other blocks.
	var expected := PhysicsBlock.LAYER_STATIC | PhysicsBlock.LAYER_PLAYER | PhysicsBlock.LAYER_BLOCK
	assert_eq(block.collision_mask, expected, "masks static + players + blocks")
	block.free()


func _test_receive_push_is_a_safe_seam() -> void:
	# receive_push just forwards an impulse to the RigidBody2D; calling it
	# off-tree must not error (the physics step applies it later).
	var block := PhysicsBlock.new()
	block.configure(Vector2(32, 32))
	block.receive_push(Vector2(10, 0))
	assert_true(block.has_method("receive_push"), "pushers detect the seam by method")
	block.free()

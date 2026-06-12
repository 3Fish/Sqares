extends TestCase

## Spawn-point ordering must come from the seed-synced `RNGService` (#64), not
## Godot's global `Array.shuffle()`, so every peer orders the spawns identically
## in a given round. Otherwise online play (#23/#27) would desync the moment
## players are placed at round start.


func _make_arena(n: int) -> Arena:
	var arena := Arena.new()
	for i in n:
		var spawn := Node2D.new()
		spawn.name = "Spawn%d" % i
		spawn.position = Vector2(i * 100, 0)
		arena.add_child(spawn)
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	return arena


func _test_spawn_points_are_a_permutation_of_the_spawns() -> void:
	var arena := _make_arena(4)
	var pts := arena.get_spawn_points()
	assert_eq(pts.size(), 4, "every Spawn* node is returned")
	for i in 4:
		assert_true(pts.has(Vector2(i * 100, 0)), "spawn %d is present" % i)
	arena.free()


func _test_spawn_order_is_seed_deterministic() -> void:
	# Re-seeding the shared stream to the same value must reproduce the same
	# ordering — the property online play relies on (every peer, same seed,
	# same spawn assignment). `Array.shuffle()` would fail this.
	var arena := _make_arena(8)

	RNGService.seed_match(4242)
	var first := arena.get_spawn_points()
	RNGService.seed_match(4242)
	var second := arena.get_spawn_points()

	assert_eq(first, second, "same seed -> identical spawn order across peers")
	arena.free()


func _test_spawn_order_follows_the_synced_stream() -> void:
	# Proves the ordering is actually drawn from RNGService (not a private/global
	# RNG): a plain `RNGService.shuffled()` over the same source, after the same
	# seed, predicts get_spawn_points()'s order exactly.
	var arena := _make_arena(8)
	var source: Array[Vector2] = []
	for i in 8:
		source.append(Vector2(i * 100, 0))

	RNGService.seed_match(1337)
	var expected: Array[Vector2] = []
	expected.assign(RNGService.shuffled(source))

	RNGService.seed_match(1337)
	var actual := arena.get_spawn_points()

	assert_eq(actual, expected, "spawn order matches the seeded RNGService stream")
	arena.free()

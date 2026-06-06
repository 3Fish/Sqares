extends TestCase

## Base arenas must ship at least MAX_PLAYERS distinct spawns for clean
## 4-player matches — the director can fall back, but shipped arenas should
## not need to (#25).


func _test_base_arenas_have_enough_unique_spawns() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for path in [
		"res://scenes/arena/arena_crossroads.tscn",
		"res://scenes/arena/arena_highrise.tscn",
	]:
		var arena: Node = load(path).instantiate()
		tree.root.add_child(arena)
		var spawns: Array[Vector2] = arena.get_spawn_points()
		assert_true(spawns.size() >= MatchDirector.MAX_PLAYERS,
			"%s has >= %d spawn points (got %d)" % [path, MatchDirector.MAX_PLAYERS, spawns.size()])
		assert_true(_all_unique(spawns), "%s spawn points are all unique" % path)
		arena.free()


func _all_unique(points: Array) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i] == points[j]:
				return false
	return true

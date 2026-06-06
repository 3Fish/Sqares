extends Node

## Dependency-free headless test harness.
##
## Run with:
##   godot --headless --rendering-driver dummy --audio-driver Dummy \
##         res://tests/run_tests.tscn
##
## Runs as a real scene (not `--script`) so autoload singletons and global
## `class_name` identifiers resolve exactly as they do in the running game.
## Exits 0 when every assertion passes, 1 otherwise.

const PLAYER_ACTIONS := [
	"move_left", "move_right", "jump", "shoot",
	"aim_left", "aim_right", "aim_up", "aim_down",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	test_input_maps()
	test_clamp_player_count()
	test_resolve_spawn_positions()
	test_setup_match_player_counts()
	test_arena_spawn_points()

	print("\n--- %d passed, %d failed ---" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## p1..p4 must each have the full action set so every local player can be driven.
func test_input_maps() -> void:
	for player in range(1, 5):
		for action in PLAYER_ACTIONS:
			var name := "p%d_%s" % [player, action]
			_check(InputMap.has_action(name), "input action exists: %s" % name)


func test_clamp_player_count() -> void:
	_eq(MatchDirector.clamp_player_count(0), 2, "clamp 0 -> min 2")
	_eq(MatchDirector.clamp_player_count(1), 2, "clamp 1 -> min 2")
	_eq(MatchDirector.clamp_player_count(2), 2, "clamp 2 -> 2")
	_eq(MatchDirector.clamp_player_count(3), 3, "clamp 3 -> 3")
	_eq(MatchDirector.clamp_player_count(4), 4, "clamp 4 -> 4")
	_eq(MatchDirector.clamp_player_count(5), 4, "clamp 5 -> max 4")
	_eq(MatchDirector.clamp_player_count(-3), 2, "clamp negative -> min 2")


func test_resolve_spawn_positions() -> void:
	var two: Array[Vector2] = [Vector2(-400, 0), Vector2(400, 0)]

	# Enough spawns: first `count` are returned verbatim.
	var p2 := MatchDirector.resolve_spawn_positions(2, two)
	_eq(p2.size(), 2, "2 players -> 2 positions")
	_check(p2[0] == two[0] and p2[1] == two[1], "2 players reuse exact spawns")

	# Fewer spawns than players: real spawns kept, extras nudged, none overlap.
	var p4 := MatchDirector.resolve_spawn_positions(4, two)
	_eq(p4.size(), 4, "4 players -> 4 positions")
	_check(p4[0] == two[0] and p4[1] == two[1], "first 2 positions are the real spawns")
	_check(_all_unique(p4), "4 positions are all unique (no stacking)")

	# No spawn metadata at all: players fan out symmetrically around origin.
	var p3 := MatchDirector.resolve_spawn_positions(3, [] as Array[Vector2])
	_eq(p3.size(), 3, "no-spawn fallback -> 3 positions")
	_check(_all_unique(p3), "no-spawn fallback positions are unique")
	var sum_x := p3[0].x + p3[1].x + p3[2].x
	_check(absf(sum_x) < 0.001, "no-spawn fallback is symmetric around origin")

	# Degenerate input.
	_eq(MatchDirector.resolve_spawn_positions(0, two).size(), 0, "0 players -> 0 positions")


func test_setup_match_player_counts() -> void:
	for count in [2, 3, 4]:
		GameManager.setup_match("crossroads", count, 5)
		_eq(GameManager.win_counts.size(), count, "setup_match(%d) tracks %d players" % [count, count])
		var all_zero := true
		for i in count:
			if GameManager.win_counts.get(i, -1) != 0:
				all_zero = false
		_check(all_zero, "setup_match(%d) zeroes every win count" % count)


## Base arenas must ship at least MAX_PLAYERS distinct spawns for clean 4-player
## matches (the director can fall back, but shipped arenas should not need to).
func test_arena_spawn_points() -> void:
	for path in [
		"res://scenes/arena/arena_crossroads.tscn",
		"res://scenes/arena/arena_highrise.tscn",
	]:
		var arena: Node = load(path).instantiate()
		add_child(arena)
		var spawns: Array[Vector2] = arena.get_spawn_points()
		_check(spawns.size() >= MatchDirector.MAX_PLAYERS,
			"%s has >= %d spawn points (got %d)" % [path, MatchDirector.MAX_PLAYERS, spawns.size()])
		_check(_all_unique(spawns), "%s spawn points are all unique" % path)
		arena.free()


# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: ", label)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [label, expected, actual])


func _all_unique(points: Array) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if points[i] == points[j]:
				return false
	return true

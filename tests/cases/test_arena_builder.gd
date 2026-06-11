extends TestCase

## Tests for the arena load path (#33): ArenaData -> runtime Arena node tree and
## PackedScene, plus LevelRegistry registration of custom arenas.

const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")
const ArenaStoreScript = preload("res://scripts/arena/arena_store.gd")
const LevelRegistryScript = preload("res://scripts/mods/level_registry.gd")

# Distinct id so the suite never collides with real user data.
const STORE_ID := "__test_builder_arena"


func before_each() -> void:
	ArenaStoreScript.delete(STORE_ID)


func after_each() -> void:
	ArenaStoreScript.delete(STORE_ID)


func _make(id: String = "test_arena") -> ArenaData:
	var arena: ArenaData = ArenaDataScript.new()
	arena.id = id
	arena.display_name = "Test Arena"
	arena.background_color = Color(0.1, 0.2, 0.3, 1.0)
	arena.add_platform(Vector2(0, 100), Vector2(200, 24))
	arena.add_platform(Vector2(-220, 80), Vector2(160, 24), Color(0.5, 0.5, 0.5, 1.0))
	arena.add_spawn_point(Vector2(-50, 80))
	arena.add_spawn_point(Vector2(50, 80))
	arena.add_spawn_point(Vector2(150, 80))
	arena.add_kill_zone(Vector2(0, 400), Vector2(800, 32))
	return arena


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


# --- build(): node structure ------------------------------------------------

func _test_build_returns_an_arena() -> void:
	var arena := ArenaBuilder.build(_make())
	assert_not_null(arena, "build returns a node")
	assert_true(arena is Arena, "root is an Arena")
	assert_eq(arena.name, "Test Arena", "root named from display_name")
	arena.free()


func _test_build_creates_named_spawn_nodes() -> void:
	var data := _make()
	var arena := ArenaBuilder.build(data)
	_tree().root.add_child(arena)

	var spawns := arena.get_spawn_points()
	assert_eq(spawns.size(), 3, "all spawn points produced Spawn* nodes")
	# get_spawn_points shuffles, so compare as a set of expected positions.
	for expected in data.spawn_points:
		assert_true(spawns.has(expected), "spawn %s is present" % expected)

	arena.free()


func _test_build_creates_solid_platforms() -> void:
	var arena := ArenaBuilder.build(_make())
	var p0 := arena.get_node("Platform0") as StaticBody2D
	assert_not_null(p0, "Platform0 is a StaticBody2D")
	assert_eq(p0.position, Vector2(0, 100), "platform positioned from data")

	var shape := (p0.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	assert_not_null(shape, "platform has a RectangleShape2D")
	assert_eq(shape.size, Vector2(200, 24), "collision shape sized from data")

	var visual := p0.get_node("Visual") as Polygon2D
	assert_eq(visual.color, ArenaBuilder.PLATFORM_COLOR, "default platform colour")
	arena.free()


func _test_build_uses_custom_platform_color() -> void:
	var arena := ArenaBuilder.build(_make())
	var visual := arena.get_node("Platform1/Visual") as Polygon2D
	assert_eq(visual.color, Color(0.5, 0.5, 0.5, 1.0), "custom platform colour preserved")
	arena.free()


func _test_build_creates_kill_zone() -> void:
	var arena := ArenaBuilder.build(_make())
	var kz := arena.get_node("KillZone") as Area2D
	assert_not_null(kz, "KillZone Area2D exists")
	assert_eq(kz.collision_layer, 0, "kill zone does not occupy a layer")
	assert_eq(kz.collision_mask, ArenaBuilder.KILL_ZONE_MASK, "kill zone masks the player layer")
	assert_eq(kz.get_child_count(), 1, "one collision shape per data kill zone")

	var col := kz.get_child(0) as CollisionShape2D
	assert_eq(col.position, Vector2(0, 400), "kill-zone shape positioned from data")
	assert_eq((col.shape as RectangleShape2D).size, Vector2(800, 32), "kill-zone shape sized from data")
	arena.free()


func _test_build_omits_kill_zone_when_none() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.id = "no_kill"
	data.add_spawn_point(Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	assert_false(arena.has_node("KillZone"), "no KillZone node when data has none")
	arena.free()


func _test_build_sets_background_color() -> void:
	var arena := ArenaBuilder.build(_make())
	var bg := arena.get_node("Background") as Polygon2D
	assert_not_null(bg, "Background polygon exists")
	assert_eq(bg.color, Color(0.1, 0.2, 0.3, 1.0), "background uses data colour")
	arena.free()


func _test_build_names_root_from_id_when_no_display_name() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.id = "slug_only"
	var arena := ArenaBuilder.build(data)
	assert_eq(arena.name, "slug_only", "root falls back to id")
	arena.free()


# --- compute_bounds() / rect_polygon(): pure helpers ------------------------

func _test_compute_bounds_covers_content_with_padding() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(100, 100))  # spans -50..50
	var bounds := ArenaBuilder.compute_bounds(data)
	var pad := ArenaBuilder.BACKGROUND_PADDING
	assert_eq(bounds.position, Vector2(-50 - pad, -50 - pad), "min corner padded")
	assert_eq(bounds.end, Vector2(50 + pad, 50 + pad), "max corner padded")


func _test_compute_bounds_falls_back_when_empty() -> void:
	var data: ArenaData = ArenaDataScript.new()
	var bounds := ArenaBuilder.compute_bounds(data)
	var ext := ArenaBuilder.DEFAULT_BACKGROUND_EXTENT
	assert_eq(bounds.position, Vector2(-ext, -ext), "default min corner")
	assert_eq(bounds.size, Vector2(ext, ext) * 2.0, "default full extent")


func _test_rect_polygon_is_centered() -> void:
	var poly := ArenaBuilder.rect_polygon(Vector2(200, 100))
	assert_eq(poly.size(), 4, "rectangle has four corners")
	assert_eq(poly[0], Vector2(-100, -50), "top-left corner")
	assert_eq(poly[2], Vector2(100, 50), "bottom-right corner")


# --- build_packed_scene(): round-trip ---------------------------------------

func _test_packed_scene_instantiates_to_equivalent_arena() -> void:
	var data := _make()
	var scene := ArenaBuilder.build_packed_scene(data)
	assert_not_null(scene, "packed scene produced")

	var arena: Arena = scene.instantiate()
	_tree().root.add_child(arena)
	assert_eq(arena.get_spawn_points().size(), 3, "instantiated arena keeps its spawns")
	assert_true(arena.has_node("KillZone"), "instantiated arena keeps its kill zone")
	assert_not_null(arena.get_node("Platform0"), "instantiated arena keeps platforms")
	arena.free()


# --- LevelRegistry integration ----------------------------------------------

func _test_register_arena_data_makes_it_loadable() -> void:
	var registry: Node = LevelRegistryScript.new()
	var ok: bool = registry.register_arena_data(_make("registered_arena"))
	assert_true(ok, "registration succeeds")
	assert_true(registry.has_level("registered_arena"), "registry reports the arena")

	var scene: PackedScene = registry.get_level("registered_arena")
	assert_not_null(scene, "get_level returns a PackedScene")
	var arena: Arena = scene.instantiate()
	_tree().root.add_child(arena)
	assert_eq(arena.get_spawn_points().size(), 3, "registered arena is playable")
	arena.free()
	registry.free()


func _test_register_arena_data_rejects_invalid() -> void:
	var registry: Node = LevelRegistryScript.new()
	assert_false(registry.register_arena_data(null), "null arena rejected")
	var no_id: ArenaData = ArenaDataScript.new()
	assert_false(registry.register_arena_data(no_id), "empty-id arena rejected")
	assert_true(registry.get_all_ids().is_empty(), "nothing registered for invalid data")
	registry.free()


func _test_load_custom_arenas_registers_stored_arenas() -> void:
	var stored := _make(STORE_ID)
	assert_eq(ArenaStoreScript.save(stored), OK, "fixture saved to disk")

	var registry: Node = LevelRegistryScript.new()
	var ids: Array = registry.load_custom_arenas()
	assert_true(ids.has(STORE_ID), "stored arena id reported as loaded")
	assert_true(registry.has_level(STORE_ID), "stored arena registered")

	var scene: PackedScene = registry.get_level(STORE_ID)
	var arena: Arena = scene.instantiate()
	_tree().root.add_child(arena)
	assert_eq(arena.get_spawn_points().size(), 3, "disk-loaded arena is playable")
	arena.free()
	registry.free()

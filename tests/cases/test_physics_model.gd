extends TestCase

## Tests for the shared physics mass/size/health model (#96, from #85).
## All functions are pure, so these run without a scene tree.

const Model = preload("res://scripts/physics/physics_model.gd")


# --- mass = size * density (the single definition) ---------------------------

func _test_mass_from_size_is_size_times_density() -> void:
	assert_almost_eq(Model.mass_from_size(10.0, 0.5), 5.0, "10 * 0.5")
	assert_almost_eq(Model.mass_from_size(0.0, 0.5), 0.0, "zero size -> zero mass")


func _test_rect_area_multiplies_extents() -> void:
	assert_almost_eq(Model.rect_area(Vector2(200, 24)), 4800.0, "200 * 24")
	# Negative extents (defensive) still yield a positive area.
	assert_almost_eq(Model.rect_area(Vector2(-50, 4)), 200.0, "abs of extents")


# --- Players ----------------------------------------------------------------

func _test_player_size_couples_base_and_health() -> void:
	var expected := 32.0 + 100.0 * Model.PLAYER_SIZE_PER_HEALTH
	assert_almost_eq(Model.player_size(32.0, 100.0), expected, "size_stat + health*factor")


func _test_player_mass_from_size_stat() -> void:
	assert_almost_eq(Model.player_mass(32.0), 32.0 * Model.PLAYER_DENSITY, "size_stat * density")


func _test_player_mass_scales_with_size() -> void:
	assert_true(Model.player_mass(64.0) > Model.player_mass(32.0), "bigger player -> more mass")


# --- Bullets ----------------------------------------------------------------

func _test_bullet_size_couples_scale_and_damage() -> void:
	var expected := 1.0 + 25.0 * Model.BULLET_SIZE_PER_DAMAGE
	assert_almost_eq(Model.bullet_size(1.0, 25.0), expected, "scale + damage*factor")


func _test_bullet_mass_is_size_times_density() -> void:
	var size := Model.bullet_size(1.0, 25.0)
	assert_almost_eq(Model.bullet_mass(1.0, 25.0), size * Model.BULLET_DENSITY, "bullet mass")


func _test_bullet_health_from_damage() -> void:
	assert_almost_eq(Model.bullet_health(25.0), 25.0 * Model.BULLET_DENSITY, "damage * density")


# --- Physics blocks ---------------------------------------------------------

func _test_block_mass_is_area_times_density() -> void:
	var size := Vector2(200, 24)
	var expected := Model.rect_area(size) * Model.BLOCK_DENSITY
	assert_almost_eq(Model.block_mass(size), expected, "area * density")


func _test_block_health_reuses_the_mass_formula() -> void:
	# The whole point of #85's "defined once": block health and mass are the
	# same area*density quantity, not two independent derivations.
	var size := Vector2(120, 48)
	assert_almost_eq(Model.block_health(size), Model.block_mass(size), "block health == mass")
	assert_almost_eq(
		Model.block_mass(size),
		Model.mass_from_size(Model.rect_area(size), Model.BLOCK_DENSITY),
		"block mass routes through mass_from_size"
	)


func _test_block_mass_scales_with_area() -> void:
	assert_true(
		Model.block_mass(Vector2(200, 48)) > Model.block_mass(Vector2(200, 24)),
		"a bigger block is heavier"
	)


# --- Push impulse -----------------------------------------------------------

func _test_push_impulse_acts_into_the_body() -> void:
	# Pusher moving +x into a block on its right: Godot's normal (block->pusher)
	# points -x; the impulse must drive the block along +x.
	var impulse := Model.push_impulse(5.0, Vector2(100, 0), Vector2(-1, 0))
	assert_almost_eq(impulse.x, 5.0 * 100.0, "impulse = mass * into-speed")
	assert_almost_eq(impulse.y, 0.0, "no off-axis component")


func _test_push_impulse_zero_when_separating() -> void:
	# Pusher moving away from the contact: no push.
	var impulse := Model.push_impulse(5.0, Vector2(-100, 0), Vector2(-1, 0))
	assert_eq(impulse, Vector2.ZERO, "separating contact imparts nothing")


func _test_push_impulse_zero_when_perpendicular() -> void:
	var impulse := Model.push_impulse(5.0, Vector2(0, 100), Vector2(-1, 0))
	assert_eq(impulse, Vector2.ZERO, "glancing contact imparts nothing")


func _test_push_impulse_scales_with_mass() -> void:
	var light := Model.push_impulse(1.0, Vector2(100, 0), Vector2(-1, 0))
	var heavy := Model.push_impulse(10.0, Vector2(100, 0), Vector2(-1, 0))
	assert_true(heavy.length() > light.length(), "heavier pusher shoves harder")

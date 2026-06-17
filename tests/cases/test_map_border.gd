extends TestCase

## Tests for the damaging elastic map boundary (#84). The boundary maths live in
## the pure, scene-free `MapBorder` helper; `Player` holds only the per-excursion
## state and wires these in, so the contact test, restoring force, bounce impulse
## and the 50-per-500 ms damage cadence are all covered here without a scene.

const Border = preload("res://scripts/arena/map_border.gd")

# Player-sized body for the contact tests: the player.tscn collision rectangle.
const HALF := Vector2(14.0, 20.0)


# --- Penetration / contact test ---------------------------------------------

func _test_inside_play_area_is_not_out_of_bounds() -> void:
	assert_eq(Border.penetration(Vector2(0, 0), HALF), Vector2.ZERO, "centre is in bounds")
	assert_false(Border.is_out_of_bounds(Vector2(0, 0), HALF), "centre is in bounds")
	# Body fully inside near (but not touching) the right edge.
	assert_eq(Border.penetration(Vector2(620, 0), HALF), Vector2.ZERO, "edge at 634 < 640")


func _test_crossing_right_border_pushes_left() -> void:
	# Centre 630, half 14 -> right edge 644, which is 4px past the 640 border.
	var pen := Border.penetration(Vector2(630, 0), HALF)
	assert_eq(pen, Vector2(-4, 0), "inward (left) by the 4px penetration")
	assert_true(Border.is_out_of_bounds(Vector2(630, 0), HALF), "out of bounds")


func _test_crossing_left_border_pushes_right() -> void:
	var pen := Border.penetration(Vector2(-630, 0), HALF)
	assert_eq(pen, Vector2(4, 0), "inward (right) by 4px")


func _test_crossing_bottom_border_pushes_up() -> void:
	# Centre y 350, half 20 -> bottom edge 370, 10px past the 360 border.
	var pen := Border.penetration(Vector2(0, 350), HALF)
	assert_eq(pen, Vector2(0, -10), "inward (up) by 10px")


func _test_crossing_top_border_pushes_down() -> void:
	var pen := Border.penetration(Vector2(0, -350), HALF)
	assert_eq(pen, Vector2(0, 10), "inward (down) by 10px")


func _test_corner_excursion_yields_both_axes() -> void:
	# Past the right (635+14-640 = 9) and bottom (355+20-360 = 15) borders at once.
	var pen := Border.penetration(Vector2(635, 355), HALF)
	assert_eq(pen, Vector2(-9, -15), "both components, each inward")


func _test_penetration_scales_with_distance_past_border() -> void:
	var shallow := Border.penetration(Vector2(630, 0), HALF)
	var deep := Border.penetration(Vector2(700, 0), HALF)
	assert_true(deep.length() > shallow.length(), "further past -> deeper penetration")


# --- Restoring force (Hooke's law) ------------------------------------------

func _test_restoring_acceleration_is_spring_constant_times_penetration() -> void:
	var pen := Vector2(-4, 0)
	var accel := Border.restoring_acceleration(pen)
	assert_almost_eq(accel.x, -4.0 * Border.SPRING_CONSTANT, "a = k * x, inward")
	assert_almost_eq(accel.y, 0.0, "no off-axis force")


func _test_restoring_acceleration_scales_with_penetration() -> void:
	var shallow := Border.restoring_acceleration(Vector2(0, -5))
	var deep := Border.restoring_acceleration(Vector2(0, -20))
	assert_true(deep.length() > shallow.length(), "deeper penetration -> stronger pull")


# --- First-contact bounce impulse -------------------------------------------

func _test_contact_impulse_is_inward_and_fixed_magnitude() -> void:
	# Past the right border: the bounce drives the player back left (-x).
	var impulse := Border.contact_impulse(Vector2(-4, 0))
	assert_almost_eq(impulse.x, -Border.CONTACT_IMPULSE, "inward at the tuned speed")
	assert_almost_eq(impulse.y, 0.0, "no off-axis component")


func _test_contact_impulse_direction_follows_penetration() -> void:
	# Off the bottom border -> bounce upward (-y).
	var impulse := Border.contact_impulse(Vector2(0, -10))
	assert_almost_eq(impulse.y, -Border.CONTACT_IMPULSE, "bounce up off the bottom")


func _test_contact_impulse_is_zero_when_in_bounds() -> void:
	assert_eq(Border.contact_impulse(Vector2.ZERO), Vector2.ZERO, "no contact, no impulse")


# --- Damage cadence (50 per 500 ms) -----------------------------------------

func _test_no_damage_before_the_interval_elapses() -> void:
	var acc := Border.accrue_damage(Border.DAMAGE_INTERVAL, 0.1)
	assert_almost_eq(acc["damage"], 0.0, "countdown not yet crossed zero")
	assert_almost_eq(acc["timer"], 0.4, "countdown advanced by delta")


func _test_one_tick_of_damage_when_interval_crossed() -> void:
	var acc := Border.accrue_damage(0.05, 0.1)
	assert_almost_eq(acc["damage"], Border.DAMAGE_PER_TICK, "one 50-damage tick")
	# Countdown rolls over by exactly one interval (carrying the overshoot).
	assert_almost_eq(acc["timer"], 0.45, "timer reset by one interval")


func _test_long_tick_banks_multiple_damage_ticks() -> void:
	# A 1.2s tick starting with a full 0.5s countdown crosses zero twice.
	var acc := Border.accrue_damage(Border.DAMAGE_INTERVAL, 1.2)
	assert_almost_eq(acc["damage"], 2.0 * Border.DAMAGE_PER_TICK, "two ticks banked")
	assert_almost_eq(acc["timer"], 0.3, "remaining countdown after both ticks")


func _test_steady_cadence_is_one_tick_per_interval() -> void:
	# Drive ~1.0s of out-of-bounds time in 0.1s steps starting just after first
	# contact (timer primed to one interval) and count the damage ticks: expect
	# 50 at t=0.5 and 50 at t=1.0 -> 100 total.
	var timer := Border.DAMAGE_INTERVAL
	var total := 0.0
	for _i in 10:
		var acc := Border.accrue_damage(timer, 0.1)
		timer = acc["timer"]
		total += acc["damage"]
	assert_almost_eq(total, 100.0, "two ticks over one second of contact")


# --- Sanity on the tuned contract -------------------------------------------

func _test_play_area_matches_the_view_edge() -> void:
	assert_eq(Border.HALF_EXTENT, Vector2(640, 360), "border sits at the 1280x720 view edge")


func _test_damage_contract_is_fifty_per_half_second() -> void:
	assert_almost_eq(Border.DAMAGE_PER_TICK, 50.0, "50 damage per tick")
	assert_almost_eq(Border.DAMAGE_INTERVAL, 0.5, "every 500 ms")

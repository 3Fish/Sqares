extends TestCase

## Tests for the decorative Chain/Rope visual (#104, deferred from #98). The sag
## geometry lives in the pure, scene-free `RopeVisual`; the `Rope` node exposes
## the same curve through `visual_points()` (straight while taut, bowing down as
## the rope goes slack, empty once severed/missing). Per the maintainer's #104
## answer the rope is "just a line with some sag" and never collides, so these
## cover the geometry only. Scene-tree-free where possible per `CLAUDE.md`.

const Visual = preload("res://scripts/arena/rope_visual.gd")
const ArenaDataScript = preload("res://scripts/arena/arena_data.gd")


# --- Pure sag depth ---------------------------------------------------------

func _test_taut_rope_has_zero_sag() -> void:
	# Endpoints exactly a rope-length apart -> straight, no droop.
	assert_almost_eq(Visual.sag_depth(200.0, 200.0), 0.0, "taut rope: no sag")


func _test_overextended_rope_has_zero_sag() -> void:
	# The constraint never lets this happen, but the maths must clamp at 0 rather
	# than take the sqrt of a negative.
	assert_almost_eq(Visual.sag_depth(250.0, 200.0), 0.0, "over-extended: clamped to 0")


func _test_slack_rope_sags_by_the_fold_depth() -> void:
	# 200-long rope, endpoints 120 apart: half-fold of sqrt(200^2 - 120^2)/... ->
	# 0.5 * sqrt(40000 - 14400) = 0.5 * sqrt(25600) = 0.5 * 160 = 80.
	assert_almost_eq(Visual.sag_depth(120.0, 200.0), 80.0, "slack rope folds to 80px deep")


func _test_fully_collapsed_rope_hangs_half_its_length() -> void:
	# Endpoints coincident: the rope folds straight down by half its material length.
	assert_almost_eq(Visual.sag_depth(0.0, 200.0), 100.0, "collapsed rope hangs rope_length/2")


func _test_sag_grows_as_the_rope_goes_slacker() -> void:
	# Monotonic: the closer the endpoints, the deeper the sag.
	var tight := Visual.sag_depth(190.0, 200.0)
	var mid := Visual.sag_depth(140.0, 200.0)
	var loose := Visual.sag_depth(60.0, 200.0)
	assert_true(tight < mid, "more slack -> more sag (tight < mid)")
	assert_true(mid < loose, "more slack -> more sag (mid < loose)")


func _test_degenerate_rope_length_has_no_sag() -> void:
	# An unresolved/zero-length rope must not produce NaNs or droop.
	assert_almost_eq(Visual.sag_depth(50.0, 0.0), 0.0, "zero length: no sag")
	assert_almost_eq(Visual.sag_depth(50.0, -1.0), 0.0, "negative length: no sag")


# --- Pure sag polyline ------------------------------------------------------

func _test_polyline_has_one_more_point_than_segments() -> void:
	var pts := Visual.sag_points(Vector2.ZERO, Vector2(100, 0), 100.0, 8)
	assert_eq(pts.size(), 9, "8 segments -> 9 points")


func _test_segment_count_is_clamped_to_at_least_one() -> void:
	var pts := Visual.sag_points(Vector2.ZERO, Vector2(100, 0), 100.0, 0)
	assert_eq(pts.size(), 2, "0 segments clamps to a single segment (2 points)")


func _test_endpoints_are_preserved_exactly() -> void:
	var a := Vector2(-30, 40)
	var b := Vector2(70, -10)
	var pts := Visual.sag_points(a, b, 500.0, 12)  # very slack so the middle bows hard
	assert_eq(pts[0], a, "first point is endpoint a")
	assert_eq(pts[pts.size() - 1], b, "last point is endpoint b")


func _test_taut_polyline_is_a_straight_chord() -> void:
	# chord == rope_length -> every interior point lies on the a->b line.
	var a := Vector2.ZERO
	var b := Vector2(120, 90)  # length 150
	var pts := Visual.sag_points(a, b, 150.0, 6)
	for i in pts.size():
		var t := float(i) / 6.0
		assert_eq(pts[i], a.lerp(b, t), "taut: point %d on the straight chord" % i)


func _test_slack_polyline_bows_downward_at_the_midpoint() -> void:
	# Horizontal chord so "down" (+Y) is purely the sag component. 200-long rope
	# across a 120px gap sags 80px (see depth test); the midpoint is the deepest.
	var a := Vector2(-60, 0)
	var b := Vector2(60, 0)
	var pts := Visual.sag_points(a, b, 200.0, 8)
	var mid := pts[4]  # 8 segments -> index 4 is the centre
	assert_almost_eq(mid.x, 0.0, "midpoint stays centred horizontally")
	assert_almost_eq(mid.y, 80.0, "midpoint droops down by the full sag depth")
	# Every interior point hangs at or below the chord (y >= 0), deepest in the middle.
	assert_true(pts[2].y > 0.0 and pts[2].y < mid.y, "quarter point sags less than the centre")


func _test_sag_is_downward_regardless_of_chord_orientation() -> void:
	# A vertical chord still bows toward +Y (gravity), not perpendicular to the chord.
	var pts := Visual.sag_points(Vector2(0, -60), Vector2(0, 60), 200.0, 8)
	var mid := pts[4]
	assert_true(mid.x > 0.0 or mid.x < 0.0 or is_equal_approx(mid.x, 0.0), "x is defined")
	# The deepest point is pushed in +Y from the chord's own midpoint (0,0).
	assert_true(mid.y > 0.0, "vertical chord still sags downward (+Y)")


# --- Rope node wiring -------------------------------------------------------

func _test_node_visual_is_straight_when_placed_at_full_length() -> void:
	# A rope is authored at its full length, so it renders straight on spawn.
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)  # physics block 0
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)                          # auto length 200
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	var pts := rope.visual_points()
	assert_true(pts.size() >= 2, "a placed rope draws a line")
	# Endpoints span the anchor and the block; taut -> the midpoint is on the chord.
	var a := Vector2(0, -200)
	var b := Vector2(0, 0)
	assert_eq(pts[0], a, "spans the world anchor")
	assert_eq(pts[pts.size() - 1], b, "spans the block")
	assert_almost_eq(pts[pts.size() / 2].distance_to(a.lerp(b, 0.5)), 0.0, "taut rope is straight")
	arena.free()


func _test_node_visual_sags_when_the_block_hangs_slack() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, false)  # physics block 0
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)                          # length baked at 200
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	var block := arena.get_node("Platform0") as PhysicsBlock
	# Swing the block up toward the anchor so the endpoints are closer than the
	# rope length -> the rope must now sag.
	block.position = Vector2(0, -120)
	var pts := rope.visual_points()
	var mid := pts[pts.size() / 2]
	# Anchor (0,-200) to block (0,-120): chord 80, length 200 -> deep sag below the
	# chord midpoint (0,-160), i.e. a clearly larger y than -160.
	assert_true(mid.y > -160.0, "slack rope bows downward below its chord midpoint")
	arena.free()


func _test_severed_rope_has_no_visual() -> void:
	var data: ArenaData = ArenaDataScript.new()
	data.add_platform(Vector2(0, 0), Vector2(64, 64), Color.WHITE, true, true)  # physics + destructible
	data.add_rope(-1, Vector2(0, -200), 0, Vector2.ZERO)
	var arena := ArenaBuilder.build(data)
	var rope := arena.get_node("Rope0") as Rope
	rope.resolve()
	assert_true(rope.visual_points().size() >= 2, "intact rope draws a line")
	var block := arena.get_node("Platform0") as PhysicsBlock
	block.damage_block(block.health() + 100.0)  # destroy the endpoint -> sever
	assert_true(rope.is_severed(), "endpoint destruction severs the rope")
	assert_eq(rope.visual_points().size(), 0, "a severed rope draws nothing")
	arena.queue_free()

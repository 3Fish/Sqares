extends TestCase

## Reflecting-shield projectile maths (#138): the pure reflection vector and
## penetration-damage helpers, plus the small instance helpers that decide
## whether a target is shielded and route a penetrating hit (a negative
## `shield_penetration` heals through the shield). Mirrors the static-helper
## style of the explosion / homing tests — no live scene tree.

const ProjectileScript = preload("res://scripts/combat/projectile.gd")


## Records which damage path a penetrating hit took, standing in for a Player.
class _StubTarget extends Node2D:
	var shielded: bool = false
	var taken: float = -1.0
	var healed: float = -1.0
	func _init(p_shielded: bool = false) -> void:
		shielded = p_shielded
	func is_shielded() -> bool:
		return shielded
	func take_damage(amount: float, _attacker: Node = null) -> void:
		taken = amount
	func heal(amount: float) -> void:
		healed = amount


## A bare target exposing no shield query — must read as unshielded.
class _NoShieldTarget extends Node2D:
	func take_damage(_amount: float, _attacker: Node = null) -> void:
		pass


var proj: Projectile


func before_each() -> void:
	proj = ProjectileScript.new()


func after_each() -> void:
	if proj:
		proj.free()
		proj = null


# ---------------------------------------------------------------------------
# Pure statics
# ---------------------------------------------------------------------------

func _test_reflect_velocity_is_straight_reversal() -> void:
	assert_eq(ProjectileScript.reflect_velocity(Vector2(3.0, -4.0)), Vector2(-3.0, 4.0),
		"reflection sends the bullet straight back")
	# Speed (magnitude) is preserved — only the direction flips.
	assert_almost_eq(ProjectileScript.reflect_velocity(Vector2(3.0, -4.0)).length(), 5.0,
		"reflection preserves speed")
	assert_eq(ProjectileScript.reflect_velocity(Vector2.ZERO), Vector2.ZERO,
		"reflecting a zero velocity is a no-op")


func _test_penetration_damage_scales_unclamped() -> void:
	assert_almost_eq(ProjectileScript.penetration_damage(40.0, 0.0), 0.0,
		"p=0 lands no damage (the bullet is fully reflected instead)")
	assert_almost_eq(ProjectileScript.penetration_damage(40.0, 0.5), 20.0,
		"p=0.5 lands half the bullet's damage")
	assert_almost_eq(ProjectileScript.penetration_damage(40.0, 1.5), 60.0,
		"p>1 lands more than the base hit (unclamped)")
	assert_almost_eq(ProjectileScript.penetration_damage(40.0, -0.25), -10.0,
		"p<0 is negative — a heal through the shield")


# ---------------------------------------------------------------------------
# Instance helpers
# ---------------------------------------------------------------------------

func _test_target_shielded_reads_the_target() -> void:
	var up := _StubTarget.new(true)
	var down := _StubTarget.new(false)
	var bare := _NoShieldTarget.new()
	assert_true(proj._target_shielded(up), "a raised-shield target reads as shielded")
	assert_false(proj._target_shielded(down), "a lowered-shield target reads as unshielded")
	assert_false(proj._target_shielded(bare), "a target without is_shielded reads as unshielded")
	up.free()
	down.free()
	bare.free()


func _test_apply_player_damage_routes_positive_to_take_damage() -> void:
	var t := _StubTarget.new()
	proj._apply_player_damage(t, 25.0)
	assert_almost_eq(t.taken, 25.0, "a positive penetrating hit lands as damage")
	assert_almost_eq(t.healed, -1.0, "no heal for a positive hit")
	t.free()


func _test_apply_player_damage_routes_negative_to_heal() -> void:
	var t := _StubTarget.new()
	proj._apply_player_damage(t, -15.0)
	assert_almost_eq(t.healed, 15.0, "a negative penetrating hit (p<0) heals through the shield")
	assert_almost_eq(t.taken, -1.0, "no damage path for a healing hit")
	t.free()


# ---------------------------------------------------------------------------
# Online reflection re-broadcast contract (#158, item 2)
# ---------------------------------------------------------------------------

func _test_reflection_rebroadcast_payload_is_the_bounce_back() -> void:
	# Reflection mutates the shot in place (reverse velocity, hand it to the
	# deflector) and the host re-broadcasts it under the SAME net_id so clients show
	# the bounce-back instead of the bullet vanishing at the shield. The live call
	# site needs a real collision (boot/integration-verified, like the rest of the
	# reflection path), but the wire contract it sends is pure and asserted here:
	# build the payload exactly as the reflect branch does and check it carries the
	# reversed trajectory, the deflector as owner, and the unchanged shot id.
	proj.net_id = "7_2"
	proj.velocity = ProjectileScript.reflect_velocity(Vector2(300.0, -120.0))
	var deflector_slot := 3
	var payload := ProjectileScript.projectile_payload(proj, deflector_slot)
	assert_eq(payload["net_id"], "7_2", "the re-broadcast keeps the same shot id")
	assert_eq(payload["player_id"], 3, "the reflected shot is re-owned by the deflector")
	assert_eq(payload["velocity"], [-300.0, 120.0], "the wire carries the reversed (bounce-back) velocity")

extends TestCase

## Player.apply_knockback adds an impulse while alive and is ignored once dead (#21).

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")


func _test_player_knockback() -> void:
	var p: Player = PLAYER_SCENE.instantiate()
	p.velocity = Vector2(10.0, 0.0)
	p.apply_knockback(Vector2(100.0, -50.0))
	assert_true(p.velocity.is_equal_approx(Vector2(110.0, -50.0)), "knockback adds impulse to velocity")
	p._dead = true
	p.apply_knockback(Vector2(500.0, 0.0))
	assert_true(p.velocity.is_equal_approx(Vector2(110.0, -50.0)), "dead player ignores knockback")
	p.free()

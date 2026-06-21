extends TestCase

## Unit tests for the pure ammo HUD readout (#116). HUD.ammo_readout has no scene
## state, so the pip + reload-indicator formatting is exercised directly, mirroring
## the other pure helpers (AmmoModel / PhysicsModel).


func _test_full_magazine_is_all_filled_pips() -> void:
	assert_eq(HUD.ammo_readout(3, 3, 1.0), "▮▮▮", "a full magazine is all filled pips, no reload indicator")


func _test_partly_spent_magazine_shows_empties_and_reload() -> void:
	assert_eq(HUD.ammo_readout(1, 3, 0.5), "▮▯▯  ↻ 50%", "one round left, reloading at 50%")


func _test_empty_magazine_shows_all_empty_and_reload() -> void:
	assert_eq(HUD.ammo_readout(0, 3, 0.0), "▯▯▯  ↻ 0%", "empty magazine, reload just started")


func _test_reload_percent_rounds_and_clamps() -> void:
	assert_eq(HUD.ammo_readout(0, 2, 0.999), "▯▯  ↻ 100%", "near-full progress rounds to 100%")
	assert_eq(HUD.ammo_readout(0, 2, 1.5), "▯▯  ↻ 100%", "over-unity progress clamps to 100%")
	assert_eq(HUD.ammo_readout(0, 2, -0.5), "▯▯  ↻ 0%", "negative progress clamps to 0%")


func _test_over_and_under_round_counts_are_clamped() -> void:
	assert_eq(HUD.ammo_readout(5, 3, 1.0), "▮▮▮", "rounds above capacity never overflow the pips")
	assert_eq(HUD.ammo_readout(-1, 3, 0.0), "▯▯▯  ↻ 0%", "a negative round count reads as empty")


func _test_zero_capacity_is_empty_string() -> void:
	assert_eq(HUD.ammo_readout(0, 0, 1.0), "", "a zero-capacity magazine renders nothing")

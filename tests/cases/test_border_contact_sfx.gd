extends TestCase

## The map-border first-contact SFX hook (#101, deferred from #84). Crossing a
## damaging map border fires the BORDER_CONTACT cue through SfxDirector — the audio
## analogue of the one-shot inward bounce impulse — mirroring how Player fires
## DEATH and Weapon fires SHOOT at their own trigger sites. Like every cue it
## warns-and-no-ops until a mod registers a stream (no audio ships in base game,
## #47), so these assert the hook fires (and only on a genuine, live first contact)
## via SfxDirector.last_cue() without standing up the audio playback pool.
##
## net_role is PREDICTED so `_update_border` skips the host-authoritative damage
## branch (no live Health needed off-tree) — which also proves the cue is local
## feedback independent of damage authority, firing on a client that only predicts
## movement, exactly like the bounce impulse it accompanies.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

# Well past the right border (the play area is ±640 x ±360); with the default body
# half-extent the body is unambiguously out of bounds.
const OUT_OF_BOUNDS := Vector2(2000.0, 0.0)
const IN_BOUNDS := Vector2.ZERO


func _spawn_predicted_player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	# PREDICTED skips the `_is_damage_authority()` damage branch, so the step needs
	# no live Health and the cue is isolated from damage authority.
	p.net_role = Player.NetRole.PREDICTED
	return p


func _clear_last_cue() -> void:
	# Isolate from cues left by earlier tests / autoload wiring.
	SfxDirector._last_cue = ""


func _test_first_border_contact_fires_the_cue() -> void:
	var p := _spawn_predicted_player()
	_clear_last_cue()
	p.global_position = OUT_OF_BOUNDS
	var out := p._update_border(0.1, false)
	assert_true(out, "a body past the border is out of bounds")
	assert_eq(SfxDirector.last_cue(), SfxDirector.BORDER_CONTACT, "first contact fires the border-contact cue")
	p.free()


func _test_staying_out_of_bounds_does_not_refire_the_cue() -> void:
	var p := _spawn_predicted_player()
	p.global_position = OUT_OF_BOUNDS
	p._update_border(0.1, false)  # first contact
	_clear_last_cue()
	p._update_border(0.1, false)  # still out -> not a new contact
	assert_eq(SfxDirector.last_cue(), "", "remaining out of bounds fires no further contact cue")
	p.free()


func _test_inside_play_area_fires_no_cue() -> void:
	var p := _spawn_predicted_player()
	_clear_last_cue()
	p.global_position = IN_BOUNDS
	var out := p._update_border(0.1, false)
	assert_false(out, "a body inside the play area is not out of bounds")
	assert_eq(SfxDirector.last_cue(), "", "no contact, no cue")
	p.free()


func _test_reconciliation_replay_does_not_fire_the_cue() -> void:
	var p := _spawn_predicted_player()
	_clear_last_cue()
	p.global_position = OUT_OF_BOUNDS
	p._update_border(0.1, true)  # a rewind+replay re-simulates this step
	assert_eq(SfxDirector.last_cue(), "", "a replay re-simulates motion but never re-fires the one-shot cue")
	p.free()


func _test_re_entering_then_leaving_refires_the_cue() -> void:
	var p := _spawn_predicted_player()
	p.global_position = OUT_OF_BOUNDS
	p._update_border(0.1, false)  # first excursion fires
	# Cross back into the play area: the excursion state resets.
	p.global_position = IN_BOUNDS
	p._update_border(0.1, false)
	_clear_last_cue()
	# A fresh excursion is a new first contact and fires its own cue.
	p.global_position = OUT_OF_BOUNDS
	var out := p._update_border(0.1, false)
	assert_true(out, "out of bounds again")
	assert_eq(SfxDirector.last_cue(), SfxDirector.BORDER_CONTACT, "each new excursion fires its own contact cue")
	p.free()

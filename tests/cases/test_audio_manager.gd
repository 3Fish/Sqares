extends TestCase

## Integration tests for AudioManager against the live autoload singleton (#29).
## Tests run against the live singleton, so they also exercise project wiring
## (autoload order, bus creation). Negative-path cases intentionally trigger
## push_error / push_warning — those are expected, not failures.


func _test_buses_created() -> void:
	# The headless `--script` runner executes inside `_initialize()` before the
	# tree is live, so AudioManager's `_ready` (which builds the bus layout) never
	# fires. Invoke the idempotent creation path directly to exercise it.
	AudioManager._ensure_buses()
	assert_true(AudioServer.get_bus_index("Master") == 0, "Master bus is index 0")
	assert_true(AudioServer.get_bus_index(AudioManager.BUS_MUSIC) >= 0, "Music bus exists")
	assert_true(AudioServer.get_bus_index(AudioManager.BUS_SFX) >= 0, "SFX bus exists")
	assert_true(AudioServer.get_bus_index(AudioManager.BUS_UI) >= 0, "UI bus exists")


func _test_volume_get_set() -> void:
	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 0.5)
	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_MASTER), 0.5), "get returns set linear volume")

	var idx := AudioServer.get_bus_index(AudioManager.BUS_MASTER)
	assert_true(not AudioServer.is_bus_mute(idx), "bus is not muted at 0.5")
	assert_true(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5)),
		"AudioServer volume_db mirrors the linear value")

	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 0.0)
	assert_true(AudioServer.is_bus_mute(idx), "bus is muted at 0.0")
	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_MASTER), 0.0), "get returns 0.0 when muted")

	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 1.0)  # restore


func _test_volume_clamping() -> void:
	AudioManager.set_bus_volume(AudioManager.BUS_SFX, 1.5)
	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_SFX), 1.0), "above-range volume clamps to 1.0")
	AudioManager.set_bus_volume(AudioManager.BUS_SFX, -0.3)
	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_SFX), 0.0), "below-range volume clamps to 0.0")
	AudioManager.set_bus_volume(AudioManager.BUS_SFX, 1.0)  # restore


func _test_volume_signal() -> void:
	var captured: Array = []
	var cb := func(bus: String, linear: float) -> void: captured.append([bus, linear])
	AudioManager.bus_volume_changed.connect(cb)
	AudioManager.set_bus_volume(AudioManager.BUS_UI, 0.7)
	AudioManager.bus_volume_changed.disconnect(cb)
	assert_eq(captured.size(), 1, "bus_volume_changed emitted once")
	assert_true(captured.size() == 1 and captured[0][0] == AudioManager.BUS_UI, "signal carries the bus name")
	assert_true(captured.size() == 1 and is_equal_approx(captured[0][1], 0.7), "signal carries the linear value")
	AudioManager.set_bus_volume(AudioManager.BUS_UI, 1.0)  # restore


func _test_unknown_bus_is_safe() -> void:
	# Setting an unmanaged bus is a no-op (warns); getting one returns the 1.0 default.
	AudioManager.set_bus_volume("DoesNotExist", 0.2)
	assert_true(is_equal_approx(AudioManager.get_bus_volume("DoesNotExist"), 1.0), "unknown bus returns default 1.0")


func _test_sound_registration() -> void:
	var stream := AudioStreamGenerator.new()
	AudioManager.register_sound("test_shoot", stream)
	assert_true(AudioManager.has_sound("test_shoot"), "registered sound is found")
	assert_true(AudioManager.get_sound_names().has("test_shoot"), "registered sound appears in name list")
	assert_false(AudioManager.has_sound("never_registered"), "unregistered sound is absent")

	# Null / empty-name registrations are rejected (these emit push_error — expected).
	AudioManager.register_sound("", stream)
	assert_false(AudioManager.has_sound(""), "empty-name sound rejected")
	AudioManager.register_sound("bad", null)
	assert_false(AudioManager.has_sound("bad"), "null-stream sound rejected")


func _test_sound_override() -> void:
	var first := AudioStreamGenerator.new()
	var second := AudioStreamGenerator.new()
	AudioManager.register_sound("override_me", first)
	var before: int = AudioManager.get_sound_names().size()
	AudioManager.register_sound("override_me", second)  # mod override, same id
	var after: int = AudioManager.get_sound_names().size()
	assert_eq(before, after, "re-registering an id overrides rather than duplicating")
	assert_true(AudioManager.has_sound("override_me"), "overridden sound still present")


func _test_playback_does_not_crash() -> void:
	AudioManager.register_sound("playable", AudioStreamGenerator.new())
	AudioManager.play_sfx("playable")
	AudioManager.play_ui("playable")
	assert_true(true, "play_sfx / play_ui on a registered sound do not crash")
	# Unknown sound warns but must not crash (warning is expected).
	AudioManager.play_sfx("not_there")
	assert_true(true, "play_sfx on an unknown sound does not crash")


func _test_music_registration_and_playback() -> void:
	AudioManager.register_music("test_menu", AudioStreamGenerator.new())
	assert_true(AudioManager.has_music("test_menu"), "registered music track is found")

	AudioManager.play_music("test_menu", 0.0)
	assert_eq(AudioManager.get_current_track(), "test_menu", "play_music sets the current track")

	AudioManager.play_music("missing_track", 0.0)  # warns, no change
	assert_eq(AudioManager.get_current_track(), "test_menu", "unknown track leaves current track unchanged")

	AudioManager.stop_music(0.0)
	assert_eq(AudioManager.get_current_track(), "", "stop_music clears the current track")


func _test_persistence_round_trip() -> void:
	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 0.42)
	AudioManager.set_bus_volume(AudioManager.BUS_MUSIC, 0.13)
	AudioManager.save_settings()

	# Mutate in memory, then reload from disk and confirm the saved values win.
	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 0.99)
	AudioManager.set_bus_volume(AudioManager.BUS_MUSIC, 0.99)
	AudioManager.load_settings()

	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_MASTER), 0.42), "Master volume persisted across save/load")
	assert_true(is_equal_approx(AudioManager.get_bus_volume(AudioManager.BUS_MUSIC), 0.13), "Music volume persisted across save/load")

	# Clean up the settings file so the test leaves no state behind.
	DirAccess.remove_absolute("user://settings.cfg")
	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, 1.0)
	AudioManager.set_bus_volume(AudioManager.BUS_MUSIC, 1.0)

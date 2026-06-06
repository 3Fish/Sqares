extends SceneTree

## Dependency-free headless test harness.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 0 when all assertions pass, 1 otherwise. Tests run against the live
## autoload singletons, so this also exercises project wiring (autoload order,
## bus setup, etc.). Negative-path tests intentionally emit push_error /
## push_warning lines — those are expected, not failures.

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	# Deferred so all autoload singletons finish _ready() before tests run.
	_run.call_deferred()


func _run() -> void:
	var audio := root.get_node_or_null("AudioManager")
	if audio == null:
		push_error("AudioManager autoload not found — cannot run tests.")
		quit(1)
		return

	_test_buses_created(audio)
	_test_volume_get_set(audio)
	_test_volume_clamping(audio)
	_test_volume_signal(audio)
	_test_unknown_bus(audio)
	_test_sound_registration(audio)
	_test_sound_override(audio)
	_test_playback_no_crash(audio)
	_test_music_registration_and_play(audio)
	_test_persistence_round_trip(audio)

	print("\n----------------------------------------")
	print("%d assertions, %d failed" % [_passed + _failed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_buses_created(audio: Node) -> void:
	_check(AudioServer.get_bus_index("Master") == 0, "Master bus is index 0")
	_check(AudioServer.get_bus_index(audio.BUS_MUSIC) >= 0, "Music bus exists")
	_check(AudioServer.get_bus_index(audio.BUS_SFX) >= 0, "SFX bus exists")
	_check(AudioServer.get_bus_index(audio.BUS_UI) >= 0, "UI bus exists")


func _test_volume_get_set(audio: Node) -> void:
	audio.set_bus_volume(audio.BUS_MASTER, 0.5)
	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_MASTER), 0.5), "get returns set linear volume")

	var idx := AudioServer.get_bus_index(audio.BUS_MASTER)
	_check(not AudioServer.is_bus_mute(idx), "bus is not muted at 0.5")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5)),
		"AudioServer volume_db mirrors the linear value")

	audio.set_bus_volume(audio.BUS_MASTER, 0.0)
	_check(AudioServer.is_bus_mute(idx), "bus is muted at 0.0")
	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_MASTER), 0.0), "get returns 0.0 when muted")

	audio.set_bus_volume(audio.BUS_MASTER, 1.0)  # restore


func _test_volume_clamping(audio: Node) -> void:
	audio.set_bus_volume(audio.BUS_SFX, 1.5)
	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_SFX), 1.0), "above-range volume clamps to 1.0")
	audio.set_bus_volume(audio.BUS_SFX, -0.3)
	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_SFX), 0.0), "below-range volume clamps to 0.0")
	audio.set_bus_volume(audio.BUS_SFX, 1.0)  # restore


func _test_volume_signal(audio: Node) -> void:
	var captured: Array = []
	var cb := func(bus: String, linear: float) -> void: captured.append([bus, linear])
	audio.bus_volume_changed.connect(cb)
	audio.set_bus_volume(audio.BUS_UI, 0.7)
	audio.bus_volume_changed.disconnect(cb)
	_check(captured.size() == 1, "bus_volume_changed emitted once")
	_check(captured.size() == 1 and captured[0][0] == audio.BUS_UI, "signal carries the bus name")
	_check(captured.size() == 1 and is_equal_approx(captured[0][1], 0.7), "signal carries the linear value")
	audio.set_bus_volume(audio.BUS_UI, 1.0)  # restore


func _test_unknown_bus(audio: Node) -> void:
	# Setting an unmanaged bus is a no-op (warns); getting one returns the 1.0 default.
	audio.set_bus_volume("DoesNotExist", 0.2)
	_check(is_equal_approx(audio.get_bus_volume("DoesNotExist"), 1.0), "unknown bus returns default 1.0")


func _test_sound_registration(audio: Node) -> void:
	var stream := AudioStreamGenerator.new()
	audio.register_sound("test_shoot", stream)
	_check(audio.has_sound("test_shoot"), "registered sound is found")
	_check(audio.get_sound_names().has("test_shoot"), "registered sound appears in name list")
	_check(not audio.has_sound("never_registered"), "unregistered sound is absent")

	# Null / empty-name registrations are rejected (these emit push_error — expected).
	audio.register_sound("", stream)
	_check(not audio.has_sound(""), "empty-name sound rejected")
	audio.register_sound("bad", null)
	_check(not audio.has_sound("bad"), "null-stream sound rejected")


func _test_sound_override(audio: Node) -> void:
	var first := AudioStreamGenerator.new()
	var second := AudioStreamGenerator.new()
	audio.register_sound("override_me", first)
	var before: int = audio.get_sound_names().size()
	audio.register_sound("override_me", second)  # mod override, same id
	var after: int = audio.get_sound_names().size()
	_check(before == after, "re-registering an id overrides rather than duplicating")
	_check(audio.has_sound("override_me"), "overridden sound still present")


func _test_playback_no_crash(audio: Node) -> void:
	audio.register_sound("playable", AudioStreamGenerator.new())
	audio.play_sfx("playable")
	audio.play_ui("playable")
	_check(true, "play_sfx / play_ui on a registered sound do not crash")
	# Unknown sound warns but must not crash (warning is expected).
	audio.play_sfx("not_there")
	_check(true, "play_sfx on an unknown sound does not crash")


func _test_music_registration_and_play(audio: Node) -> void:
	audio.register_music("test_menu", AudioStreamGenerator.new())
	_check(audio.has_music("test_menu"), "registered music track is found")

	audio.play_music("test_menu", 0.0)
	_check(audio.get_current_track() == "test_menu", "play_music sets the current track")

	audio.play_music("missing_track", 0.0)  # warns, no change
	_check(audio.get_current_track() == "test_menu", "unknown track leaves current track unchanged")

	audio.stop_music(0.0)
	_check(audio.get_current_track() == "", "stop_music clears the current track")


func _test_persistence_round_trip(audio: Node) -> void:
	audio.set_bus_volume(audio.BUS_MASTER, 0.42)
	audio.set_bus_volume(audio.BUS_MUSIC, 0.13)
	audio.save_settings()

	# Mutate in memory, then reload from disk and confirm the saved values win.
	audio.set_bus_volume(audio.BUS_MASTER, 0.99)
	audio.set_bus_volume(audio.BUS_MUSIC, 0.99)
	audio.load_settings()

	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_MASTER), 0.42), "Master volume persisted across save/load")
	_check(is_equal_approx(audio.get_bus_volume(audio.BUS_MUSIC), 0.13), "Music volume persisted across save/load")

	# Clean up the settings file so the test leaves no state behind.
	DirAccess.remove_absolute("user://settings.cfg")
	audio.set_bus_volume(audio.BUS_MASTER, 1.0)
	audio.set_bus_volume(audio.BUS_MUSIC, 1.0)


# ---------------------------------------------------------------------------
# Assertion helper
# ---------------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % label)
	else:
		_failed += 1
		printerr("  FAIL: %s" % label)

extends Node

## Central audio service: owns the bus layout, plays one-shot SFX / UI cues,
## crossfades music, and persists per-bus volumes to disk.
##
## Sounds and music are registered by mods (and the base game) the same way
## stats and levels are — there is no fixed enum. Mods may also re-register an
## existing name to override a built-in sound. Foundation for the audio epic
## (#14): gameplay SFX hookup (#30) and music tracks (#31) build on this.

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"

## Bus names managed by the AudioManager. "Master" always exists in Godot;
## the rest are created at runtime and routed to Master if absent.
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

const MANAGED_BUSES: Array[String] = [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_UI]

## Number of pooled SFX players (caps simultaneous one-shot sounds).
const SFX_POOL_SIZE := 16
## Default crossfade duration for music transitions, in seconds.
const DEFAULT_CROSSFADE := 1.0
## Effective-silence volume in dB; faded-out players are driven to this.
const MIN_DB := -80.0

# sound_name -> AudioStream  (one-shot SFX / UI cues)
var _sounds: Dictionary = {}
# track_name -> AudioStream  (looping music)
var _music: Dictionary = {}

# bus_name -> linear volume in [0, 1]. Source of truth; applied to AudioServer.
var _volumes: Dictionary = {
	BUS_MASTER: 1.0,
	BUS_MUSIC: 1.0,
	BUS_SFX: 1.0,
	BUS_UI: 1.0,
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0
# Two music players ping-pong so transitions can crossfade.
var _music_players: Array[AudioStreamPlayer] = []
var _active_music: int = 0
var _current_track: String = ""

signal bus_volume_changed(bus_name: String, linear: float)


func _ready() -> void:
	_ensure_buses()
	_build_players()
	load_settings()


# ---------------------------------------------------------------------------
# Sound / music registration (mod hook)
# ---------------------------------------------------------------------------

## Registers (or overrides) a one-shot SFX / UI cue by name.
func register_sound(sound_name: String, stream: AudioStream) -> void:
	if sound_name.is_empty() or stream == null:
		push_error("AudioManager: register_sound needs a name and a stream.")
		return
	_sounds[sound_name] = stream


## Registers (or overrides) a music track by name.
func register_music(track_name: String, stream: AudioStream) -> void:
	if track_name.is_empty() or stream == null:
		push_error("AudioManager: register_music needs a name and a stream.")
		return
	_music[track_name] = stream


func has_sound(sound_name: String) -> bool:
	return _sounds.has(sound_name)


func has_music(track_name: String) -> bool:
	return _music.has(track_name)


func get_sound_names() -> Array:
	return _sounds.keys()


func get_music_names() -> Array:
	return _music.keys()


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------

## Plays a registered one-shot sound on the given bus (SFX by default).
func play_sfx(sound_name: String, bus: String = BUS_SFX) -> void:
	if not _sounds.has(sound_name):
		push_warning("AudioManager: sound '%s' is not registered." % sound_name)
		return
	if _sfx_pool.is_empty():
		return
	var player := _sfx_pool[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_pool.size()
	player.stream = _sounds[sound_name]
	player.bus = bus
	player.volume_db = 0.0
	player.play()


## Convenience: plays a registered cue on the UI bus.
func play_ui(sound_name: String) -> void:
	play_sfx(sound_name, BUS_UI)


## Crossfades to a registered music track. Re-requesting the current track
## while it is playing is a no-op.
func play_music(track_name: String, crossfade: float = DEFAULT_CROSSFADE) -> void:
	if not _music.has(track_name):
		push_warning("AudioManager: music track '%s' is not registered." % track_name)
		return
	if track_name == _current_track and _music_players[_active_music].playing:
		return
	_current_track = track_name

	var incoming := _music_players[1 - _active_music]
	var outgoing := _music_players[_active_music]
	_active_music = 1 - _active_music

	incoming.stream = _music[track_name]
	incoming.volume_db = MIN_DB
	incoming.play()

	if crossfade <= 0.0:
		incoming.volume_db = 0.0
		outgoing.stop()
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "volume_db", 0.0, crossfade)
	tween.tween_property(outgoing, "volume_db", MIN_DB, crossfade)
	tween.chain().tween_callback(outgoing.stop)


## Fades out and stops the current music track.
func stop_music(fade: float = DEFAULT_CROSSFADE) -> void:
	_current_track = ""
	var player := _music_players[_active_music]
	if fade <= 0.0:
		player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", MIN_DB, fade)
	tween.tween_callback(player.stop)


func get_current_track() -> String:
	return _current_track


# ---------------------------------------------------------------------------
# Volume (linear 0..1) — source of truth mirrored onto the AudioServer
# ---------------------------------------------------------------------------

## Sets a managed bus volume from a linear [0, 1] value. A value of 0 mutes
## the bus. Emits bus_volume_changed.
func set_bus_volume(bus_name: String, linear: float) -> void:
	if not _volumes.has(bus_name):
		push_warning("AudioManager: '%s' is not a managed bus." % bus_name)
		return
	linear = clampf(linear, 0.0, 1.0)
	_volumes[bus_name] = linear
	_apply_bus_volume(bus_name)
	bus_volume_changed.emit(bus_name, linear)


func get_bus_volume(bus_name: String) -> float:
	return _volumes.get(bus_name, 1.0)


func _apply_bus_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear: float = _volumes[bus_name]
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Writes the managed bus volumes to disk, preserving any other settings
## sections already present in the file.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # ignore error: a missing file just starts empty
	for bus: String in MANAGED_BUSES:
		cfg.set_value(SETTINGS_SECTION, bus.to_lower(), _volumes[bus])
	cfg.save(SETTINGS_PATH)


## Loads managed bus volumes from disk (falling back to defaults) and applies
## them to the AudioServer.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(SETTINGS_PATH) == OK
	for bus: String in MANAGED_BUSES:
		var fallback: float = _volumes.get(bus, 1.0)
		var value: float = fallback
		if ok:
			value = float(cfg.get_value(SETTINGS_SECTION, bus.to_lower(), fallback))
		_volumes[bus] = clampf(value, 0.0, 1.0)
		_apply_bus_volume(bus)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _ensure_buses() -> void:
	for bus: String in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, BUS_MASTER)


func _build_players() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_pool.append(player)

	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		add_child(player)
		_music_players.append(player)

extends Node

## Global display / window configuration (#83).
##
## Owns the window's fullscreen mode and minimum size, and persists the player's
## fullscreen preference to `user://settings.cfg`. The rendered scene scales to
## the window while preserving the 16:9 base resolution — the project uses stretch
## mode `canvas_items` with aspect `keep`, so any non-16:9 window is letter-/
## pillarboxed rather than stretched.
##
## Because gameplay always runs in the fixed base viewport space (1280x720), its
## physics is identical regardless of the resolution the game is displayed at.
## The letterbox / window-clamp math is exposed as pure static helpers so that
## invariance — and the 16:9 and minimum-size guarantees — can be unit-tested
## without a live window.

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "display"
const FULLSCREEN_KEY := "fullscreen"

## Base render resolution (16:9). Matches `window/size/viewport_*` in project.godot.
const BASE_WIDTH := 1280
const BASE_HEIGHT := 720

## Minimum windowed size (also 16:9). The window cannot be shrunk below this.
const MIN_WIDTH := 480
const MIN_HEIGHT := 270

var _fullscreen := false


func _ready() -> void:
	_apply_min_window_size()
	load_settings()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func is_fullscreen() -> bool:
	return _fullscreen


## Enables or disables fullscreen and applies it to the live window.
func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	_apply_window_mode()


func toggle_fullscreen() -> void:
	set_fullscreen(not _fullscreen)


# ---------------------------------------------------------------------------
# Pure scaling helpers (no live window — unit-testable)
# ---------------------------------------------------------------------------

## Aspect ratio of the base render resolution (16:9 -> ~1.777...).
static func base_aspect() -> float:
	return float(BASE_WIDTH) / float(BASE_HEIGHT)


## Uniform content scale that fits `base_size` inside `window_size` without
## distortion: the smaller of the two per-axis ratios, so the base always fits
## and aspect is preserved. The leftover area is the letter-/pillarbox border.
static func content_scale(window_size: Vector2, base_size := Vector2(BASE_WIDTH, BASE_HEIGHT)) -> float:
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		return 1.0
	return minf(window_size.x / base_size.x, window_size.y / base_size.y)


## Centred rectangle (in window pixels) that the base resolution is drawn into.
## Any window area outside this rect is the letter-/pillarbox border.
static func viewport_rect(window_size: Vector2, base_size := Vector2(BASE_WIDTH, BASE_HEIGHT)) -> Rect2:
	var scale := content_scale(window_size, base_size)
	var drawn := base_size * scale
	var origin := (window_size - drawn) * 0.5
	return Rect2(origin, drawn)


## Maps a base/world coordinate to a window-pixel coordinate for a given window
## size. The inverse `screen_to_world` round-trips identically at any resolution,
## which is what makes gameplay coordinates resolution-independent.
static func world_to_screen(world_pos: Vector2, window_size: Vector2, base_size := Vector2(BASE_WIDTH, BASE_HEIGHT)) -> Vector2:
	var rect := viewport_rect(window_size, base_size)
	return rect.position + world_pos * content_scale(window_size, base_size)


static func screen_to_world(screen_pos: Vector2, window_size: Vector2, base_size := Vector2(BASE_WIDTH, BASE_HEIGHT)) -> Vector2:
	var scale := content_scale(window_size, base_size)
	if scale <= 0.0:
		return Vector2.ZERO
	var rect := viewport_rect(window_size, base_size)
	return (screen_pos - rect.position) / scale


## Clamps a requested window size up to the minimum supported size on each axis.
static func clamp_window_size(size: Vector2i, min_size := Vector2i(MIN_WIDTH, MIN_HEIGHT)) -> Vector2i:
	return Vector2i(maxi(size.x, min_size.x), maxi(size.y, min_size.y))


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Writes the fullscreen preference to disk, preserving other settings sections.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # ignore error: a missing file just starts empty
	cfg.set_value(SETTINGS_SECTION, FULLSCREEN_KEY, _fullscreen)
	cfg.save(SETTINGS_PATH)


## Loads the fullscreen preference (falling back to windowed) and applies it.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_fullscreen = bool(cfg.get_value(SETTINGS_SECTION, FULLSCREEN_KEY, _fullscreen))
	_apply_window_mode()


# ---------------------------------------------------------------------------
# Live window application
# ---------------------------------------------------------------------------

func _apply_window_mode() -> void:
	var win := get_window()
	if win == null or not _has_real_window():
		return
	win.mode = Window.MODE_FULLSCREEN if _fullscreen else Window.MODE_WINDOWED


func _apply_min_window_size() -> void:
	var win := get_window()
	if win == null or not _has_real_window():
		return
	win.min_size = Vector2i(MIN_WIDTH, MIN_HEIGHT)


## False under the headless display server (tests / dedicated server), where
## window mutations are unsupported no-ops.
func _has_real_window() -> bool:
	return DisplayServer.get_name() != "headless"

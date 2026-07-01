extends Node

## Global gameplay-preference store (#169). Currently owns the card-pick
## presentation mode (Auto / One By One / All At Once) chosen in the Options menu,
## persisted to `user://settings.cfg` alongside the display settings under its own
## section. Mirrors the `DisplaySettings` persistence pattern; the mode's decision
## logic lives in the pure `CardPickMode` helpers, so this autoload is only the
## stored-preference seam the Options screen writes and the match reads.

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "gameplay"
const CARD_PICK_MODE_KEY := "card_pick_mode"

## The stored card-pick setting: one of `CardPickMode.AUTO` / `SEQUENTIAL` /
## `PARALLEL`. Defaults to AUTO (the adaptive default by player count).
var card_pick_mode: String = CardPickMode.AUTO


func _ready() -> void:
	load_settings()


## Sets the card-pick mode setting, normalising any unrecognised value to AUTO.
func set_card_pick_mode(mode: String) -> void:
	card_pick_mode = CardPickMode.normalize_setting(mode)


## Writes the gameplay preferences to disk, preserving other settings sections
## (the display section owned by `DisplaySettings` shares the same file).
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # ignore error: a missing file just starts empty
	cfg.set_value(SETTINGS_SECTION, CARD_PICK_MODE_KEY, card_pick_mode)
	cfg.save(SETTINGS_PATH)


## Loads the stored card-pick setting (falling back to AUTO), coercing any stale
## or hand-edited value to a known setting.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		card_pick_mode = CardPickMode.normalize_setting(
			String(cfg.get_value(SETTINGS_SECTION, CARD_PICK_MODE_KEY, card_pick_mode)))

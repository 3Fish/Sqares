extends Control

## Local match-setup screen (#26): pick a game mode, player count, number of
## rounds, and arena, then start the match. The choice is written to the
## MatchConfig autoload and `scenes/match.tscn` is loaded, which MatchDirector
## consumes one-shot in `_ready`.
##
## This ships the general, mode-independent setup options plus a game-mode-specific
## options submenu (#133) — currently the friendly-fire toggle (#62), which is only
## meaningful for modes that group players into shared teams. The wider lobby —
## online host/join + roster (#66/#82), per-player name + colour (#132), save/load
## of configurations (#135), and manual / N-team assignment (#134) — is deferred to
## dedicated follow-ups. Host-only visibility of the submenu (others see but cannot
## edit) only becomes meaningful with the online lobby; locally the single operator
## edits it directly.
##
## Controls are built in code (like options_menu.gd) to keep the scene minimal.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"

## Fallback options when the registries are empty (e.g. before mods have loaded).
## The base game registers exactly these.
const FALLBACK_MODES := ["ffa", "teams"]
const FALLBACK_ARENAS := ["crossroads"]

var _mode_picker: OptionButton
var _player_picker: OptionButton
var _rounds_picker: SpinBox
var _arena_picker: OptionButton
var _mode_options_button: Button
var _mode_options_popup: PopupPanel
var _friendly_fire_toggle: CheckButton

# Saved match configurations (#135).
var _config_name_edit: LineEdit
var _config_picker: OptionButton
var _overwrite_dialog: ConfirmationDialog

# Parallel arrays: picker item index -> registered id.
var _mode_ids: Array = []
var _arena_ids: Array = []
# Saved-config picker item index -> stored display name (#135).
var _config_names: Array = []
# Name awaiting an overwrite-confirm answer (#135 A3).
var _pending_save_name: String = ""

# Staged mode-specific options (written into MatchConfig on start).
var _friendly_fire: bool = true


func _ready() -> void:
	_mode_ids = _ids_or_fallback(GameModeRegistry.get_all_ids(), FALLBACK_MODES)
	_arena_ids = _ids_or_fallback(LevelRegistry.get_all_ids(), FALLBACK_ARENAS)

	var bg := ColorRect.new()
	bg.color = Color(0.102, 0.102, 0.18, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(360, 0)
	add_child(vbox)

	var title := Label.new()
	title.text = "Match Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	_mode_picker = _add_option_row(vbox, "Game Mode", _mode_labels())
	_player_picker = _add_option_row(vbox, "Players", ["2", "3", "4"])
	_rounds_picker = _add_spin_row(vbox, "Rounds to win",
		MatchConfig.MIN_WINS, MatchConfig.MAX_WINS, MatchConfig.DEFAULT_WINS)
	_arena_picker = _add_option_row(vbox, "Arena", _arena_labels())

	# Mode-specific options submenu (#133). Only enabled for modes that group
	# players into shared teams (so friendly fire is meaningful); inert for FFA.
	_mode_options_button = Button.new()
	_mode_options_button.text = "Mode Options"
	_mode_options_button.pressed.connect(_on_mode_options_pressed)
	vbox.add_child(_mode_options_button)

	_mode_options_popup = _build_mode_options_popup()
	add_child(_mode_options_popup)

	# Default selections: FFA, 2 players, default arena.
	_mode_picker.select(maxi(0, _mode_ids.find(MatchConfig.DEFAULT_MODE)))
	_player_picker.select(0)
	_arena_picker.select(maxi(0, _arena_ids.find(MatchConfig.DEFAULT_ARENA)))

	# Keep the submenu availability in sync with the selected mode.
	_mode_picker.item_selected.connect(_on_mode_selected)
	_refresh_mode_options_availability()

	# Saved match configurations (#135).
	_build_config_rows(vbox)

	var start := Button.new()
	start.text = "Start"
	start.pressed.connect(_on_start_pressed)
	vbox.add_child(start)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	vbox.add_child(back)


func _on_start_pressed() -> void:
	# Player picker index 0 -> 2 players, 1 -> 3, 2 -> 4.
	var players := _player_picker.selected + 2
	var rounds := int(_rounds_picker.value)
	MatchConfig.configure(_current_mode_id(), players, rounds, _current_arena_id(), _friendly_fire)
	get_tree().change_scene_to_file(MATCH_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## The currently-selected game-mode id, or the default when nothing is selected.
func _current_mode_id() -> String:
	return String(_mode_ids[_mode_picker.selected]) \
		if _mode_picker.selected >= 0 else MatchConfig.DEFAULT_MODE


## The currently-selected arena id, or the default when nothing is selected.
func _current_arena_id() -> String:
	return String(_arena_ids[_arena_picker.selected]) \
		if _arena_picker.selected >= 0 else MatchConfig.DEFAULT_ARENA


# ---------------------------------------------------------------------------
# Saved match configurations (#135)
# ---------------------------------------------------------------------------

## Builds the save/load row: a name field + Save button, and a load picker with
## Load + Delete buttons. A saved config is a reusable match *template* (mode +
## general & mode-specific options); player count and per-player info are not
## persisted (maintainer A2), so loading a config leaves the current roster
## selection untouched.
func _build_config_rows(parent: Node) -> void:
	var heading := Label.new()
	heading.text = "Saved Configs"
	parent.add_child(heading)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	_config_name_edit = LineEdit.new()
	_config_name_edit.placeholder_text = "Config name"
	_config_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_config_name_edit)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_config_pressed)
	save_row.add_child(save_button)
	parent.add_child(save_row)

	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	_config_picker = OptionButton.new()
	_config_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_config_picker)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_config_pressed)
	load_row.add_child(load_button)
	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(_on_delete_config_pressed)
	load_row.add_child(delete_button)
	parent.add_child(load_row)

	# A name collision prompts before clobbering an existing file (A3).
	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.title = "Overwrite config?"
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_dialog)

	_refresh_config_list()


## Repopulates the load picker from the stored configs on disk.
func _refresh_config_list() -> void:
	_config_names = MatchConfigStore.list_names()
	_config_picker.clear()
	for name: String in _config_names:
		_config_picker.add_item(name)
	if not _config_names.is_empty():
		_config_picker.select(0)


func _on_save_config_pressed() -> void:
	# Blank name -> an auto-generated, non-colliding default (A3).
	var name := _config_name_edit.text.strip_edges()
	if name.is_empty():
		name = MatchConfig.default_config_name(_config_names)
		_config_name_edit.text = name
	# A name that slugifies to nothing (e.g. only punctuation) can't be saved.
	if MatchConfigStore.sanitize_name(name).is_empty():
		return
	if MatchConfigStore.exists(name):
		_pending_save_name = name
		_overwrite_dialog.dialog_text = "A config named \"%s\" already exists. Overwrite it?" % name
		_overwrite_dialog.popup_centered()
		return
	_do_save_config(name)


func _on_overwrite_confirmed() -> void:
	if not _pending_save_name.is_empty():
		_do_save_config(_pending_save_name)
		_pending_save_name = ""


## Serialises the current selection (mode + general & mode-specific options) and
## writes it under `name`, then refreshes the load picker and selects the saved
## entry.
func _do_save_config(name: String) -> void:
	var data := MatchConfig.to_dict(
		_current_mode_id(), int(_rounds_picker.value), _current_arena_id(), _friendly_fire)
	if MatchConfigStore.save(name, data) != OK:
		return
	_refresh_config_list()
	var idx := _config_names.find(name)
	if idx >= 0:
		_config_picker.select(idx)


func _on_load_config_pressed() -> void:
	if _config_picker.selected < 0 or _config_picker.selected >= _config_names.size():
		return
	var data := MatchConfigStore.load_config(String(_config_names[_config_picker.selected]))
	if data.is_empty():
		# File vanished (e.g. deleted externally) — keep the list honest.
		_refresh_config_list()
		return
	_apply_config(MatchConfig.normalize_dict(data, _mode_ids, _arena_ids))


## Applies a normalised config dict to the setup controls (#135). Mode/arena are
## already resolved to registered ids and wins clamped by `normalize_dict`, so the
## pickers always land on a real entry. Player count is intentionally left as-is.
func _apply_config(norm: Dictionary) -> void:
	_mode_picker.select(maxi(0, _mode_ids.find(String(norm["game_mode"]))))
	_arena_picker.select(maxi(0, _arena_ids.find(String(norm["arena_id"]))))
	_rounds_picker.value = int(norm["wins_needed"])
	_friendly_fire = bool(norm["friendly_fire"])
	# A loaded mode may differ from the previous one; re-evaluate the submenu.
	_refresh_mode_options_availability()


func _on_delete_config_pressed() -> void:
	if _config_picker.selected < 0 or _config_picker.selected >= _config_names.size():
		return
	MatchConfigStore.delete(String(_config_names[_config_picker.selected]))
	_refresh_config_list()


# ---------------------------------------------------------------------------
# Mode-specific options submenu (#133)
# ---------------------------------------------------------------------------

func _on_mode_options_pressed() -> void:
	# Reflect the staged value into the toggle before showing the submenu.
	_friendly_fire_toggle.button_pressed = _friendly_fire
	_mode_options_popup.popup_centered()


func _on_friendly_fire_toggled(pressed: bool) -> void:
	_friendly_fire = pressed


func _on_mode_selected(_index: int) -> void:
	_refresh_mode_options_availability()


## Enables the submenu button only when the selected mode groups players into
## shared teams (so its team-only options, e.g. friendly fire, are meaningful).
## Evaluated at the maximum roster so the answer is mode-level, not tied to the
## currently-selected player count.
func _refresh_mode_options_availability() -> void:
	var groups := mode_groups_players(_selected_mode_script(), MatchDirector.MAX_PLAYERS)
	_mode_options_button.disabled = not groups
	_mode_options_button.tooltip_text = "" if groups \
		else "No mode-specific options for this game mode."
	# A non-team mode (FFA) leaves friendly fire moot; it is ignored downstream.


func _selected_mode_script() -> GDScript:
	if _mode_picker == null or _mode_picker.selected < 0:
		return null
	return GameModeRegistry.get_mode(String(_mode_ids[_mode_picker.selected]))


func _build_mode_options_popup() -> PopupPanel:
	var popup := PopupPanel.new()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(300, 0)
	popup.add_child(box)

	var heading := Label.new()
	heading.text = "Mode Options"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	box.add_child(heading)

	_friendly_fire_toggle = CheckButton.new()
	_friendly_fire_toggle.text = "Friendly fire"
	_friendly_fire_toggle.button_pressed = _friendly_fire
	_friendly_fire_toggle.toggled.connect(_on_friendly_fire_toggled)
	box.add_child(_friendly_fire_toggle)

	var hint := Label.new()
	hint.text = "When on, team-mates can damage each other."
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)

	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(popup.hide)
	box.add_child(done)
	return popup


# ---------------------------------------------------------------------------
# UI builders
# ---------------------------------------------------------------------------

func _add_option_row(parent: Node, label_text: String, options: Array) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var picker := OptionButton.new()
	for opt: String in options:
		picker.add_item(opt)
	picker.custom_minimum_size = Vector2(320, 0)
	parent.add_child(picker)
	return picker


func _add_spin_row(parent: Node, label_text: String, min_v: int, max_v: int, default_v: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.value = default_v
	spin.custom_minimum_size = Vector2(320, 0)
	parent.add_child(spin)
	return spin


# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

## Human-readable labels for the mode picker: each mode's own `display_name` when
## resolvable, else a titleised id.
func _mode_labels() -> Array:
	var labels: Array = []
	for id: String in _mode_ids:
		var script: GDScript = GameModeRegistry.get_mode(id)
		var label := String(id).capitalize()
		if script:
			var mode: Object = script.new()
			if mode is GameMode:
				label = (mode as GameMode).display_name
		labels.append(label)
	return labels


func _arena_labels() -> Array:
	var labels: Array = []
	for id: String in _arena_ids:
		labels.append(String(id).capitalize())
	return labels


## Returns a copy of `ids`, or a copy of `fallback` when `ids` is empty.
static func _ids_or_fallback(ids: Array, fallback: Array) -> Array:
	return ids.duplicate() if not ids.is_empty() else fallback.duplicate()


## True when `mode_script` assigns two or more players to a shared team at the
## given roster size — i.e. the mode has team-mates, so team-only options such as
## friendly fire are meaningful. FFA gives every player their own team (false);
## Teams groups them (true). Generic over modded modes via `assign_teams` rather
## than matching a mode id; a null / non-`GameMode` script is treated as no teams.
static func mode_groups_players(mode_script: GDScript, player_count: int) -> bool:
	if mode_script == null:
		return false
	var mode: Object = mode_script.new()
	if not (mode is GameMode):
		return false
	var teams: Dictionary = (mode as GameMode).assign_teams(player_count)
	var distinct: Dictionary = {}
	for pid: int in teams:
		distinct[teams[pid]] = true
	return distinct.size() < teams.size()

extends Control

## Local match-setup screen (#26): pick a game mode, player count, number of
## rounds, and arena, then start the match. The choice is written to the
## MatchConfig autoload and `scenes/match.tscn` is loaded, which MatchDirector
## consumes one-shot in `_ready`.
##
## This ships the general, mode-independent setup options for local play. The
## wider lobby — online host/join + roster (#66/#82), per-player name + colour,
## a host-only game-mode-specific options submenu (the friendly-fire toggle #62
## lives there), save/load of configurations, and manual / N-team assignment —
## is deferred to dedicated follow-ups.
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

# Parallel arrays: picker item index -> registered id.
var _mode_ids: Array = []
var _arena_ids: Array = []


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

	# Default selections: FFA, 2 players, default arena.
	_mode_picker.select(maxi(0, _mode_ids.find(MatchConfig.DEFAULT_MODE)))
	_player_picker.select(0)
	_arena_picker.select(maxi(0, _arena_ids.find(MatchConfig.DEFAULT_ARENA)))

	var start := Button.new()
	start.text = "Start"
	start.pressed.connect(_on_start_pressed)
	vbox.add_child(start)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	vbox.add_child(back)


func _on_start_pressed() -> void:
	var mode_id: String = String(_mode_ids[_mode_picker.selected]) \
		if _mode_picker.selected >= 0 else MatchConfig.DEFAULT_MODE
	var arena_id: String = String(_arena_ids[_arena_picker.selected]) \
		if _arena_picker.selected >= 0 else MatchConfig.DEFAULT_ARENA
	# Player picker index 0 -> 2 players, 1 -> 3, 2 -> 4.
	var players := _player_picker.selected + 2
	var rounds := int(_rounds_picker.value)
	MatchConfig.configure(mode_id, players, rounds, arena_id)
	get_tree().change_scene_to_file(MATCH_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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

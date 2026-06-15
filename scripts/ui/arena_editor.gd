extends Control

## Arena editor UI shell (#34): a grid canvas with pan & zoom, plus Save / Load
## buttons wired to the arena data format (`ArenaData` + `ArenaStore`).
##
## This is the editor *shell*. It can create a blank arena, view/pan/zoom the
## canvas, and persist arenas to / from `user://arenas/`. The placement and
## editing tools that add platforms, spawns and kill zones are #35; validation +
## the in-match playtest are #36. Controls are built in code to keep the scene
## file minimal, matching `options_menu.gd`.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"
## Fallback id when playtesting an arena that has no id / name yet.
const PLAYTEST_FALLBACK_ID := "playtest"

var _canvas: ArenaEditorCanvas
var _id_field: LineEdit
var _name_field: LineEdit
var _load_picker: OptionButton
var _status: Label
var _tool_group: ButtonGroup

# Per-element property inspector (#72).
var _inspector_type: Label
var _pos_row: Control
var _size_row: Control
var _color_row: Control
var _pos_x: SpinBox
var _pos_y: SpinBox
var _size_w: SpinBox
var _size_h: SpinBox
var _color_btn: ColorPickerButton
## True while the inspector is being repopulated, so programmatic widget updates
## don't echo back as user edits.
var _refreshing: bool = false


func _ready() -> void:
	ArenaStore.ensure_dir()

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_toolbar())

	_canvas = ArenaEditorCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.arena_modified.connect(_on_arena_modified)
	_canvas.selection_changed.connect(_on_selection_changed)

	root.add_child(_build_tool_bar())

	# Canvas + property inspector share the remaining vertical space.
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_canvas)
	body.add_child(_build_inspector())
	root.add_child(body)

	_new_arena()
	_refresh_load_picker()
	_refresh_inspector(_canvas.sel_kind, _canvas.sel_index)


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Arena Editor"
	title.add_theme_font_size_override("font_size", 20)
	bar.add_child(title)

	_id_field = LineEdit.new()
	_id_field.placeholder_text = "id"
	_id_field.custom_minimum_size = Vector2(120, 0)
	bar.add_child(_id_field)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "display name"
	_name_field.custom_minimum_size = Vector2(160, 0)
	bar.add_child(_name_field)

	bar.add_child(_make_button("New", _new_arena))
	bar.add_child(_make_button("Save", _on_save))

	_load_picker = OptionButton.new()
	_load_picker.custom_minimum_size = Vector2(140, 0)
	bar.add_child(_load_picker)
	bar.add_child(_make_button("Load", _on_load))

	bar.add_child(_make_button("Frame", func() -> void: _canvas.frame_content()))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)

	bar.add_child(_make_button("Back", _on_back))
	return bar


func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	return btn


## A second toolbar row: the placement-tool palette + delete.
func _build_tool_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = "Tools:"
	bar.add_child(label)

	_tool_group = ButtonGroup.new()
	bar.add_child(_make_tool_button("Select", ArenaEditTools.Tool.SELECT, true))
	bar.add_child(_make_tool_button("Platform", ArenaEditTools.Tool.PLATFORM, false))
	bar.add_child(_make_tool_button("Spawn", ArenaEditTools.Tool.SPAWN, false))
	bar.add_child(_make_tool_button("Kill Zone", ArenaEditTools.Tool.KILL_ZONE, false))

	var sep := VSeparator.new()
	bar.add_child(sep)
	bar.add_child(_make_button("Delete", _on_delete))
	bar.add_child(_make_button("Undo", _on_undo))
	bar.add_child(_make_button("Redo", _on_redo))

	var sep2 := VSeparator.new()
	bar.add_child(sep2)
	bar.add_child(_make_button("Validate", _on_validate))
	bar.add_child(_make_button("Playtest", _on_playtest))

	var hint := Label.new()
	hint.text = "  (left: place/edit · middle/right drag: pan · wheel: zoom · Del: delete · Ctrl+Z/Y: undo/redo)"
	hint.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(hint)
	return bar


func _make_tool_button(text: String, tool_id: int, pressed: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_group = _tool_group
	btn.button_pressed = pressed
	btn.pressed.connect(func() -> void: _on_tool_selected(tool_id))
	return btn


func _on_tool_selected(tool_id: int) -> void:
	_canvas.set_tool(tool_id)


func _on_delete() -> void:
	if _canvas.delete_selected():
		_set_status("Deleted selection")


func _on_undo() -> void:
	if not _canvas.undo():
		_set_status("Nothing to undo")


func _on_redo() -> void:
	if not _canvas.redo():
		_set_status("Nothing to redo")


func _on_arena_modified() -> void:
	var a := _canvas.arena
	_set_status("%d platform(s), %d spawn(s), %d kill zone(s)" % [
		a.platforms.size(), a.spawn_points.size(), a.kill_zones.size()
	])
	# Geometry may have moved/resized under a live selection (drag, undo/redo);
	# keep the inspector's numbers in sync with the canonical values.
	_refresh_inspector(_canvas.sel_kind, _canvas.sel_index)


# --- Property inspector (#72) ----------------------------------------------

## Build the right-hand panel that numerically edits the selected element's
## position, size (platforms / kill zones) and colour (platforms). Widget
## changes route through the canvas so each edit is one undoable step.
func _build_inspector() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Inspector"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_inspector_type = Label.new()
	_inspector_type.text = "No selection"
	vbox.add_child(_inspector_type)

	_pos_x = _make_spin(true)
	_pos_y = _make_spin(true)
	_pos_x.value_changed.connect(func(_v: float) -> void: _on_position_field_changed())
	_pos_y.value_changed.connect(func(_v: float) -> void: _on_position_field_changed())
	_pos_row = _make_field_row("Position", [_labeled("X", _pos_x), _labeled("Y", _pos_y)])
	vbox.add_child(_pos_row)

	_size_w = _make_spin(false)
	_size_h = _make_spin(false)
	_size_w.value_changed.connect(func(_v: float) -> void: _on_size_field_changed())
	_size_h.value_changed.connect(func(_v: float) -> void: _on_size_field_changed())
	_size_row = _make_field_row("Size", [_labeled("W", _size_w), _labeled("H", _size_h)])
	vbox.add_child(_size_row)

	_color_btn = ColorPickerButton.new()
	_color_btn.custom_minimum_size = Vector2(0, 28)
	_color_btn.color_changed.connect(func(c: Color) -> void: _on_color_field_changed(c))
	_color_row = _make_field_row("Colour", [_color_btn])
	vbox.add_child(_color_row)

	return panel


## A numeric field. `allow_negative` widens the range for position coordinates;
## size fields are floored at the editor's minimum rectangle extent.
func _make_spin(allow_negative: bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.step = 1.0
	spin.allow_greater = true
	spin.max_value = 100000.0
	if allow_negative:
		spin.allow_lesser = true
		spin.min_value = -100000.0
	else:
		spin.min_value = ArenaEditTools.MIN_RECT_SIZE.x
	spin.custom_minimum_size = Vector2(64, 0)
	return spin


func _labeled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(16, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_field_row(title: String, children: Array) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(label)
	for child in children:
		box.add_child(child)
	return box


func _on_selection_changed(kind: int, index: int) -> void:
	_refresh_inspector(kind, index)


## Repopulate the inspector for the given selection, showing only the fields the
## element actually has. `_refreshing` suppresses the echo from setting widgets.
func _refresh_inspector(kind: int, index: int) -> void:
	_refreshing = true
	if kind == ArenaEditTools.Kind.NONE or index < 0:
		_inspector_type.text = "No selection"
		_pos_row.visible = false
		_size_row.visible = false
		_color_row.visible = false
	else:
		_inspector_type.text = _kind_label(kind)
		var pos: Vector2 = ArenaEditTools.element_position(_canvas.arena, kind, index)
		_pos_x.value = pos.x
		_pos_y.value = pos.y
		_pos_row.visible = true

		_size_row.visible = ArenaEditTools.has_size(kind)
		if _size_row.visible:
			var sz: Vector2 = ArenaEditTools.element_size(_canvas.arena, kind, index)
			_size_w.value = sz.x
			_size_h.value = sz.y

		_color_row.visible = ArenaEditTools.has_color(kind)
		if _color_row.visible:
			_color_btn.color = ArenaEditTools.element_color(_canvas.arena, kind, index)
	_refreshing = false


func _on_position_field_changed() -> void:
	if _refreshing:
		return
	_canvas.set_selected_position(Vector2(_pos_x.value, _pos_y.value))


func _on_size_field_changed() -> void:
	if _refreshing:
		return
	_canvas.set_selected_size(Vector2(_size_w.value, _size_h.value))


func _on_color_field_changed(color: Color) -> void:
	if _refreshing:
		return
	_canvas.set_selected_color(color)


func _kind_label(kind: int) -> String:
	match kind:
		ArenaEditTools.Kind.PLATFORM: return "Platform"
		ArenaEditTools.Kind.SPAWN: return "Spawn point"
		ArenaEditTools.Kind.KILL_ZONE: return "Kill zone"
	return "Selection"


func _new_arena() -> void:
	_canvas.set_arena(ArenaData.new())
	_canvas.frame_content()
	_id_field.text = ""
	_name_field.text = ""
	_set_status("New arena")


func _on_save() -> void:
	_sync_meta()
	var err := ArenaStore.save(_canvas.arena)
	if err != OK:
		_set_status("Save failed (error %d)" % err)
		return
	# ArenaStore back-fills a sanitised id when one was missing; reflect it.
	_id_field.text = _canvas.arena.id
	_refresh_load_picker()
	_select_in_picker(_canvas.arena.id)
	# Validate before reporting (#36) so the user sees what still needs fixing.
	var issues := ArenaValidator.validate(_canvas.arena)
	if issues.is_empty():
		_set_status("Saved '%s' — valid" % _canvas.arena.id)
	else:
		_set_status("Saved '%s' — %d error(s), %d warning(s)" % [
			_canvas.arena.id,
			ArenaValidator.count(issues, ArenaValidator.Severity.ERROR),
			ArenaValidator.count(issues, ArenaValidator.Severity.WARNING),
		])


## Report validation results without saving or launching.
func _on_validate() -> void:
	_sync_meta()
	_set_status(ArenaValidator.summarize(ArenaValidator.validate(_canvas.arena)))


## Launch a match on the edited arena (#36). Refuses if validation finds errors;
## otherwise registers the arena and hands it to a fresh match via MatchDirector.
func _on_playtest() -> void:
	_sync_meta()
	var issues := ArenaValidator.validate(_canvas.arena)
	if ArenaValidator.has_errors(issues):
		_set_status("Cannot playtest:\n" + ArenaValidator.summarize(issues))
		return
	_ensure_id()
	if not LevelRegistry.register_arena_data(_canvas.arena):
		_set_status("Playtest failed: could not register arena")
		return
	MatchDirector.pending_arena_id = _canvas.arena.id
	get_tree().change_scene_to_file(MATCH_SCENE)


## Copy the id / name fields into the live arena before save / validate / play.
func _sync_meta() -> void:
	_canvas.arena.id = _id_field.text
	_canvas.arena.display_name = _name_field.text


## Guarantee the arena has a non-empty, file-safe id so it can be registered and
## launched, deriving one from the name (or a fallback) when none was given.
func _ensure_id() -> void:
	var slug := ArenaStore.sanitize_id(_canvas.arena.id)
	if slug.is_empty():
		slug = ArenaStore.sanitize_id(_canvas.arena.display_name)
	if slug.is_empty():
		slug = PLAYTEST_FALLBACK_ID
	_canvas.arena.id = slug
	_id_field.text = slug


func _on_load() -> void:
	if _load_picker.item_count == 0:
		_set_status("Nothing to load")
		return
	var id := _load_picker.get_item_text(_load_picker.selected)
	var loaded := ArenaStore.load_arena(id)
	if loaded == null:
		_set_status("Could not load '%s'" % id)
		return
	_canvas.set_arena(loaded)
	_canvas.frame_content()
	_id_field.text = loaded.id
	_name_field.text = loaded.display_name
	_set_status("Loaded '%s'" % id)


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _refresh_load_picker() -> void:
	_load_picker.clear()
	for id in ArenaStore.list_ids():
		_load_picker.add_item(id)
	_load_picker.disabled = _load_picker.item_count == 0


func _select_in_picker(id: String) -> void:
	for i in _load_picker.item_count:
		if _load_picker.get_item_text(i) == id:
			_load_picker.selected = i
			return


func _set_status(text: String) -> void:
	_status.text = text

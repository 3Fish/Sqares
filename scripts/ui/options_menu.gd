extends Control

## Options screen: one volume slider per managed audio bus. Changes apply live
## through AudioManager and are persisted to disk when leaving the screen.
## All controls are built in code to keep the scene file minimal.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

# Human-readable labels for the managed buses.
const BUS_LABELS := {
	"Master": "Master",
	"Music": "Music",
	"SFX": "Effects",
	"UI": "Interface",
}


func _ready() -> void:
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
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	for bus: String in AudioManager.MANAGED_BUSES:
		_add_volume_row(vbox, bus)

	_add_fullscreen_row(vbox)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	vbox.add_child(back)


func _add_volume_row(parent: Node, bus: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	var name_text: String = BUS_LABELS.get(bus, bus)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = AudioManager.get_bus_volume(bus)
	slider.custom_minimum_size = Vector2(320, 0)
	slider.value_changed.connect(
		func(value: float) -> void:
			AudioManager.set_bus_volume(bus, value)
			label.text = "%s  %d%%" % [name_text, roundi(value * 100.0)]
	)
	row.add_child(slider)

	label.text = "%s  %d%%" % [name_text, roundi(slider.value * 100.0)]


func _add_fullscreen_row(parent: Node) -> void:
	var toggle := CheckButton.new()
	toggle.text = "Fullscreen"
	toggle.button_pressed = DisplaySettings.is_fullscreen()
	toggle.toggled.connect(
		func(on: bool) -> void:
			DisplaySettings.set_fullscreen(on)
	)
	parent.add_child(toggle)


func _on_back_pressed() -> void:
	AudioManager.save_settings()
	DisplaySettings.save_settings()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

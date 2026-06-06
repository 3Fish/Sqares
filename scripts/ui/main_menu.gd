extends Control

func _ready() -> void:
	$VBox/PlayButton.pressed.connect(_on_play_pressed)
	$VBox/SettingsButton.pressed.connect(_on_settings_pressed)
	$VBox/QuitButton.pressed.connect(_on_quit_pressed)

	# Populate any menu items injected by mods
	for item: Dictionary in UIManager.get_menu_items():
		var btn := Button.new()
		btn.text = item["label"]
		btn.pressed.connect(func(): _open_mod_scene(item["scene"]))
		$VBox.add_child(btn)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/match.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/options_menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _open_mod_scene(scene: PackedScene) -> void:
	get_tree().change_scene_to_packed(scene)

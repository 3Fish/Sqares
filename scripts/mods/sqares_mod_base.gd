extends Node
class_name SqaresModBase

## Base class for all Sqares mods (built-in and third-party).
## Override _on_load() to register cards, stats, levels, actions, and UI extensions.
## Do NOT override _ready() — it runs before other AutoLoads are guaranteed ready.

var mod_path: String = ""


func _on_load() -> void:
	pass


func register_card(data: Dictionary) -> void:
	CardRegistry.register_card(data)


func register_sound(sound_name: String, stream: AudioStream) -> void:
	AudioManager.register_sound(sound_name, stream)


func register_music(track_name: String, stream: AudioStream) -> void:
	AudioManager.register_music(track_name, stream)

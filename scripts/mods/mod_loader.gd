extends Node

## Discovers and initializes all mods in res://mods/ and user://mods/.
## Each mod must have a mod.gd extending SqaresModBase.
## Implemented fully in feature/12-mod-loader.

var _loaded_mods: Array = []


func _ready() -> void:
	# Deferred so all AutoLoad singletons finish _ready() before any mod code runs.
	call_deferred("_load_all_mods")


func _load_all_mods() -> void:
	_load_mods_from("res://mods/")
	_load_mods_from("user://mods/")
	# Mods (incl. base_game) have now registered their built-in arenas; pull in
	# any player-authored custom arenas so they appear in match setup too (#33).
	LevelRegistry.load_custom_arenas()


func _load_mods_from(base_path: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_try_load_mod(base_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _try_load_mod(mod_path: String) -> void:
	var entry_script_path := mod_path.path_join("mod.gd")
	if not FileAccess.file_exists(entry_script_path):
		push_warning("ModLoader: no mod.gd in '%s' — skipping." % mod_path)
		return
	var script: GDScript = load(entry_script_path)
	if script == null:
		push_error("ModLoader: failed to load '%s'." % entry_script_path)
		return
	var mod: Node = script.new()
	mod.name = mod_path.get_file()
	add_child(mod)
	if mod.has_method("_on_load"):
		mod._on_load()
	_loaded_mods.append(mod)
	print("ModLoader: loaded mod '%s'." % mod.name)


func get_loaded_mods() -> Array:
	return _loaded_mods.duplicate()

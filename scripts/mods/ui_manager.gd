extends Node

## Allows mods to inject UI elements: overlays, menu items, and HUD widgets.
## All standard UI is registered through mods/base_game/ using this same API.
## Implemented fully in feature/16-ui-menus.

# Array of {label, scene} dicts
var _menu_items: Array = []
# Array of PackedScene
var _overlays: Array = []
# Array of PackedScene
var _hud_elements: Array = []

signal menu_item_added(label: String, scene: PackedScene)
signal overlay_added(scene: PackedScene)
signal hud_element_added(scene: PackedScene)


func add_menu_item(label: String, scene: PackedScene) -> void:
	_menu_items.append({"label": label, "scene": scene})
	menu_item_added.emit(label, scene)


func add_overlay(scene: PackedScene) -> void:
	_overlays.append(scene)
	overlay_added.emit(scene)


func add_hud_element(scene: PackedScene) -> void:
	_hud_elements.append(scene)
	hud_element_added.emit(scene)


func get_menu_items() -> Array:
	return _menu_items.duplicate()


func get_overlays() -> Array:
	return _overlays.duplicate()


func get_hud_elements() -> Array:
	return _hud_elements.duplicate()

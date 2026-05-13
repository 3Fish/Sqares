extends Node2D
class_name Arena

## Base class for all arena scenes.
## Provides spawn-point enumeration and kill-zone death handling.

@onready var _kill_zone: Area2D = $KillZone if has_node("KillZone") else null


func _ready() -> void:
	if _kill_zone:
		_kill_zone.body_entered.connect(_on_kill_zone_body_entered)


## Returns all spawn positions in a randomised order.
func get_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for child in get_children():
		if child is Node2D and child.name.begins_with("Spawn"):
			points.append(to_global(child.position))
	points.shuffle()
	return points


func _on_kill_zone_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(INF)

extends StaticBody2D

## Throwaway test target: flashes red on hit, logs damage to console.

@onready var _visual: Polygon2D = $Visual


func take_damage(amount: float, _attacker: Node = null) -> void:
	print("DummyTarget hit for %s damage" % amount)
	_visual.color = Color(1.0, 0.2, 0.2, 1.0)
	get_tree().create_timer(0.12).timeout.connect(
		func() -> void: _visual.color = Color(0.55, 0.2, 0.7, 1.0)
	)

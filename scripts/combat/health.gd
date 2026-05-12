extends Node
class_name Health

signal damaged(amount: float, attacker: Node)
signal died(killer: Node)
signal shield_broken()

var max_hp: float = 100.0
var current_hp: float = 100.0
var shield_charges: int = 0
var _dead: bool = false


func initialize(stats: Dictionary) -> void:
	max_hp = stats.get("max_health", 100.0)
	current_hp = max_hp
	shield_charges = int(stats.get("shield_charges", 0.0))
	_dead = false


func apply_stats(stats: Dictionary) -> void:
	max_hp = stats.get("max_health", max_hp)
	shield_charges = int(stats.get("shield_charges", float(shield_charges)))


func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	if shield_charges > 0:
		shield_charges -= 1
		shield_broken.emit()
		return
	current_hp = maxf(current_hp - amount, 0.0)
	damaged.emit(amount, attacker)
	if current_hp <= 0.0:
		_dead = true
		died.emit(attacker)


func heal(amount: float) -> void:
	if _dead:
		return
	current_hp = minf(current_hp + amount, max_hp)


func reset() -> void:
	_dead = false
	current_hp = max_hp


func is_dead() -> bool:
	return _dead

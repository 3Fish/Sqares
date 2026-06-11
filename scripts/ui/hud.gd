extends CanvasLayer
class_name HUD

## In-game HUD: health readout, win pips, round number, center announcements.
## All UI nodes are built in code so there's no separate .tscn needed.

const P_COLORS: Array[Color] = [
	Color(0.4, 0.7, 1.0),
	Color(1.0, 0.5, 0.3),
	Color(0.4, 1.0, 0.5),
	Color(1.0, 0.9, 0.3),
]

var _round_label: Label
var _center_label: Label
var _hp_labels: Dictionary = {}    # player_id -> Label
var _win_labels: Dictionary = {}   # player_id -> Label
var _players: Dictionary = {}      # player_id -> Player


func _ready() -> void:
	_round_label = _label(Vector2(440, 8), Vector2(400, 28), 18)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_center_label = _label(Vector2(290, 280), Vector2(700, 160), 38)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_center_label.visible = false


func _process(_delta: float) -> void:
	for id: int in _players:
		var p: Player = _players[id]
		if not is_instance_valid(p) or not _hp_labels.has(id):
			continue
		var pct := p.health.current_hp / p.health.max_hp
		var hp_int := roundi(p.health.current_hp)
		_hp_labels[id].text = "P%d  %d HP" % [id + 1, hp_int]
		_hp_labels[id].modulate.a = lerpf(0.6, 1.0, pct)


func register_player(player_id: int, player: Player) -> void:
	_players[player_id] = player
	if _hp_labels.has(player_id):
		return
	# Even ids go top-left, odd ids top-right; each extra player on a side stacks
	# downward so 3- and 4-player readouts don't overlap P1 / P2.
	var on_left := player_id % 2 == 0
	var row := player_id / 2
	var y := 16.0 + float(row) * 56.0
	var pos := Vector2(16, y) if on_left else Vector2(1064, y)
	var align := HORIZONTAL_ALIGNMENT_LEFT if on_left else HORIZONTAL_ALIGNMENT_RIGHT
	var color: Color = P_COLORS[mini(player_id, P_COLORS.size() - 1)]

	var hp := _label(pos, Vector2(200, 24), 16)
	hp.horizontal_alignment = align
	hp.add_theme_color_override("font_color", color)
	hp.text = "P%d" % (player_id + 1)
	_hp_labels[player_id] = hp

	var wins := _label(pos + Vector2(0, 28), Vector2(200, 20), 14)
	wins.horizontal_alignment = align
	wins.add_theme_color_override("font_color", color)
	_win_labels[player_id] = wins


func set_round(round_num: int) -> void:
	_round_label.text = "Round %d" % round_num


func show_center(text: String) -> void:
	_center_label.text = text
	_center_label.visible = true


func hide_center() -> void:
	_center_label.visible = false


func update_wins() -> void:
	# Pips reflect the player's *team* win count, so teammates show the same
	# tally. In Free-for-all the team is the player, so this is per-player.
	for id: int in _win_labels:
		var count: int = GameManager.wins_for_player(id)
		_win_labels[id].text = "■".repeat(count) + "□".repeat(
			GameManager.rounds_to_win - count
		)


# ---------------------------------------------------------------------------

func _label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	add_child(lbl)
	return lbl

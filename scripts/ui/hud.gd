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
var _ammo_labels: Dictionary = {}  # player_id -> Label
var _players: Dictionary = {}      # player_id -> Player
## Elastic-border danger frame + contact flashes + out-of-bounds arrows (#101).
## Added first so it draws behind the text readouts.
var _border_overlay: BorderOverlay


func _ready() -> void:
	_border_overlay = BorderOverlay.new()
	add_child(_border_overlay)

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
		# Ammo: rounds remaining as pips, plus an idle-reload indicator (#116).
		if _ammo_labels.has(id) and is_instance_valid(p.weapon):
			_ammo_labels[id].text = ammo_readout(
				p.weapon.get_ammo(), p.weapon.magazine_size, p.weapon.get_reload_progress()
			)


func register_player(player_id: int, player: Player) -> void:
	_players[player_id] = player
	# Re-register the border overlay every round with the fresh player node so its
	# out-of-bounds arrows / contact flashes track the live square (#101).
	var p_color: Color = P_COLORS[mini(player_id, P_COLORS.size() - 1)]
	_border_overlay.register_player(player_id, player, p_color, "P%d" % (player_id + 1))
	if _hp_labels.has(player_id):
		return
	# Even ids go top-left, odd ids top-right; each extra player on a side stacks
	# downward so 3- and 4-player readouts don't overlap P1 / P2. The row pitch
	# leaves room for the HP / wins / ammo trio (#116).
	var on_left := player_id % 2 == 0
	var row := player_id / 2
	var y := 16.0 + float(row) * 78.0
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

	# Right-side readouts are right-aligned in a wider box so the ammo pips +
	# reload indicator sit flush with HP / wins.
	var ammo_pos := pos + Vector2(0, 50) if on_left else pos + Vector2(-40, 50)
	var ammo := _label(ammo_pos, Vector2(240, 20), 14)
	ammo.horizontal_alignment = align
	ammo.add_theme_color_override("font_color", color)
	_ammo_labels[player_id] = ammo


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

## Builds the per-player ammo readout (#116): one filled pip per round still in
## the magazine, an empty pip per spent round, so the magazine size and rounds
## remaining read at a glance — the same pip idiom the win tally uses. While the
## magazine is refilling (not yet full), an idle-reload indicator shows how far
## along the reload is. Pure (no scene state) so it is unit-tested directly.
static func ammo_readout(current: int, capacity: int, reload_progress: float) -> String:
	var cap := maxi(capacity, 0)
	var rounds := clampi(current, 0, cap)
	var pips := "▮".repeat(rounds) + "▯".repeat(cap - rounds)
	if current >= cap:
		return pips
	var pct := clampi(roundi(reload_progress * 100.0), 0, 100)
	return "%s  ↻ %d%%" % [pips, pct]


func _label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	add_child(lbl)
	return lbl

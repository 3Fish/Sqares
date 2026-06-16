class_name CardSelectionUI extends CanvasLayer

## Between-rounds card pick screen (#17).
##
## Shows one panel per losing player, each listing that player's drawn hand, and
## lets every loser pick in parallel using their own `p{n}_*` inputs:
## `move_left` / `move_right` to change the highlighted card and `jump` to lock
## it in. Once every panel has confirmed, `selection_complete` fires with a
## `{ player_id: Card }` map and the screen is done (the caller frees it).
##
## All nodes are built in code, mirroring `HUD` — there is no companion `.tscn`.
## The input/scene-tree behaviour is boot-verified; the pure index maths are
## unit-tested via `wrap_index`.

## Player colours, matched to the HUD readouts so a panel reads as "your" panel.
const P_COLORS: Array[Color] = [
	Color(0.4, 0.7, 1.0),
	Color(1.0, 0.5, 0.3),
	Color(0.4, 1.0, 0.5),
	Color(1.0, 0.9, 0.3),
]

const PANEL_WIDTH := 300.0
const PANEL_GAP := 24.0

## Emitted once every shown player has confirmed a pick. `picks` maps
## player_id -> chosen Card (a player whose hand was empty maps to null).
signal selection_complete(picks: Dictionary)

# player_id -> { "hand": Array[Card], "index": int, "confirmed": bool,
#               "cards_box": VBoxContainer, "status": Label }
var _panels: Dictionary = {}
var _done: bool = false


## Builds the screen from `hands` ({ player_id: Array[Card] }) and starts
## listening for input. With no players (or all hands empty) it completes on the
## next frame so the round flow never stalls waiting on a pick that can't be made.
func begin(hands: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var title := _label(Vector2(0, 40), Vector2(1280, 40), 30)
	title.text = "Pick a card"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var ids: Array = hands.keys()
	ids.sort()
	var total_width := ids.size() * PANEL_WIDTH + maxf(0, ids.size() - 1) * PANEL_GAP
	var start_x := (1280.0 - total_width) * 0.5
	for i in ids.size():
		var pid: int = ids[i]
		var hand: Array = hands[pid]
		var x := start_x + i * (PANEL_WIDTH + PANEL_GAP)
		_build_panel(pid, hand, x)

	# Auto-confirm any player who has nothing to pick, then settle empties.
	for pid in _panels:
		if (_panels[pid]["hand"] as Array).is_empty():
			_panels[pid]["confirmed"] = true
	_refresh_all()
	# Play the card-draw UI cue once the hands are on screen, but only when there
	# is actually something to pick — an empty round completes silently (#58).
	if has_drawable_cards(hands):
		SfxDirector.play_ui(SfxDirector.CARD_DRAW)
	_maybe_complete.call_deferred()


func _process(_delta: float) -> void:
	if _done:
		return
	for pid: int in _panels:
		var panel: Dictionary = _panels[pid]
		if panel["confirmed"]:
			continue
		var hand: Array = panel["hand"]
		var n := (pid + 1)
		if Input.is_action_just_pressed("p%d_move_left" % n):
			panel["index"] = wrap_index(panel["index"], -1, hand.size())
			_refresh_panel(pid)
		elif Input.is_action_just_pressed("p%d_move_right" % n):
			panel["index"] = wrap_index(panel["index"], 1, hand.size())
			_refresh_panel(pid)
		elif Input.is_action_just_pressed("p%d_jump" % n):
			_confirm(pid)


## Locks in the highlighted card for one player: marks the panel confirmed, plays
## the card-pick UI cue (#58), repaints the panel, and settles the screen if every
## panel is now done. Empty hands are auto-confirmed in `begin()` and never route
## here, so a pick cue always corresponds to a real card choice.
func _confirm(player_id: int) -> void:
	_panels[player_id]["confirmed"] = true
	SfxDirector.play_ui(SfxDirector.CARD_PICK)
	_refresh_panel(player_id)
	_maybe_complete()


func _maybe_complete() -> void:
	if _done:
		return
	for pid: int in _panels:
		if not _panels[pid]["confirmed"]:
			return
	_done = true
	var picks: Dictionary = {}
	for pid: int in _panels:
		var hand: Array = _panels[pid]["hand"]
		picks[pid] = hand[_panels[pid]["index"]] if not hand.is_empty() else null
	selection_complete.emit(picks)


# ---------------------------------------------------------------------------
# Construction / rendering
# ---------------------------------------------------------------------------

func _build_panel(player_id: int, hand: Array, x: float) -> void:
	var color: Color = P_COLORS[mini(player_id, P_COLORS.size() - 1)]

	var header := _label(Vector2(x, 110), Vector2(PANEL_WIDTH, 28), 20)
	header.text = "Player %d" % (player_id + 1)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", color)
	add_child(header)

	var cards_box := VBoxContainer.new()
	cards_box.position = Vector2(x, 150)
	cards_box.size = Vector2(PANEL_WIDTH, 360)
	cards_box.add_theme_constant_override("separation", 12)
	add_child(cards_box)

	var status := _label(Vector2(x, 520), Vector2(PANEL_WIDTH, 24), 16)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)

	_panels[player_id] = {
		"hand": hand,
		"index": 0,
		"confirmed": false,
		"cards_box": cards_box,
		"status": status,
	}
	_render_cards(player_id)


func _render_cards(player_id: int) -> void:
	var panel: Dictionary = _panels[player_id]
	var box: VBoxContainer = panel["cards_box"]
	for child in box.get_children():
		child.queue_free()
	var hand: Array = panel["hand"]
	if hand.is_empty():
		var none := Label.new()
		none.text = "(no cards available)"
		box.add_child(none)
		return
	for i in hand.size():
		var card = hand[i]
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD
		entry.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
		entry.add_theme_font_size_override("font_size", 15)
		entry.text = _card_text(card)
		box.add_child(entry)


func _card_text(card) -> String:
	var name_str := String(card.display_name) if card.display_name != "" else String(card.id)
	var rarity_str := Card.rarity_to_string(card.rarity).capitalize()
	return "%s  [%s]\n%s" % [name_str, rarity_str, String(card.description)]


func _refresh_all() -> void:
	for pid: int in _panels:
		_refresh_panel(pid)


## Re-applies the highlight + status for one panel without rebuilding it.
func _refresh_panel(player_id: int) -> void:
	var panel: Dictionary = _panels[player_id]
	var box: VBoxContainer = panel["cards_box"]
	var selected: int = panel["index"]
	var confirmed: bool = panel["confirmed"]
	for i in box.get_child_count():
		var child := box.get_child(i)
		if child is Label:
			# Dim unselected entries; full-bright the highlighted one.
			child.modulate.a = 1.0 if i == selected else 0.45
	panel["status"].text = "READY" if confirmed else "← →  •  Jump = pick"


func _label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl


# ---------------------------------------------------------------------------
# Pure helper (unit-tested)
# ---------------------------------------------------------------------------

## Steps a selection index by `delta`, wrapping within `[0, size)`. Returns 0
## for an empty/degenerate list so callers never index out of range.
static func wrap_index(current: int, delta: int, size: int) -> int:
	if size <= 0:
		return 0
	return posmod(current + delta, size)


## True when at least one player was dealt a non-empty hand, i.e. there is a card
## to actually pick. Gates the card-draw UI cue (#58) so a round with no losers or
## no registered cards — which completes immediately — stays silent.
static func has_drawable_cards(hands: Dictionary) -> bool:
	for pid in hands:
		if hands[pid] is Array and not (hands[pid] as Array).is_empty():
			return true
	return false

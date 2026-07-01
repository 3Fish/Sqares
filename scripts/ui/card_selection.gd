class_name CardSelectionUI extends CanvasLayer

## Between-rounds card pick screen (#17, #169).
##
## Shows one panel per losing player, each listing that player's drawn hand, and
## lets losers pick with their own `p{n}_*` inputs: `move_left` / `move_right` to
## change the highlighted card and `jump` to lock it in. Once every panel has
## confirmed, `selection_complete` fires with a `{ player_id: Card }` map and the
## screen is done (the caller frees it).
##
## The phase runs in one of two presentation modes (#169), chosen by the caller
## via `begin`'s `options`:
##   * PARALLEL ("All At Once") — every loser picks simultaneously (the original
##     flow). This is the default when no mode is given.
##   * SEQUENTIAL ("One By One") — losers pick in turn following `options.order`;
##     only the active picker's panel accepts input while the others watch (dimmed
##     with a "Waiting" status).
## Either mode shows a per-player "picked / still choosing" status indicator, and
## an optional pick `timeout` auto-picks a random card (from `options.rng`) for a
## player who runs out of time — after which the phase settles as usual.
##
## All nodes are built in code, mirroring `HUD` — there is no companion `.tscn`.
## The input/scene-tree behaviour is boot-verified; the pure decision maths
## (mode/order/timeout/auto-pick) lives in `CardPickMode` and is unit-tested, as
## is `wrap_index`.

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
## player_id -> input index whose `p{n+1}_*` actions drive that panel. Defaults
## to the player_id itself (local couch play). Online, a remote loser drives its
## own panel through this machine's primary `p1` bindings (override -> 0),
## mirroring `Player.input_id` for the local slot (#82).
var _input_overrides: Dictionary = {}

## Presentation mode for this phase (#169): `CardPickMode.PARALLEL` (default) or
## `CardPickMode.SEQUENTIAL`.
var _mode: String = CardPickMode.PARALLEL
## SEQUENTIAL pick order — the slots to hand off to, in turn (a permutation of the
## panel slots). Unused in PARALLEL mode.
var _order: Array = []
## The slot whose panel currently accepts input in SEQUENTIAL mode, or -1 when no
## one is active (PARALLEL mode, or every picker has confirmed).
var _active: int = -1
## Pick timeout in seconds; `0.0` disables it (wait indefinitely). In PARALLEL the
## clock runs once for the whole phase; in SEQUENTIAL it resets for each picker.
var _timeout: float = 0.0
## Seeded RNG for a timeout auto-pick (#169 Q3). Null falls back to the currently
## highlighted card.
var _rng: RandomNumberGenerator = null
## Seconds elapsed against the active timeout window.
var _elapsed: float = 0.0
## The "Pick a card" heading, kept so the timeout countdown can be shown on it.
var _title: Label = null


## Builds the screen from `hands` ({ player_id: Array[Card] }) and starts
## listening for input. `input_overrides` ({ player_id -> input index }) remaps
## which `p{n}_*` bindings drive a panel; an unlisted panel uses its own slot.
## `options` tunes the presentation (#169): `mode` (CardPickMode.SEQUENTIAL /
## PARALLEL, default PARALLEL), `order` (Array of slots for sequential hand-off),
## `timeout` (float seconds, 0 = none), and `rng` (RandomNumberGenerator for the
## auto-pick). With no players (or all hands empty) it completes on the next frame
## so the round flow never stalls waiting on a pick that can't be made.
func begin(hands: Dictionary, input_overrides: Dictionary = {}, options: Dictionary = {}) -> void:
	_input_overrides = input_overrides
	_mode = CardPickMode.normalize_setting(String(options.get("mode", CardPickMode.PARALLEL)))
	if _mode == CardPickMode.AUTO:
		# `begin` needs a concrete mode; a caller that forwards AUTO by mistake gets
		# the original simultaneous flow rather than an inert screen.
		_mode = CardPickMode.PARALLEL
	_timeout = maxf(0.0, float(options.get("timeout", 0.0)))
	_rng = options.get("rng", null)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_title = _label(Vector2(0, 40), Vector2(1280, 40), 30)
	_title.text = "Pick a card"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

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

	# Resolve the sequential order (defaulting to sorted slots) and pick the first
	# active player; PARALLEL leaves `_active` at -1 so every panel takes input.
	if _mode == CardPickMode.SEQUENTIAL:
		_order = _resolve_order(options.get("order", []))
		_advance_active()

	_refresh_all()
	# Play the card-draw UI cue once the hands are on screen, but only when there
	# is actually something to pick — an empty round completes silently (#58).
	if has_drawable_cards(hands):
		SfxDirector.play_ui(SfxDirector.CARD_DRAW)
	_maybe_complete.call_deferred()


func _process(delta: float) -> void:
	if _done:
		return
	if _mode == CardPickMode.SEQUENTIAL:
		_process_sequential(delta)
	else:
		_process_parallel(delta)
	_update_title()


## PARALLEL flow: every unconfirmed panel takes its own input, and a single phase
## timeout auto-picks everyone still choosing when it elapses.
func _process_parallel(delta: float) -> void:
	for pid: int in _panels:
		if not _panels[pid]["confirmed"]:
			_handle_input(pid)
	if _done or _timeout <= 0.0:
		return
	_elapsed += delta
	if not CardPickMode.timed_out(_elapsed, _timeout):
		return
	for pid: int in _panels.keys():
		if not _panels[pid]["confirmed"]:
			_auto_pick(pid)


## SEQUENTIAL flow: only the active picker takes input, and the timeout (reset for
## each picker in `_advance_active`) auto-picks the active player when it elapses.
func _process_sequential(delta: float) -> void:
	if _active < 0:
		return
	_handle_input(_active)
	if _done or _active < 0 or _timeout <= 0.0:
		return
	_elapsed += delta
	if CardPickMode.timed_out(_elapsed, _timeout):
		_auto_pick(_active)


## Reads one panel's `p{n}_*` inputs: step the highlight left/right or lock in.
func _handle_input(player_id: int) -> void:
	var panel: Dictionary = _panels[player_id]
	var hand: Array = panel["hand"]
	var n: int = int(_input_overrides.get(player_id, player_id)) + 1
	if Input.is_action_just_pressed("p%d_move_left" % n):
		panel["index"] = wrap_index(panel["index"], -1, hand.size())
		_refresh_panel(player_id)
	elif Input.is_action_just_pressed("p%d_move_right" % n):
		panel["index"] = wrap_index(panel["index"], 1, hand.size())
		_refresh_panel(player_id)
	elif Input.is_action_just_pressed("p%d_jump" % n):
		_confirm(player_id)


## Locks in the highlighted card for one player: marks the panel confirmed, plays
## the card-pick UI cue (#58), repaints, hands off to the next picker in SEQUENTIAL
## mode, and settles the screen if every panel is now done. Empty hands are
## auto-confirmed in `begin()` and never route here, so a pick cue always
## corresponds to a real card choice.
func _confirm(player_id: int) -> void:
	if _panels[player_id]["confirmed"]:
		return
	_panels[player_id]["confirmed"] = true
	SfxDirector.play_ui(SfxDirector.CARD_PICK)
	if _mode == CardPickMode.SEQUENTIAL:
		_advance_active()
		_refresh_all()  # the active/waiting statuses shift to the next picker
	else:
		_refresh_panel(player_id)
	_maybe_complete()


## Resolves a timeout for one player by choosing a random card from their hand
## (maintainer #169 Q3) and confirming it. A null `_rng` falls back to the current
## highlight so the phase still advances.
func _auto_pick(player_id: int) -> void:
	var panel: Dictionary = _panels[player_id]
	if panel["confirmed"]:
		return
	var hand: Array = panel["hand"]
	var idx := CardPickMode.auto_pick_index(hand.size(), _rng) if _rng != null else 0
	if idx >= 0:
		panel["index"] = idx
	_refresh_panel(player_id)
	_confirm(player_id)


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
# Sequential hand-off
# ---------------------------------------------------------------------------

## Builds the sequential pick order from `raw` (the caller's order), keeping only
## real panel slots and appending any panel slot the order omitted (sorted) so the
## order always covers every panel. Falls back to sorted slots for an empty order.
func _resolve_order(raw: Array) -> Array:
	var out: Array = []
	for slot in raw:
		var s := int(slot)
		if _panels.has(s) and not out.has(s):
			out.append(s)
	var keys: Array = _panels.keys()
	keys.sort()
	for slot: int in keys:
		if not out.has(slot):
			out.append(slot)
	return out


## Advances the active picker to the next unconfirmed slot in `_order` (or -1 when
## all have confirmed) and restarts the timeout clock for the new picker.
func _advance_active() -> void:
	_active = CardPickMode.next_active(_order, _confirmed_set())
	_elapsed = 0.0


## The set of already-confirmed slots (Dictionary used as a set).
func _confirmed_set() -> Dictionary:
	var s: Dictionary = {}
	for pid: int in _panels:
		if _panels[pid]["confirmed"]:
			s[pid] = true
	return s


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


## Re-applies the highlight + status for one panel without rebuilding it. In
## SEQUENTIAL mode a player who is neither confirmed nor the active picker is
## "watching": its whole hand is dimmed so the focus stays on the active picker.
func _refresh_panel(player_id: int) -> void:
	var panel: Dictionary = _panels[player_id]
	var box: VBoxContainer = panel["cards_box"]
	var selected: int = panel["index"]
	var confirmed: bool = panel["confirmed"]
	var watching := _mode == CardPickMode.SEQUENTIAL and not confirmed and player_id != _active
	for i in box.get_child_count():
		var child := box.get_child(i)
		if child is Label:
			# Dim unselected entries; full-bright the highlighted one — but a
			# watching player's whole hand is dimmed further (they aren't up yet).
			var a := 1.0 if i == selected else 0.45
			child.modulate.a = 0.2 if watching else a
	panel["status"].text = _status_text(player_id, confirmed, watching)


## The per-player "picked / still choosing" indicator text (#169): a confirmed
## player reads "Picked", a watching (not-yet-their-turn) player reads "Waiting",
## and whoever can act reads the controls hint.
func _status_text(_player_id: int, confirmed: bool, watching: bool) -> String:
	if confirmed:
		return "✓ Picked"
	if watching:
		return "Waiting…"
	return "Choosing…   ← →  •  Jump = pick"


## Shows the remaining timeout on the heading while the phase is running, so
## players can see how long they have; reverts to the plain title otherwise.
func _update_title() -> void:
	if _title == null:
		return
	if _timeout > 0.0 and not _done:
		var remaining := maxf(0.0, _timeout - _elapsed)
		_title.text = "Pick a card   (%d)" % ceili(remaining)
	else:
		_title.text = "Pick a card"


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

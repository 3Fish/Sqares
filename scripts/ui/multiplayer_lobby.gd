extends Control

## Multiplayer demo lobby (#149): host or join a game over direct ENet IP:port,
## see the connected roster, and — host only — pick the match settings and start.
## Clients adopt the host's settings and follow it into `scenes/match.tscn`.
##
## Scope is the maintainer's MVP decision on #149: **direct IP:port only** (no
## relay / Steam invites — those are separate follow-ups), a **host-only setup**
## (clients just see the roster and wait), **automatic team assignment** (the
## mode's built-in `assign_teams`, since per-player colour identity isn't
## replicated yet — #66/#82), and **best-effort disconnect handling** (no
## reconnect/migration here; that's #151/#152).
##
## The actual networked match is already supported end-to-end by `match.tscn`
## (`MatchDirector._client_setup` mirrors the host's reliable round-flow events,
## #27); this screen only provides the front-end flow to get peers into it. The
## host's Start broadcasts the chosen config via `NetReplicator.broadcast_start_match`
## and every peer loads the match scene; a scene-ready handshake holds round 1
## until clients are listening.
##
## Controls are built in code (like `options_menu.gd` / `match_setup.gd`) to keep
## the scene file minimal; the parse / gate / roster-format logic is pure static
## helpers covered by tests.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"

## Fallbacks when the registries are empty (e.g. before mods have loaded). The
## base game registers exactly these.
const FALLBACK_MODES := ["ffa", "teams"]
const FALLBACK_ARENAS := ["crossroads"]
const DEFAULT_ADDRESS := "127.0.0.1"

var _connect_panel: VBoxContainer
var _lobby_panel: VBoxContainer
var _address_edit: LineEdit
var _port_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _status_label: Label
var _roster_label: Label
var _start_button: Button
var _host_settings: VBoxContainer
var _waiting_label: Label
var _mode_picker: OptionButton
var _arena_picker: OptionButton
var _rounds_picker: SpinBox

# Parallel arrays: picker item index -> registered id.
var _mode_ids: Array = []
var _arena_ids: Array = []


func _ready() -> void:
	_mode_ids = _ids_or_fallback(GameModeRegistry.get_all_ids(), FALLBACK_MODES)
	_arena_ids = _ids_or_fallback(LevelRegistry.get_all_ids(), FALLBACK_ARENAS)
	_build_ui()
	_show_connect()

	# Connection lifecycle: host_game emits server_started synchronously, so the
	# host enters the lobby inline below; a client waits for these signals.
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobby_changed.connect(_refresh_roster)
	# A client follows the host's Start into the match scene (#149).
	NetReplicator.match_starting.connect(_on_match_starting)
	# Best-effort: if the host vanishes while we're in the lobby, drop back to the
	# connect screen rather than hanging (#149 Q5).
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Connection actions
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	var port := parse_port(_port_edit.text)
	var err := NetworkManager.host_game(port)
	if err != OK:
		_status_label.text = "Could not host on port %d (error %d)." % [port, err]
		return
	_show_lobby()
	_refresh_roster()


func _on_join_pressed() -> void:
	var address := parse_address(_address_edit.text)
	var port := parse_port(_port_edit.text)
	_set_connect_enabled(false)
	_status_label.text = "Connecting to %s:%d…" % [address, port]
	var err := NetworkManager.join_game(address, port)
	if err != OK:
		_status_label.text = "Could not start connection (error %d)." % err
		_set_connect_enabled(true)


func _on_client_connected() -> void:
	# The client is on the host; the roster mirror arrives over RPC shortly.
	_show_lobby()
	_refresh_roster()


func _on_connection_failed() -> void:
	_status_label.text = "Connection failed — check the address and that a host is running."
	_set_connect_enabled(true)
	_show_connect()


func _on_server_disconnected() -> void:
	NetworkManager.disconnect_game()
	_status_label.text = "Disconnected from host."
	_set_connect_enabled(true)
	_show_connect()


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	_status_label.text = ""
	_set_connect_enabled(true)
	_show_connect()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# ---------------------------------------------------------------------------
# Match start (#149)
# ---------------------------------------------------------------------------

## Host only: broadcast the chosen config, adopt it locally, and load the match.
func _on_start_pressed() -> void:
	if not (NetworkManager.is_host() and can_start(NetworkManager.peer_count())):
		return
	var mode := _current_mode_id()
	var wins := int(_rounds_picker.value)
	var arena := _current_arena_id()
	var config := MatchConfig.to_dict(mode, wins, arena, true, false)
	NetReplicator.broadcast_start_match(config)
	# The host's own roster size is the player count; identity stays default
	# (colour-by-slot) for the demo, so no names/colours are staged (#149 Q4).
	MatchConfig.configure(mode, NetworkManager.peer_count(), wins, arena, true, [], [], false)
	get_tree().change_scene_to_file(MATCH_SCENE)


## Client: adopt the host's config and load the match scene (#149).
func _on_match_starting(config: Dictionary) -> void:
	var norm := MatchConfig.normalize_dict(config, _mode_ids, _arena_ids)
	MatchConfig.configure(
		String(norm["game_mode"]), NetworkManager.peer_count(), int(norm["wins_needed"]),
		String(norm["arena_id"]), bool(norm["friendly_fire"]), [], [], bool(norm["team_handicap"]))
	get_tree().change_scene_to_file(MATCH_SCENE)


# ---------------------------------------------------------------------------
# Roster + view state
# ---------------------------------------------------------------------------

func _refresh_roster() -> void:
	if _roster_label == null:
		return
	_roster_label.text = roster_text(NetworkManager.peers, NetworkManager.local_slot())
	if _start_button != null:
		_start_button.disabled = not can_start(NetworkManager.peer_count())


## Toggles between the connect screen and the lobby screen, and shows host-only
## controls only to the host.
func _show_connect() -> void:
	_connect_panel.visible = true
	_lobby_panel.visible = false


func _show_lobby() -> void:
	_connect_panel.visible = false
	_lobby_panel.visible = true
	var host := NetworkManager.is_host()
	_host_settings.visible = host
	_start_button.visible = host
	_waiting_label.visible = not host


func _set_connect_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled


func _current_mode_id() -> String:
	return String(_mode_ids[_mode_picker.selected]) \
		if _mode_picker != null and _mode_picker.selected >= 0 else MatchConfig.DEFAULT_MODE


func _current_arena_id() -> String:
	return String(_arena_ids[_arena_picker.selected]) \
		if _arena_picker != null and _arena_picker.selected >= 0 else MatchConfig.DEFAULT_ARENA


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.102, 0.102, 0.18, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_theme_constant_override("separation", 14)
	root.custom_minimum_size = Vector2(380, 0)
	add_child(root)

	var title := Label.new()
	title.text = "Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	root.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(360, 0)
	_status_label.add_theme_font_size_override("font_size", 13)
	root.add_child(_status_label)

	_connect_panel = _build_connect_panel()
	root.add_child(_connect_panel)

	_lobby_panel = _build_lobby_panel()
	root.add_child(_lobby_panel)


func _build_connect_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)

	_address_edit = LineEdit.new()
	_address_edit.text = DEFAULT_ADDRESS
	_address_edit.placeholder_text = "Host address (for Join)"
	panel.add_child(_label_row(panel, "Address"))
	panel.add_child(_address_edit)

	_port_edit = LineEdit.new()
	_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_port_edit.placeholder_text = "Port"
	panel.add_child(_label_row(panel, "Port"))
	panel.add_child(_port_edit)

	_host_button = Button.new()
	_host_button.text = "Host Game"
	_host_button.pressed.connect(_on_host_pressed)
	panel.add_child(_host_button)

	_join_button = Button.new()
	_join_button.text = "Join Game"
	_join_button.pressed.connect(_on_join_pressed)
	panel.add_child(_join_button)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	panel.add_child(back)
	return panel


func _build_lobby_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)

	var roster_heading := Label.new()
	roster_heading.text = "Players"
	panel.add_child(roster_heading)

	_roster_label = Label.new()
	_roster_label.custom_minimum_size = Vector2(360, 80)
	panel.add_child(_roster_label)

	# Host-only match settings (#149 Q3): mode / arena / rounds.
	_host_settings = VBoxContainer.new()
	_host_settings.add_theme_constant_override("separation", 8)
	_mode_picker = _add_option_row(_host_settings, "Game Mode", _mode_labels())
	_arena_picker = _add_option_row(_host_settings, "Arena", _arena_labels())
	_rounds_picker = _add_spin_row(_host_settings, "Rounds to win",
		MatchConfig.MIN_WINS, MatchConfig.MAX_WINS, MatchConfig.DEFAULT_WINS)
	_mode_picker.select(maxi(0, _mode_ids.find(MatchConfig.DEFAULT_MODE)))
	_arena_picker.select(maxi(0, _arena_ids.find(MatchConfig.DEFAULT_ARENA)))
	panel.add_child(_host_settings)

	_waiting_label = Label.new()
	_waiting_label.text = "Waiting for the host to start the match…"
	_waiting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_waiting_label.custom_minimum_size = Vector2(360, 0)
	panel.add_child(_waiting_label)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	panel.add_child(_start_button)

	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_on_leave_pressed)
	panel.add_child(leave)
	return panel


func _label_row(_parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _add_option_row(parent: Node, label_text: String, options: Array) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var picker := OptionButton.new()
	for opt: String in options:
		picker.add_item(opt)
	picker.custom_minimum_size = Vector2(340, 0)
	parent.add_child(picker)
	return picker


func _add_spin_row(parent: Node, label_text: String, min_v: int, max_v: int, default_v: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.value = default_v
	spin.custom_minimum_size = Vector2(340, 0)
	parent.add_child(spin)
	return spin


func _mode_labels() -> Array:
	var labels: Array = []
	for id: String in _mode_ids:
		var script: GDScript = GameModeRegistry.get_mode(id)
		var label := String(id).capitalize()
		if script:
			var mode: Object = script.new()
			if mode is GameMode:
				label = (mode as GameMode).display_name
		labels.append(label)
	return labels


func _arena_labels() -> Array:
	var labels: Array = []
	for id: String in _arena_ids:
		labels.append(String(id).capitalize())
	return labels


# ---------------------------------------------------------------------------
# Pure helpers (no scene-tree dependencies — covered by tests/)
# ---------------------------------------------------------------------------

## Parses a port from a text field, falling back to the default ENet port for
## blank / non-numeric / out-of-range (1..65535) input.
static func parse_port(text: String) -> int:
	var trimmed := text.strip_edges()
	if not trimmed.is_valid_int():
		return NetworkManager.DEFAULT_PORT
	var port := trimmed.to_int()
	if port < 1 or port > 65535:
		return NetworkManager.DEFAULT_PORT
	return port


## Parses a host address from a text field, falling back to localhost when blank.
static func parse_address(text: String) -> String:
	var trimmed := text.strip_edges()
	return trimmed if not trimmed.is_empty() else DEFAULT_ADDRESS


## Whether the host may start the match: at least the minimum number of players
## (the host plus one peer) are in the lobby.
static func can_start(peer_count: int) -> bool:
	return peer_count >= MatchDirector.MIN_PLAYERS


## Roster rows for display, one per peer, sorted by slot. Each entry is
## { slot, connected, you, host }. `local_slot` flags this machine's row; slot 0
## is always the host. Pure so the formatting is unit-tested without a session.
static func roster_entries(peers: Dictionary, local_slot: int) -> Array:
	var entries: Array = []
	for info in peers.values():
		var slot := int(info.get("slot", -1))
		entries.append({
			"slot": slot,
			"connected": bool(info.get("connected", true)),
			"you": slot == local_slot,
			"host": slot == 0,
		})
	entries.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return entries


## A single roster line, e.g. "P1 (Host, You)" or "P2 (disconnected)".
static func roster_line(entry: Dictionary) -> String:
	var label := "P%d" % (int(entry["slot"]) + 1)
	var tags: Array = []
	if bool(entry.get("host", false)):
		tags.append("Host")
	if bool(entry.get("you", false)):
		tags.append("You")
	if not bool(entry.get("connected", true)):
		tags.append("disconnected")
	if not tags.is_empty():
		label += " (%s)" % ", ".join(tags)
	return label


## The full roster as newline-separated lines, or a placeholder when empty.
static func roster_text(peers: Dictionary, local_slot: int) -> String:
	var lines: Array = []
	for entry in roster_entries(peers, local_slot):
		lines.append(roster_line(entry))
	return "\n".join(lines) if not lines.is_empty() else "(no players yet)"


## Returns a copy of `ids`, or a copy of `fallback` when `ids` is empty.
static func _ids_or_fallback(ids: Array, fallback: Array) -> Array:
	return ids.duplicate() if not ids.is_empty() else fallback.duplicate()

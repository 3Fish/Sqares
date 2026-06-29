extends TestCase

## Unit tests for the Multiplayer demo lobby (#149): the pure parse / start-gate /
## roster-format helpers on the lobby screen, plus the host-side scene-ready start
## gate on MatchDirector. The live connection lifecycle (host_game / join_game,
## the match-start handshake RPCs) is boot/integration verified, since the
## headless runner can't stand up a two-process ENet session — matching the
## convention used by the netcode tests.

const Lobby := preload("res://scripts/ui/multiplayer_lobby.gd")
const MatchDirectorScript := preload("res://scripts/match/match_director.gd")


# ---------------------------------------------------------------------------
# parse_port
# ---------------------------------------------------------------------------

func _test_parse_port_accepts_valid() -> void:
	assert_eq(Lobby.parse_port("7777"), 7777, "a valid port is kept")
	assert_eq(Lobby.parse_port("  1234 "), 1234, "surrounding whitespace is trimmed")
	assert_eq(Lobby.parse_port("1"), 1, "lower bound 1 is valid")
	assert_eq(Lobby.parse_port("65535"), 65535, "upper bound 65535 is valid")


func _test_parse_port_falls_back_on_bad_input() -> void:
	var d := NetworkManager.DEFAULT_PORT
	assert_eq(Lobby.parse_port(""), d, "blank -> default port")
	assert_eq(Lobby.parse_port("abc"), d, "non-numeric -> default port")
	assert_eq(Lobby.parse_port("0"), d, "0 is out of range -> default port")
	assert_eq(Lobby.parse_port("70000"), d, "above 65535 -> default port")
	assert_eq(Lobby.parse_port("-5"), d, "negative -> default port")


# ---------------------------------------------------------------------------
# parse_address
# ---------------------------------------------------------------------------

func _test_parse_address_keeps_value_and_trims() -> void:
	assert_eq(Lobby.parse_address("192.168.1.10"), "192.168.1.10", "a value is kept")
	assert_eq(Lobby.parse_address("  10.0.0.2  "), "10.0.0.2", "whitespace is trimmed")


func _test_parse_address_defaults_to_localhost_when_blank() -> void:
	assert_eq(Lobby.parse_address(""), "127.0.0.1", "blank -> localhost")
	assert_eq(Lobby.parse_address("   "), "127.0.0.1", "whitespace-only -> localhost")


# ---------------------------------------------------------------------------
# can_start
# ---------------------------------------------------------------------------

func _test_can_start_requires_minimum_players() -> void:
	assert_false(Lobby.can_start(0), "no peers -> can't start")
	assert_false(Lobby.can_start(1), "host alone -> can't start")
	assert_true(Lobby.can_start(2), "host + 1 -> can start")
	assert_true(Lobby.can_start(4), "full lobby -> can start")


# ---------------------------------------------------------------------------
# roster formatting
# ---------------------------------------------------------------------------

func _make_peers() -> Dictionary:
	# Host (peer 1 -> slot 0) plus two clients on slots 1 and 2; client on slot 1
	# is mid-reconnect (held / disconnected).
	return {
		1: {"slot": 0, "token": "a", "connected": true, "hold_deadline_ms": 0},
		7: {"slot": 1, "token": "b", "connected": false, "hold_deadline_ms": 123},
		9: {"slot": 2, "token": "c", "connected": true, "hold_deadline_ms": 0},
	}


func _test_roster_entries_sorted_by_slot_with_flags() -> void:
	var entries := Lobby.roster_entries(_make_peers(), 2)
	assert_eq(entries.size(), 3, "one entry per peer")
	# Sorted by slot regardless of dictionary order.
	assert_eq(int(entries[0]["slot"]), 0, "slot 0 first")
	assert_eq(int(entries[1]["slot"]), 1, "slot 1 second")
	assert_eq(int(entries[2]["slot"]), 2, "slot 2 third")
	# Host is slot 0.
	assert_true(bool(entries[0]["host"]), "slot 0 is the host")
	assert_false(bool(entries[1]["host"]), "slot 1 is not the host")
	# local_slot 2 -> the slot-2 entry is "you".
	assert_true(bool(entries[2]["you"]), "local slot is flagged as you")
	assert_false(bool(entries[0]["you"]), "a non-local slot is not you")
	# Held slot reports disconnected.
	assert_false(bool(entries[1]["connected"]), "held slot reads disconnected")
	assert_true(bool(entries[2]["connected"]), "a live slot reads connected")


func _test_roster_line_tags() -> void:
	assert_eq(Lobby.roster_line({"slot": 0, "host": true, "you": true, "connected": true}),
		"P1 (Host, You)", "host + you tags, 1-based label")
	assert_eq(Lobby.roster_line({"slot": 1, "host": false, "you": false, "connected": true}),
		"P2", "a plain peer has no tags")
	assert_eq(Lobby.roster_line({"slot": 2, "host": false, "you": false, "connected": false}),
		"P3 (disconnected)", "a dropped peer is flagged disconnected")


func _test_roster_text_joins_lines_and_handles_empty() -> void:
	var text := Lobby.roster_text(_make_peers(), 0)
	# local_slot 0 -> the host line is "you" as well.
	assert_eq(text, "P1 (Host, You)\nP2 (disconnected)\nP3", "rows joined by newline, sorted")
	assert_eq(Lobby.roster_text({}, -1), "(no players yet)", "empty roster -> placeholder")


# ---------------------------------------------------------------------------
# MatchDirector start gate (#149): all clients in the match scene
# ---------------------------------------------------------------------------

func _test_all_peers_ready_ignores_host() -> void:
	# Roster = host (1) + two clients (7, 9). The host never needs to ack.
	var roster := [1, 7, 9]
	assert_false(MatchDirectorScript.all_peers_ready([], roster, 1),
		"no client acks yet -> not ready")
	assert_false(MatchDirectorScript.all_peers_ready([7], roster, 1),
		"only one of two clients ready -> not ready")
	assert_true(MatchDirectorScript.all_peers_ready([7, 9], roster, 1),
		"both clients ready -> ready (host excluded)")


func _test_all_peers_ready_host_only_is_immediately_ready() -> void:
	# A host with no clients (peer_count 1) has nothing to wait for.
	assert_true(MatchDirectorScript.all_peers_ready([], [1], 1),
		"host-only roster is ready with no acks")


func _test_all_peers_ready_extra_acks_are_harmless() -> void:
	# An ack from a peer no longer in the roster doesn't block the start.
	assert_true(MatchDirectorScript.all_peers_ready([7, 9, 99], [1, 7, 9], 1),
		"a stale extra ack still satisfies the gate")

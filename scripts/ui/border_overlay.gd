class_name BorderOverlay
extends Node2D

## Decorative visual for the damaging elastic map border (#84, deferred via #101).
##
## #84 ships the elastic border as logic-only: it damages and repels a player that
## touches or crosses the play-area edge, but draws nothing. Per the maintainer's
## [#101 answer](https://github.com/3Fish/Sqares/issues/101#issuecomment-4762634950)
## this renders the boundary as a **semi-transparent red "danger" frame** at the
## ±[constant MapBorder.HALF_EXTENT] edge, with a **short contact flash** at the
## point of first contact (the visual analogue of the one-shot bounce impulse and
## the `BORDER_CONTACT` cue already fired in [method Player._update_border]), plus
## a **per-player out-of-bounds indicator** — a small arrow in the player's colour
## with their name, clamped to the screen edge and pointing toward the off-screen
## player.
##
## The overlay lives under the HUD `CanvasLayer`, so it draws in screen space. Every
## arena centres its `Camera2D` at the origin over the `2 * HALF_EXTENT` viewport
## (the border invariant documented on [MapBorder]), so the border coincides with
## the screen edge and a world point maps to screen space by a fixed offset
## ([method world_to_overlay]). Editor-built arenas that author no camera are the
## arena-editor-epic concern (#15), out of scope here.
##
## All geometry lives in pure static helpers (no scene-tree dependency) so it is
## covered by the headless suite per `CLAUDE.md`; the node only tracks the small
## per-player out-of-bounds state and the live flash list and renders them.

## Persistent danger frame: semi-transparent red, per the maintainer's answer. The
## border is draw-only (never gameplay), so colour/width are visual tuning
## constants per `CLAUDE.md`.
const FRAME_COLOR := Color(1.0, 0.15, 0.15, 0.30)
const FRAME_WIDTH := 6.0

## Contact flash: a brief filled spark at the contact point that fades over
## [constant FLASH_DURATION] seconds. Visual tuning.
const FLASH_COLOR := Color(1.0, 0.35, 0.2)
const FLASH_DURATION := 0.28
const FLASH_RADIUS := 26.0

## Out-of-bounds arrow indicator. `MARGIN` keeps the arrow this many pixels inside
## the screen edge so it is always visible; the rest are arrow/label sizing. Visual
## tuning.
const INDICATOR_MARGIN := 28.0
const INDICATOR_SIZE := 14.0
const INDICATOR_LABEL_SIZE := 13

var _half_extent: Vector2 = MapBorder.HALF_EXTENT
## Registered players, duck-typed (anything exposing `global_position` and
## `is_out_of_bounds()`), so a test stub stands in without a scene tree.
var _players: Dictionary = {}   # id -> player
var _colors: Dictionary = {}    # id -> Color
var _labels: Dictionary = {}    # id -> String
var _was_out: Dictionary = {}   # id -> bool (out-of-bounds last tick, for edge detect)
## Live contact flashes: each `{ "pos": Vector2 (overlay space), "elapsed": float }`.
var _flashes: Array = []


## Registers (or re-registers, each round) a player with the colour and name the
## HUD already computed. Re-registering re-arms the out-of-bounds edge detection so
## a fresh round's player starts in-bounds.
func register_player(player_id: int, player: Object, color: Color, label: String) -> void:
	_players[player_id] = player
	_colors[player_id] = color
	_labels[player_id] = label
	_was_out[player_id] = false


func _process(delta: float) -> void:
	advance(delta)
	queue_redraw()


## Advances flash lifetimes and spawns a new contact flash whenever a registered
## player newly crosses out of bounds — the visual analogue of the one-shot bounce
## impulse / `BORDER_CONTACT` cue in [method Player._update_border], fired once per
## excursion via the same first-contact edge. Scene-free given duck-typed players,
## so the flash cadence is unit-tested directly.
func advance(delta: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i]["elapsed"] += delta
		if _flashes[i]["elapsed"] >= FLASH_DURATION:
			_flashes.remove_at(i)
	for id in _players:
		var p = _players[id]
		if not is_instance_valid(p):
			continue
		var oob: bool = p.is_out_of_bounds()
		if oob and not _was_out.get(id, false):
			var pt := border_contact_point(p.global_position, _half_extent)
			_flashes.append({"pos": world_to_overlay(pt, _half_extent), "elapsed": 0.0})
		_was_out[id] = oob


## The currently active contact flashes as `{ "position": overlay-space Vector2,
## "alpha": float }`, alpha faded by [method flash_alpha]. Drives [method _draw];
## exposed so the spawn/expiry behaviour is testable without a live canvas.
func flashes() -> Array:
	var out: Array = []
	for f in _flashes:
		out.append({
			"position": f["pos"],
			"alpha": flash_alpha(f["elapsed"], FLASH_DURATION),
		})
	return out


## The out-of-bounds player indicators, one per registered, still-valid player
## currently out of bounds: `{ "position", "angle", "color", "label" }`. `position`
## is the arrow's overlay-space point (clamped on-screen), `angle` points outward
## toward the player. Scene-free given duck-typed players, so the geometry is
## testable without a live canvas.
func indicators() -> Array:
	var out: Array = []
	for id in _players:
		var p = _players[id]
		if not is_instance_valid(p) or not p.is_out_of_bounds():
			continue
		out.append({
			"position": indicator_position(p.global_position, _half_extent, INDICATOR_MARGIN),
			"angle": indicator_angle(p.global_position),
			"color": _colors.get(id, Color.WHITE),
			"label": _labels.get(id, ""),
		})
	return out


func _draw() -> void:
	# Persistent semi-transparent red "danger" frame at the play-area edge.
	var size := _half_extent * 2.0
	draw_rect(Rect2(Vector2.ZERO, size), FRAME_COLOR, false, FRAME_WIDTH)
	# Transient contact flashes (fading sparks at the contact point).
	for f in flashes():
		var c := FLASH_COLOR
		c.a = f["alpha"]
		draw_circle(f["position"], FLASH_RADIUS, c)
	# Out-of-bounds player arrows + names.
	var font := ThemeDB.fallback_font
	for ind in indicators():
		_draw_indicator(ind["position"], ind["angle"], ind["color"], ind["label"], font)


## Draws one out-of-bounds arrow (a small triangle pointing along `angle`) in the
## player's colour, with their name set just above it.
func _draw_indicator(pos: Vector2, angle: float, color: Color, label: String, font: Font) -> void:
	var tip := pos + Vector2(INDICATOR_SIZE, 0.0).rotated(angle)
	var base_l := pos + Vector2(-INDICATOR_SIZE * 0.6, -INDICATOR_SIZE * 0.7).rotated(angle)
	var base_r := pos + Vector2(-INDICATOR_SIZE * 0.6, INDICATOR_SIZE * 0.7).rotated(angle)
	draw_colored_polygon(PackedVector2Array([tip, base_l, base_r]), color)
	if label != "" and font != null:
		draw_string(font, pos + Vector2(-10.0, -INDICATOR_SIZE - 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, INDICATOR_LABEL_SIZE, color)


# ---------------------------------------------------------------------------
# Pure geometry (no scene-tree dependency — covered by tests/)
# ---------------------------------------------------------------------------

## Maps an arena/world-space point into this overlay's screen space. Every arena
## centres its `Camera2D` at the origin over the `2 * half_extent` viewport (the
## border invariant on [MapBorder]), so world `(0, 0)` is the screen centre and the
## border at `±half_extent` maps to the viewport corners `(0,0)`..`(2*half_extent)`.
## Pure.
static func world_to_overlay(world: Vector2, half_extent: Vector2 = MapBorder.HALF_EXTENT) -> Vector2:
	return world + half_extent


## Linear fade from `1.0` at `elapsed == 0` to `0.0` at `elapsed == duration`,
## clamped to `[0, 1]`; `0.0` for a non-positive duration. Pure.
static func flash_alpha(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)


## The point on the border nearest an out-of-bounds body centre: the centre clamped
## component-wise into the play-area box. For a player past the right edge this is
## the contact point on the right border (same x as the edge, the player's y), and
## a corner excursion clamps both axes. Pure.
static func border_contact_point(center: Vector2, half_extent: Vector2 = MapBorder.HALF_EXTENT) -> Vector2:
	return Vector2(
		clampf(center.x, -half_extent.x, half_extent.x),
		clampf(center.y, -half_extent.y, half_extent.y))


## Overlay-space position for an out-of-bounds player's arrow: the player's mapped
## position clamped to stay `margin` pixels inside the screen edges, so the arrow is
## always on-screen even when the player is far off it. Pure.
static func indicator_position(player_world: Vector2, half_extent: Vector2 = MapBorder.HALF_EXTENT, margin: float = INDICATOR_MARGIN) -> Vector2:
	var screen := world_to_overlay(player_world, half_extent)
	var size := half_extent * 2.0
	return Vector2(
		clampf(screen.x, margin, size.x - margin),
		clampf(screen.y, margin, size.y - margin))


## Direction (radians) the arrow points: outward from the play-area centre toward
## the player. The world origin is the screen centre, so this is simply the
## player's world-position angle. Pure.
static func indicator_angle(player_world: Vector2) -> float:
	return player_world.angle()

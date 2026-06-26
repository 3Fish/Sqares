class_name PlayerPalette

## The fixed set of 16 named player colours offered in match setup (#132).
##
## The maintainer settled the colour model as a fixed palette (not a free RGB
## picker) shown as swatches, with duplicates allowed, and the colour tinting only
## the in-arena player character (the HUD keeps its own pip palette — #132 A1/A3).
## Each entry is named because the team-win announcement names a team by its
## colour ("Team Babyblue wins!") once teams-from-colours lands (#134 / #132 A4),
## so the names live here as the single source the announcement reuses.
##
## Pure static data + helpers (no scene-tree state) so the palette and its
## clamp/default logic are unit-testable per the conventions in `CLAUDE.md`. The
## first four entries mirror the HUD's default per-player order so an unconfigured
## match (editor playtest, tests) still spawns sensibly distinct squares.

const COLORS: Array[Dictionary] = [
	{"name": "Sky", "color": Color(0.4, 0.7, 1.0)},
	{"name": "Orange", "color": Color(1.0, 0.5, 0.3)},
	{"name": "Lime", "color": Color(0.4, 1.0, 0.5)},
	{"name": "Gold", "color": Color(1.0, 0.9, 0.3)},
	{"name": "Crimson", "color": Color(0.9, 0.2, 0.25)},
	{"name": "Violet", "color": Color(0.6, 0.4, 0.95)},
	{"name": "Teal", "color": Color(0.2, 0.8, 0.8)},
	{"name": "Pink", "color": Color(1.0, 0.5, 0.75)},
	{"name": "Babyblue", "color": Color(0.6, 0.85, 1.0)},
	{"name": "Mint", "color": Color(0.6, 1.0, 0.8)},
	{"name": "Coral", "color": Color(1.0, 0.6, 0.5)},
	{"name": "Lavender", "color": Color(0.8, 0.7, 1.0)},
	{"name": "Sand", "color": Color(0.9, 0.8, 0.55)},
	{"name": "Magenta", "color": Color(0.9, 0.3, 0.8)},
	{"name": "Forest", "color": Color(0.25, 0.6, 0.35)},
	{"name": "Slate", "color": Color(0.5, 0.55, 0.65)},
]


## Number of colours in the palette.
static func count() -> int:
	return COLORS.size()


## Clamps an arbitrary index into the valid palette range so a stale/out-of-range
## saved or replicated index always resolves to a real colour.
static func clamp_index(index: int) -> int:
	return clampi(index, 0, COLORS.size() - 1)


static func color_at(index: int) -> Color:
	return COLORS[clamp_index(index)]["color"]


static func name_at(index: int) -> String:
	return COLORS[clamp_index(index)]["name"]


## The palette index a player defaults to when nothing was chosen: each player id
## wraps into the palette, so the first four players get the first four (distinct)
## colours and a hypothetical fifth wraps back around rather than going invalid.
static func default_index(player_id: int) -> int:
	return posmod(player_id, COLORS.size())

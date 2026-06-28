# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Sqares** — a 2D rogue-like arena battle shooter (Godot 4.6, GL Compatibility renderer). Players battle in arenas (FFA or teams); after each round losing players pick modifier cards. Free, open-source, and built mod-first: nearly all gameplay content (stats, cards, arenas, game modes, sounds) is registered at runtime through the mod system rather than hard-coded.

## Automation

This repo is maintained by a recurring autonomous routine. Its full operating
manual lives in the repo so it can be reviewed and changed through commits:

- `docs/dev-routine.md` — what the routine does each run (PR maintenance,
  suggestion refinement, issue implementation). The platform-side routine is just
  a thin pointer to this file.
- `docs/suggestion-workflow.md` — how community feature suggestions (filed via the
  issue form) are refined into greenlit work.

## Commands

The Godot binary on this machine is `godot` (Godot 4.6).

```bash
# Run the headless test suite (gates CI conceptually; exits non-zero on failure)
godot --headless --script res://tests/run_tests.gd

# Open the editor on this project
godot --editor --path .

# Run the game (main scene: scenes/ui/main_menu.tscn)
godot --path .

# Headless import (needed once after checkout / before export)
godot --headless --verbose --import
```

There is no single-test flag. The runner discovers every `_test_*` method in every script under `tests/cases/`. To run a subset, temporarily move other case files out of `tests/cases/`, or invoke a case script's methods from a scratch script.

CI (`.github/workflows/export.yml`) runs the headless **test suite** first, then validates that the project **exports** for linux/windows/macos via `barichello/godot-ci:4.6` (the export job `needs: test`). A green run means tests pass and all three platforms build. Still run tests locally before pushing — it's faster than waiting on CI.

## Test framework

Custom minimal harness — no GUT or third-party framework.

- `tests/run_tests.gd` — `SceneTree` runner. Discovers case scripts, instantiates each, runs every `_test_*` method, calls optional `before_each`/`after_each` around each.
- `tests/test_case.gd` — `TestCase` base class (`class_name TestCase`). Provides `assert_true/false/eq/almost_eq/null/not_null`. The runner injects itself as `runner`.
- A new test is a script in `tests/cases/` that `extends TestCase` with `_test_*` methods.
- Tests favor **pure static helpers** that have no scene-tree dependency (see `MatchDirector.clamp_player_count` / `resolve_spawn_positions`). When adding logic, prefer extracting a static, testable function over embedding it in `_ready`/`_process`.

## Architecture

### AutoLoad singletons (project.godot `[autoload]`)

Order matters — these are the global services every system talks to:

- `GameManager` (`scripts/core/game_manager.gd`) — match/round **state machine** (`State` enum: MENU → ROUND_INTRO → ROUND → ROUND_END → CARD_SELECTION → MATCH_END). Tracks `win_counts`, emits `state_changed` / `round_started` / `round_ended` / `match_ended`. Holds no scene references — pure logic.
- `ModLoader` (`scripts/mods/mod_loader.gd`) — discovers `mod.gd` files in `res://mods/` and `user://mods/` and calls their `_on_load()`. Runs via `call_deferred` so all other AutoLoads are ready first.
- Registries (`scripts/mods/`): `StatRegistry`, `CardRegistry`, `LevelRegistry`, `GameModeRegistry`, `PlayerActionRegistry` — runtime dictionaries populated by mods at load. **No fixed enums** for stats/cards/arenas; everything is string-keyed and registered dynamically.
- `UIManager` (`scripts/mods/ui_manager.gd`), `AudioManager` (`scripts/audio/audio_manager.gd`), `NetworkManager` (`scripts/multiplayer/network_manager.gd`).

### Mod system (central design)

Built-in content is itself a mod (`mods/base_game/mod.gd`) and uses the **same public API** third-party mods would. To understand or extend content, start here:

- A mod's `mod.gd` `extends SqaresModBase` (`scripts/mods/sqares_mod_base.gd`) and overrides `_on_load()` to register content. **Never override `_ready()`** in a mod — it runs before other AutoLoads are guaranteed ready.
- Base game registers stats (`StatRegistry.register("move_speed", 300.0)`), arenas (`LevelRegistry.register("crossroads", preload(...))`), and cards in `_on_load()`. Content is intentionally sparse — many systems are stubbed with `#NN` issue references pointing to the feature branch that fills them in (e.g. the card effect engine is `#20`).
- Registries follow a consistent pattern: `register(...)`, `get_*`, `has_*`, last-registration-wins for overrides (a mod can replace a built-in card by re-registering its `id`).

### Match flow

`scenes/match.tscn` contains a `MatchDirector` (`scripts/match/match_director.gd`) alongside `ArenaContainer`, `PlayersContainer`, and `HUD` siblings. The director:
- Clamps player count to 2–4 (local couch play; input maps and HUD support p1–p4).
- Drives the round lifecycle (spawn arena + players → fight → detect last-alive → record win via `GameManager` → next round or match end).
- Spawns players from `Arena.get_spawn_points()` (nodes named `Spawn*`), with fallback fan-out spacing when an arena has fewer spawns than players.

### Player & stats

- `Player` (`scripts/player/player.gd`, `CharacterBody2D`) — platformer movement with coyote time, jump buffering, wall-sliding; reads input via per-player action names `p%d_*` (`player_id + 1`). Composes `Health` and `Weapon` child nodes.
- `PlayerStats` (`scripts/player/player_stats.gd`) — a stat bag initialized from `StatRegistry.get_defaults()`. Card effects call `Player.apply_stats(overrides)` which merges into `PlayerStats` and re-propagates to `Health`/`Weapon` via `_sync_stats`. This is the seam between the card system and live gameplay.
- `Arena` (`scripts/arena/arena_base.gd`, `class_name Arena`) — base for arena scenes; enumerates `Spawn*` children and wires an optional `KillZone` Area2D that deals `INF` damage on body entry.

## Conventions

- **GDScript indentation is tabs** (`.editorconfig`: `indent_size = 4` for `.gd`). YAML/JSON use 2-space indent. UTF-8, LF, trailing-whitespace trimmed, final newline.
- New cross-cutting gameplay values should be **registered stats**, not constants, so mods can override them. Per-node tuning constants (movement feel, timers) stay as `const` in the relevant script.
- Many files reference future work as `#NN` (GitHub issue numbers) and `feature/NN-*` branch names — these mark deliberately incomplete subsystems, not bugs.
- `.gd.uid` files are Godot-generated script UIDs; commit them alongside their `.gd`.

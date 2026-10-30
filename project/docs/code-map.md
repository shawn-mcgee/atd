# Task-oriented code map

Read `AGENTS.md` first. Open only the relevant entries below. The current game and controls are described in the root `README.md`; older prototype specs are historical. Proposed changes in `ideas.md` are not implemented requirements.

| Task | Start here | Focused tests (`tools/test-game.py --name …`) |
| --- | --- | --- |
| Startup, loading screen, restart | `scenes/loading.tscn`, `view/loading.gd`; prepared core handoff in `view/game.gd` | `loading`, `top-down` |
| Tick loop, command dispatch, IDs, replay | `engine/simulation.gd`: `initialize`, `enqueue`, `step`, `apply_command`, `snapshot`; `engine/state_codec.gd` | `engine`, `gameplay-baseline` |
| Prices, health, speeds, production stats | `engine/expedition_rules.gd` | `mission-upgrade`, `engine` |
| Selection, hotkeys, camera, command targeting | `view/game.gd`: `pick`, `target_click`, `_input`, `_unhandled_input` | `top-down` |
| Generate or integrate 2D art | [Sprite integration](sprite-integration.md), `view/sprite_library.gd`, root `tools/prepare-sprites.py`; [generation brief](asset-generation-brief.md) for art specs | `sprites`, `top-down`; rendered gallery |
| Drawing, footprint polygons, tile geometry | `view/terrain_renderer.gd`, `view/primitives.gd`; `engine/structure_footprints.gd`; `engine/hex_grid.gd` | `top-down`, `mission-upgrade` |
| Selected unit/structure silhouettes | `view/selection_highlight.gd`, `view/shaders/selection_mask.gdshader`, `selection_outline.gdshader` | `top-down`, `sprites`; preview `--combat --selection` |
| HUD, tooltips, contextual menus | `view/game_hud.gd`, `rts_theme.gd`, `rts_panel.gd`, `rts_icons.gd`; `view/game.gd`: `refresh_context_commands` | `top-down` |
| Wispy darkness shader / visual light mask | `view/darkness.gd`, `view/shaders/darkness.gdshader`, `view/shaders/light_mask.gdshader` | `darkness`, `top-down`; rendered preview |
| Minimap, discovery, illumination | `view/minimap.gd`; `engine/simulation.gd`: `record_exploration`, `rebuild_light`; `engine/illumination.gd`, `resource_fields.gd` | `expedition-scouts`, `top-down` |
| Frame performance / profiling | [Performance](performance.md), `view/terrain_renderer.gd`, `view/minimap.gd`; `engine/expedition_navigation.gd`: `cache_light_weights` | `terrain-renderer`, `light-weights`; rendered `benchmark-frames.gd` |
| Routes, terrain, ramps, platforms | `engine/expedition_navigation.gd`, `expedition_terrain.gd`, `structure_footprints.gd` | `mission-upgrade`, `construction-clearance` |
| Unit movement, boarding, unload | `engine/expedition_unit.gd`; `simulation.gd`: `advance_movement`, `unload`; `soft_unit_spacing.gd` | `unit-spacing`, `expedition-seating` |
| Construction/repair and clearance | `simulation.gd`: `valid_site`, `order_build`, `process_order`, `continue_maintenance`; `construction_clearance.gd` | `construction-clearance`, `engineer-maintenance` |
| Mining/convoys/crew priorities | `engine/complex_commands.gd`, `foot_expeditions.gd`, `expedition_scouts.gd` | `expedition-delivery`, `expedition-seating`, `expedition-scouts`, `nearest-receiver` |
| Exploration and interruptions | `engine/exploration_expeditions.gd`; `complex_commands.gd`: `start_expedition`, `interrupt` | `exploration-interruptions`, `expedition-seating` |
| Combat facing, muzzle alignment, mining adjacency | `view/sprite_library.gd`, root `tools/prepare-sprites.py`, `engine/resource_fields.gd`; shot dispatch in `engine/simulation.gd` | `combat-and-mining`, `sprites`, mining expedition suites |
| Infantry and convoy patrol/tactics | `engine/tactical_orders.gd`, `tactical_groups.gd`, `expedition_patrol.gd` | `expedition-patrol`, `mission-upgrade`, `engine` |
| Economy, power, gates, batteries, drilling | `engine/expedition_economy.gd`, `expedition_power.gd`, `gate_passage.gd`, `vehicle_systems.gd` | `mission-upgrade`, `expedition-delivery`, `engine` |
| Creature AI, reinforcement, combat | `engine/predator_director.gd`, `predator.gd`, `turret_system.gd`; `simulation.gd`: `combat_tick` | `predators`, `predator-pressure`, `mission-upgrade` |
| Expanded map and terrain density | `engine/scenario_layout.gd`, `expedition_terrain.gd`; radius 84, 72 ridges | `map-generation`, `mission-upgrade`, `darkness` |
| Map generation, mission lifecycle | `engine/scenario_layout.gd`, `hive_mission.gd` | `mission-upgrade`, `gameplay-baseline` |
| Export, test runner, rendered preview | root `tools/build-web.ps1`, `tools/test-game.py`; `project/tools/preview-prototype.gd` | Run the affected tool |

Paths above are relative to `project/` unless marked root. Locate functions with `rg -n '^func NAME' path`, then read a bounded range. Shared scene-free test setup is in `tools/fixtures/simulation_fixture.gd` and `mechanics_layout.gd`. Run tests from the repository root; supply `--godot <executable>` if needed. Logs and previews are ignored under `project/art_source/.build/`.

For architecture/API changes, read [engine.md](engine.md). For a presentation-only task, avoid loading unrelated economy/AI modules. Preserve the deterministic core/view boundary.

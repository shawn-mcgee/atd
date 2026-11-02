# Gameplay core and top-down view

`engine/simulation.gd` is the authoritative game. It extends `RefCounted`, owns plain state objects and existing gameplay systems, and needs no scene tree, camera, GPU, input devices, or physics world. Godot math types and AStar navigation remain dependencies. This is a small simulation boundary, not a new general-purpose engine or a rewrite of game rules.

## Driving a game

```gdscript
const Simulation = preload("res://engine/simulation.gd")
var game = Simulation.new()
game.initialize(42)
game.enqueue({
    "kind": "context",
    "actors": [game.units[0].simulation_id],
    "point": Vector3(-8, 0, -5),
    "tick": 0,
})
game.step()
```

Each step advances 0.1 seconds. Six fixed movement substeps preserve smooth steering and spacing. Commands execute before movement, ordered by tick and insertion sequence. IDs are assigned locally and sequentially; gameplay never depends on process object IDs. The view accumulates real elapsed time, runs complete ticks, and interpolates positions for display. Pausing advances no ticks. Rendering never advances simulation time.

Coordinates retain the old x/z ground plane and y elevation. This preserves navigation, range, ramp, platform, and sight-line rules and allows a future 3D view to reuse the same state. The map, combat, power, economy, production, construction, expeditions, and mission logic moved from the previous renderer with their rule values intact.

## Commands

Every command includes `kind` and an `actors` array of simulation IDs. Optional fields include `tick` (defaults to the current tick), `append` (Shift behavior), and `direction` (hex footprint rotation 0–5). Use IDs for targets, not object references.

| Kind | Additional fields |
| --- | --- |
| `context` | `point`, optional `target` ID; move, board, gather, repair, deliver, attack, or take core |
| `build` | `building` rule key, `point` |
| `walls` | `start`, `point` endpoint |
| `train` | `unit` rule key |
| `expedition` | `point`, `mining` boolean |
| `tactical` | `mode`: `attack_move`, `attack`, `defend`, `patrol`, or `drill`; `point`, optional `target` |
| `repair` | `target` structure ID |
| Selection actions | `board_squad`, `unload`, `load_nearest`, `stock_depot`, `return_home`, `escort`, `stop_selected`, `destroy_selected`, `cancel_training` |
| Toggles and reload | `toggle_auto_recharge`, `toggle_repeater`, `toggle_gate`, `toggle_gate_lock`, `reload_selected_turrets`, `toggle_turret_reload` |

The renderer resolves a mouse position into a point/target before submitting a command. UI selection and targeting modes are local to the view. The engine's temporary `selected` list exists only while dispatching a command, to preserve the existing selection-based gameplay methods. Those lower-level methods are also available to mechanics tests; runtime input uses the queue.

## Observation, replay, and lifetime

Views read actor arrays, resources, explored cells, power grids, mission state, and scanner contacts. `events` is a bounded stream of messages and shooter-tagged shot effects identified by increasing serial numbers. Consume by serial without clearing it or making gameplay depend on a consumer.

`snapshot()` and `state_hash()` provide canonical diagnostic state. `replay_data()` returns a versioned seed and command log; JSON round-trip it and pass it to `load_replay()` on a fresh simulation. Then run the same number of ticks. This is command replay from a new game, not save-game restoration. Floating-point math and Godot AStar remain in use: replay is validated on the same engine/runtime, without claiming cross-platform network lockstep.

`dispose()` breaks actor-reference cycles when restarting or replacing a simulation. Scene nodes belong only to the view; removing a view does not require freeing a tree of gameplay nodes.

## Presentation

`view/primitives.gd` shades and outlines the full occupied hex-tile boundary for placement previews, including concave joins and rotated multi-cell footprints. Walls use full-tile sprites and hex bounds. Other placed sprite bounds retain their outer tile-center hulls and 0.8-radius single-cell hexagons. Buildings have no filled polygon foundations. `Simulation.BUILD_KINDS` defines the enabled construction catalog; ramps and platforms are temporarily excluded from both UI and build commands, while their legacy terrain helpers remain available to fixtures.

Approved art is drawn through `view/sprite_library.gd`. Original sheets are preserved, with atlas metadata, facing corrections, and a 30-degree flat-top-to-pointy-top correction for hex artwork. Full building illustrations are fitted to footprint bounds instead of clipped into triangular fragments. Sprite alpha extends picking to visible artwork; labels and status bars never participate. See [sprite integration](sprite-integration.md) for preparation commands and maintenance details.

The minimap reads the engine's explored-cell memory; exploration does not depend on a minimap existing. All sprite caches, effects, headings, and gate animation remain view-only state. Elevation and navigation remain in the core despite the overhead presentation.

## Validation

`test-gameplay-baseline.gd` compares 10 mechanics checkpoints over 200 ticks against the former 3D game, using the frozen original layout and predator director to check movement, queued construction, production, economy, and early enemy behavior. Later world-dependent enemy paths are intentionally excluded after the 50% map expansion. Its fixture is data captured before deleting the old renderer. The comparison uses its historical work radius through a test subclass; current adjacent-tile work and field delivery loops are covered by 	est-todo-logistics.gd. Comparisons tolerate 0.0001 for floating-point differences from replacing native Node3D rotations with state values. Packed paths and queues were copied when capturing checkpoints to prevent later mutation of the fixture.

`test-engine.gd` verifies independently allocated simulations and a serialized replay. `test-top-down.gd` checks picking, footprint sizes, projection inversion, contextual construction, command dispatch, resize behavior, rendering isolation, and equal outcomes at 30/60/144 FPS. The remaining suites preserve focused mechanics checks using a scene-free fixture.

Gameplay defaults now come from `config/gameplay.json`; see [gameplay-balance.md](gameplay-balance.md). The todo overhaul intentionally removes battery mechanics, adds HQ healing and seven-cell balanced extractors, extends repeater links, and makes illumination terrain-aware. Run replays with the same configuration. Derived flood-fill/light masks and route caches stay outside snapshots.

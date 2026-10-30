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

Views read actor arrays, resources, explored cells, power grids, mission state, and scanner contacts. `events` is a bounded stream of messages, sound cues, and shot effects identified by increasing serial numbers. Consume by serial without clearing it or making gameplay depend on a consumer.

`snapshot()` and `state_hash()` provide canonical diagnostic state. `replay_data()` returns a versioned seed and command log; JSON round-trip it and pass it to `load_replay()` on a fresh simulation. Then run the same number of ticks. This is command replay from a new game, not save-game restoration. Floating-point math and Godot AStar remain in use: replay is validated on the same engine/runtime, without claiming cross-platform network lockstep.

`dispose()` breaks actor-reference cycles when restarting or replacing a simulation. Scene nodes belong only to the view; removing a view does not require freeing a tree of gameplay nodes.

## Primitive presentation

`view/primitives.gd` computes the convex hull of occupied tile centers for structures with three or more footprint cells. Thus HQ uses the outer six centers, generators/barracks are triangles, and garages are quadrilaterals. Single-cell structures use a hexagon of 0.8 tile radius. A two-point ramp footprint needs area to draw and pick, so it uses a narrow ribbon joining those centers. Elevation stays in gameplay even though the camera looks straight down.

Units and visible enemies are circles, with facing marks, selection outlines, and focus lines. Labels, HUD, and status bars never participate in picking. A click tests unit circles and structure polygons first, then falls through to the terrain coordinate conversion. The minimap reads the engine's explored-cell memory; exploration no longer depends on the minimap existing.

## Validation

`test-gameplay-baseline.gd` compares 16 checkpoints over 320 ticks against the former 3D game, including seeded layout, movement, queued construction, production, economy, enemy behavior, and combat. Its fixture is data captured before deleting the old renderer. Comparisons tolerate 0.0001 for floating-point differences from replacing native Node3D rotations with state values. Packed paths and queues were copied when capturing checkpoints to prevent later mutation of the fixture.

`test-engine.gd` verifies independently allocated simulations and a serialized replay. `test-top-down.gd` checks picking, footprint sizes, projection inversion, contextual construction, command dispatch, resize behavior, rendering isolation, and equal outcomes at 30/60/144 FPS. The remaining suites preserve focused mechanics checks using a scene-free fixture.

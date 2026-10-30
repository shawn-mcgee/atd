# Project instructions

This is a Godot 4.7.2 project. Open `project/project.godot`; run repository commands from the outer repository root. `res://` paths are relative to `project/`.

## Efficient working style

Minimize token usage without sacrificing quality.

- Start with this file and the task-specific entry in `project/docs/code-map.md`. Read only the relevant functions or short ranges; use `rg -n` to locate them. Do not dump whole large files, asset catalogs, or repeated logs.
- Batch independent searches/reads into one tool call and group related edits into a coherent change. Keep dependencies sequential.
- Finish a coherent implementation before testing. Run the focused suites once, then the required final checks. Repeat only to diagnose a failure or validate a subsequent fix; avoid repeated smoke tests after small edits.
- Keep commentary and final reports short: result, material limitation, validation. Summarize successful checks instead of reproducing their output.
- Update the narrowest relevant documentation when behavior or architecture changes. Keep this file and the code map concise; link deeper details instead of duplicating them.
- Preserve quality: inspect affected callers, handle edge cases, run appropriate validation, and review the final diff. Token savings must not come from skipping necessary work.

## Simulation and views

- `project/engine/` owns gameplay. Its entry point is `simulation.gd`, a headless `RefCounted` simulation. Actors are plain `SimEntity`, `SimUnit`, `SimStructure`, and `SimPredator` state objects, not scene nodes.
- Preserve deterministic fixed ticks: initialize with an explicit seed, enqueue commands using actor IDs, and call `step()`. Do not poll input, use wall-clock time, call unseeded randomness, or access rendering/scene-tree APIs in the engine.
- Ground positions retain Vector3 coordinates: x/z are the hex-world plane and y is elevation. Vector3 and AStar3D are math/navigation utilities here; they do not require a 3D renderer or physics scene.
- `project/view/` handles input, camera, picking, HUD, and drawing. Gameplay actions go through the engine command queue. Camera movement, selection, previews, and drawing must not mutate simulation state.
- The active scene is `project/scenes/top_down.tscn`. Approved sprite sheets render units and structures; footprints remain hex-grid geometry for placement/selection. No filled structure foundations. See `project/docs/sprite-integration.md` for atlas preparation, south-facing corrections, flat-top art rotation, and procedural gates.
- Keep gameplay and balancing unchanged when editing presentation. Prospective ideas in `ideas.md` are not automatically authorized gameplay changes.
- The 3D models, 3D renderer/shaders, and Asset Forge pipeline were removed. The new 2D darkness shaders live under `project/view/shaders/`; keep them presentation-only.
- Do not manually edit `.godot/` or generated import caches.

## Validation

Run `python tools/test-game.py --godot <path-to-Godot> --jobs 3` from the repository root. The runner imports first, then runs all headless suites, and treats script errors as failures even if Godot returns zero. Logs go to ignored `project/art_source/.build/test-results/`.

`test-engine.gd` checks seeded deterministic replay. `test-top-down.gd` checks view isolation, footprints, picking, HUD, resize, and different render frame rates. `test-gameplay-baseline.gd` compares against checkpoints captured from the previous 3D game. Other suites cover mission mechanics and logistics directly through the headless core.

For rendered review: `Godot --path project --script res://tools/preview-prototype.gd -- --engineer --seed=42`. The preview script saves a PNG under ignored `project/art_source/.build/`. Use `tools/build-web.ps1` for a local web export. Keep machine-specific executable paths and generated build output out of Git.

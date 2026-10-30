# Frame performance

Run from the repository root, with other test/game processes stopped:

```powershell
& <Godot-console-executable> --path project --script res://tools/benchmark-frames.gd
# Exercise creature AI immediately; shorter diagnostic run:
& <Godot-console-executable> --path project --script res://tools/benchmark-frames.gd -- --active --quick
```

The rendered benchmark disables VSync and the frame cap, uses seed 42 at 1280×800, warms each case, then measures at least 3,000 frames / 5 seconds. Cases cover the starting base, fully surveyed 21,421-cell map, panning, and rotation. `--active` advances 175 deterministic ticks before sampling; `--quick` uses at least 1,000 frames / 1 second. Output includes median, p95, p99, maximum, sample count, draw calls, and simulation ticks exceeding 4 ms with route/segment costs. Loading, initial map generation, full-survey injection, and warm-up are excluded. These are elapsed rendered frame intervals, not reciprocal average FPS. Avoid concurrent tests, background games, or window minimization when comparing runs; VSync/driver limits affect normal gameplay independently.

## Architecture

- `view/terrain_renderer.gd` retains four MultiMesh batches. Positions and atlas UVs are uploaded only when surveyed terrain changes. The camera changes one parent transform; cliffs retain world-Z depth order and bottom alignment. Resource sprites remain between ground and cliff layers.
- `view/shaders/terrain.gdshader` samples the same GPU illumination texture as darkness. Terrain no longer samples lights, constructs polygons, or sorts all surveyed cells and thousands of off-screen rocks every frame. Fog quality and gameplay visibility are preserved.
- `view/minimap.gd` caches surveyed terrain in an ImageTexture and draws contacts/camera bounds at 10 Hz. It invalidates on exploration, navigation revision, or resize.
- `engine/expedition_navigation.gd` caches exact light weights only within deterrent source radii, then restores those weights after a route. Ordinary routes retain weight 1. Flat-cell segment samples reuse graph elevation and share one axial conversion; ramp cells retain interpolated slope checks. A bounded 256-entry exact-route cache avoids calculating the same probe and movement route twice; geometry revisions and light-source changes invalidate the relevant results. These caches are derived and excluded from snapshots.

The initial starting-base benchmark was approximately 28 ms median. After the renderer changes, starting-base/full-survey/pan/orbit medians were about 0.5–0.6 ms and p99 about 1.1–1.6 ms on this machine (RX 6700 XT, Godot 4.7.2 debug executable, GL Compatibility). These figures describe warmed rendering, not a guarantee that every simulation or operating-system frame is below 4 ms. AI route bursts and large exploration/geometry updates can still exceed that budget; use the active benchmark to track these separately.

Validation: `terrain-renderer` checks retention, invalidation, projection and core isolation; `light-weights` compares sparse lighting costs against full-map sampling; existing movement, mission, predator, replay and baseline suites cover behavior preservation. Rendered previews are required because headless tests do not validate GPU appearance.

## Final active-AI sample

After all changes, a separate `--active --quick` run (no concurrent tests) measured:

| Case | Median ms | p95 ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: |
| Base | 0.615 | 1.366 | 1.998 | 13.857 |
| Fully surveyed | 0.601 | 1.084 | 1.665 | 5.575 |
| Pan | 0.556 | 0.906 | 1.408 | 9.852 |
| Orbit | 0.568 | 0.978 | 1.482 | 4.997 |

The largest frame included a 13.054 ms simulation tick at tick 184 (17 route requests, 9.893 ms total routing). The 4 ms budget is met for typical frames and p99 in these cases, but not every AI tick. The earlier approximately 50 ms activation hitch is substantially reduced. All 21 headless suites passed, including deterministic baseline/replay and the new renderer/light-cost checks; the cliff/ground preview was reviewed using the real GL renderer.

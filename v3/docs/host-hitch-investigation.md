# Host hitch investigation

Measured on 2026-11-11 with Godot 4.7.2, an Intel Core Ultra 5 235U,
seed 472 and the standard 3,997-tile map.

## Reproduced causes

The aging-match trace reproduced 106?112 ms host ticks after roughly seven
simulated minutes. A single Ravager or Thresher route consumed about 102 ms.
The call chain was `_unit_step` ? `_probe_step` ? `move_to` ? `_route_path`.
These spikes did not come from Gloom updates or snapshot compression.

Large bodies enabled an A* neighbor callback which ran swept capsule/hex geometry
for edges visited by the search. Construction cleared its cache, so a newly
unlocked creature or an organ starting construction could expose the full cold
search cost again. Even a warm search retained per-edge script overhead.

A second fixture with 200 units and 100 structures reproduced a 363 ms combat
burst. Probe units planned distant Anchor routes before discovering adjacent
opponents. Route smoothing also evaluated the entire future path immediately,
concentrating geometry work when many units engaged or retreated together.

## Changes

- Two native A* graphs precompute clearance for the body-size band used by current
  vehicles, Ravagers and Threshers. Only the two shared neighboring hexes can
  obstruct an adjacent edge in that band. Terrain/structure changes update the six
  affected surrounding edges; searches have no script neighbor callbacks.
- Normal and dark graphs retain illumination weights. Friendly unlocked gates are
  admitted only for the current query and restored afterward. Boundary and other
  body sizes retain the general exact-geometry implementation.
- Probe units acquire visible contacts before considering distant Anchor routes.
- Route smoothing handles the next segment immediately and retains the safe native
  remainder. Subsequent segments smooth as units reach them. Exact swept-body
  checks, gate handling, final destinations and movement budgets still apply.
- Gate clearance queries use the existing per-cell structure index.

## Recorded results

| Native workload | Before | Final |
| --- | ---: | ---: |
| Cold long-distance clearance search, mean | 73.41 ms | 0.33 ms |
| Warm long-distance clearance search, mean | 9.90 ms | 0.33 ms |
| Ten-minute aging match, worst host tick | 111.59 ms | 18.18 ms |
| Thirty-second 200-unit combat fixture, worst host tick | 363.28 ms | 40.50 ms |

The final five-player capture completed seven simulated minutes and peaked at
20.88 ms, including filtered snapshot generation, binary encoding and compression
for four guests. The fixture assumes snapshots can be sent immediately; it does
not simulate transport congestion or Internet latency.

Aging fixtures keep Anchors alive with increased health and supply large resource
banks, while ordinary colony production, AI, movement and combat continue. The
stress fixture uses a fixed mixed army and construction layout, and disables
colony expansion. Populations diverge across the aging runs (62 versus 70 units at
ten minutes), so their averages are not a controlled FPS comparison. The isolated
path benchmark compares both implementations in the same process.

These measurements exclude browser/WASM execution, rendering and GPU time. Dense
combat can still exceed a 16.7 ms presentation-frame budget; the original 4 ms
CPU goal remains unmet. Remaining captured costs include visibility, construction
navigation refreshes, separation and snapshot encoding. This fixes the reproduced
stalls without claiming every possible hitch is eliminated.

## Reproduce and capture

Run from `v3/`:

```sh
npm run profile:cpu -- --path-query
npm run profile:cpu -- --match-timeline
npm run profile:cpu -- --match-timeline --timeline-players=5 --timeline-seconds=420
npm run profile:cpu -- --match-timeline --stress --active --timeline-seconds=30
```

`--timeline-seed`, `--timeline-seconds`, `--timeline-players`, and
`--timeline-budget-ms` control the aging capture. The default wall budget is
35 seconds; the report records the actual simulated duration if it stops early.
Optional `--timeline-units` and `--timeline-structures` add a per-player workload.

Reports are written to `build/profiles/match-timeline-1p.json`,
`match-timeline-5p.json`, and `match-timeline-1p-stress.json`. They contain per-minute
mean/p95/max tick costs and the twelve worst ticks, with path callers, slow units,
component timings, entity counts and snapshot bytes. Nested component costs must
not be summed. All wall-clock instrumentation lives in `tools/profile-core.gd`;
gameplay uses no wall-clock budgets.

Regression coverage compares seeded obstacle/radius layouts against exact swept
geometry, checks gate permissions and restoration, verifies immediate nearby
Probe engagement, and exercises ordinary movement, combat, convoy and networking
behavior through the full simulation/interface suite.

## Validation

Full `npm test`, web export, and four focused browser checks passed: native/browser
admission, Lightless controls, guest movement/terminal host loss and complex mining.
`git diff --check` also passed. The current web build is staged at `/` and `/v3/`.

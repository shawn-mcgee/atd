# CPU performance

The target is less than 4 ms of CPU work for a moderately busy frame. It is **not yet achieved in active combat**. Treat individual subsystem timings as diagnostic measurements, not a claim about total frame time or browser performance.

Run the bounded benchmark from `v3/`:

```sh
npm run profile:cpu
npm run profile:cpu -- --active
npm run profile:cpu -- --active --frames --rendered
```

The fixed seed-472 fixture has 3,997 tiles, 26 structures and 103 units. Its additional 96 friendly infantry are neutral in the idle comparison. `--active` retains their configured stances, issues movement routes to one third of them and adds 12 hostile Scavengers. Each stage reports mean, p95 and maximum milliseconds with five warmup samples. Reports go to ignored `build/profiles/core-idle.json` and `core-active.json`. The wrapper exits on script errors or a 45-second timeout. `--detail` adds the slowest individual unit updates.

`simulation_step` uses 1/60-second increments for the original comparison; `simulation_tick_20hz` uses the actual project tick interval. `--frames` samples 120 calls through the real game callbacks with a 60 Hz presentation / 20 Hz simulation schedule. Those callback times exclude subsequent Canvas draw callbacks, render submission and GPU work. The separately reported engine process monitor includes rendering and can contain startup/shader-compilation spikes; it is not an isolated CPU profiler. `--rendered` opens the actual native renderer. Browser/WASM and GPU costs require separate measurement. Stage benchmarks advance the same fixture in sequence, so compare like-for-like invocations and record hardware/runtime.

The November 2026 pass removed repeated structure scans from sight obstruction, replaced overlapping floods with an exact multi-source union, bounded personal-sight caching, and reused unchanged sight unions. Topology refresh detects cliff and opaque-gate changes. Only changed illumination cells update dark-path weights. Combat acquisition reuses opposing-entity lists within each simulation tick; spawn, destruction, vehicle capture and snapshots invalidate them. Separation retains its original iteration order.

Presentation refreshes the explored terrain edge instead of scanning the whole map. Fog splat indices are precomputed and combined with packed integer pixels, retaining overlap behavior. Picking rejects whole-model bounds before individual pieces. Silhouettes cache stationary queries and use projected structure bounds before mesh tests; camera, structure and animated machinery changes invalidate the cache. Material overlays are written only when their state changes, model-part references are cached, and material lookup uses Color keys instead of formatted strings.

Navigation retains the existing hex graph when only obstacle admission changes. No gameplay systems use wall-clock budgets or presentation frame timing. All caches are derived state and excluded from snapshots. Browser diagnostic site enumeration/serialization runs only with `?test=1` or `?diagnostics=1`.

Initial idle measurements on the local desktop were approximately 103 ms per visibility refresh, 13.3 ms per terrain refresh, 16.3 ms per entity-presentation pass and 5.0 ms per pick. Following the pass these are approximately 1.0, 0.4, 2.2 and 0.1 ms respectively. Active combat and simultaneous movement/path requests remain the priority for the next pass. The rendered active fixture still showed roughly 7.9 ms mean / 17.1 ms p95 for combined game callbacks; do not interpret the idle gains as meeting the 4 ms frame target.

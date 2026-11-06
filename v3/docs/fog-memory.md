# Last-seen structures

Enemy structures remain as scouting records when their footprints leave vision.
The record freezes health, construction, power, and other observed state at the
last visibility refresh. A building created in explored fog is not revealed by
the existence of explored terrain. Seeing any occupied part of a large
footprint is sufficient to observe it.

Hidden demolition preserves the old silhouette. Revisiting any part of its
old footprint clears the record if the structure is gone. Visible destruction
clears it immediately. Owners receive current information about their own
structures. Mobile units do not leave remembered silhouettes.

Remembered models use a muted material, stop animating, and turn off their
visual work lights. Their minimap markers are gray. The inspector says **LAST
SEEN**, shows the observation's age in simulation seconds, and identifies its
health as last recorded information. Right-clicking a remembered structure
orders movement toward its old location. Explicit attacks and targeted
interactions require rediscovery; stale records are not live combat targets.

`presentation.structureMemoryTintStrength` controls the tint coverage from 0 to
1 (default 0.75). It is presentation-only and excluded from the gameplay hash.

## State and UI boundaries

- `WorldState.structure_memory` stores records per observer, separate from
  authoritative structures. Records cannot generate power, produce units,
  obstruct movement, or receive damage.
- `structure_visible`, `observed_entity`, and `observed_structures` supply
  observer-specific views. UI, models, minimap, and inspection use these views;
  simulation continues using `entity` and the real `structures` dictionary.
- `_remember_structures` captures sight before and after visibility changes,
  preserving recent damage when vision recedes. Direct tests which replace the
  sight map can call it explicitly.
- Snapshots include frozen records tagged `remembered`, `last_seen_tick`, and
  `last_seen_seconds`. Replica loading puts them in the observer's memory map,
  not in live entities or the structure collision index. Hidden current health
  and inventory are not substituted into these records.
- Network protocol 2 separates this snapshot behavior from older hosts and
  clients. Both peers must use the same configured protocol version.

Run the pinned Godot from `v3/` with
`--headless --path . --script tests/simulation.gd -- --memory-only` for focused
checks. `npm test` also covers remembered-model inspection, last-known-location
orders, and clearing models on rediscovery. The existing rendered review helper
accepts `-- --memory` and writes `build/visual-review/structure-memory.png`.

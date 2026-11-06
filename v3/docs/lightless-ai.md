# Lightless probing and combat

The current CPU produces Scavengers; the complete Womb, gland, and Father
coordinator economy remains pending. Behavior runs on simulation time in
`WorldState`, with routing and obstruction decisions in `LightlessTactics`.

| State | Behavior |
| --- | --- |
| Probe | Approach a known Anchor using dark-weighted navigation. Look for visible enemy units and structures, excluding vehicle occupants. Stop before entering an illuminated waypoint. |
| Pressure | An observed target, or the already-known Anchor beyond a blocking light perimeter, starts the resistance timer. Taking actual damage before commitment triggers retreat. An unopposed probe recruits nearby idle/probing Scavengers into an attack. Already committed attackers keep their objectives. |
| Attack | Cross illumination. Select a reachable firing position with a clear shot. A visible wall or closed Gate blocking the objective becomes the immediate target; destroying it resumes the original objective. |
| Retreat | Seek reachable, unilluminated Gloom. Ignore closer isolated patches. Retry interrupted routes, then wait for regeneration before probing again. |

Knowing Anchor locations is the CPU's existing discovery exception. The
perimeter fallback does not reveal other concealed units or structures. Normal
vision and shot obstruction still govern which intervening walls are selected.
This avoids a permanent blind spot when Anchor illumination exceeds Scavenger
vision, while retaining light avoidance before commitment.

Combat routes require a complete path. A partial path ending outside a base is
not a usable attack position. Replanning is throttled and uses deterministic
hex candidates; it does not depend on frame rate, camera state, or wall-clock
time. Human combat orders also use the shared [continuous-routing layer](navigation.md).

Tune `config/prototype.json`:

- `lightless.probeResistanceWindowSeconds`: delay before unopposed commitment.
- `lightless.probePressureSignalRangeTiles`: local recruitment radius.
- `lightless.darkPathLightPenalty`: preference for dark routes before attacking.
- `lightless.combatRepathSeconds`: retry interval for blocked/moving attack goals.
- `lightless.retreatRepathSeconds`: retry interval for interrupted retreats.
- `weapons.scavenger_bite.bonusDamageAgainstStructures`: defaults to 3, added to
  the 3-damage bite before armor. This allows 1 damage against an unshielded
  Anchor's 5 armor. Unit damage and the global zero-damage floor are unchanged.

`npm test` includes the behavioral regressions. For focused headless checks,
run the pinned Godot from `v3/` with
`--headless --path . --script tests/simulation.gd -- --ai-only`.
Coverage includes generated cliff maps, dark perimeters, wall breaching,
objective resumption, unreachable Gloom, protected passengers, and replay.

# Lightless probing and combat

The CPU now grows typed Wombs as well as producing Scavengers. Colony production
runs in `WorldState.LightlessColony`; routing and obstruction decisions remain in
`LightlessTactics`. This is a colony-production baseline, not the complete
Lightless economy or coordination system.

The colony starts with configured Chyme and receives the Medusa's passive income.
At configured decision/expansion intervals it pays for queued Mothers, reserves
Chyme, and places Womb blueprints in reachable, unoccupied Gloom using
`cpuWombPriority`. A Mother travels to the paid site, transforms, and is consumed.
Gestation raises structure health; damage delays completion. If the Mother dies
en route, the blueprint remains available for another Mother without another cost.

Completed Wombs increase the cap and unlock their corresponding type. Each Womb
passively spawns that type for free; the Medusa's free production remains
Scavenger-only. Thus Stalkers, Ravagers, Threshers, and Shades now appear through
colony development rather than being substituted into the Medusa's free timer.
The default priority grows the Scavenger Womb first, so variety develops over time.

Paid host-side queues run alongside free timers, obey the same per-type cap,
retain completed progress when capped, and resolve manual completions first by
source ID. Unstarted cancellations refund; started cancellations and source
destruction do not. Losing the last required Womb pauses a queued Medusa order
without erasing its progress. Existing over-cap units survive Womb loss. Medusa
death grants configured Chyme and permanently accelerates surviving Wombs.

Human Lightless controls/manual-spawn buttons, combat Chyme harvesting/delivery,
Glands, Father recruitment, full Gather/Defend coordination, and post-Medusa CPU
expansion remain pending. The existing unit combat/concealment/burrow rules apply
to the newly produced types; this pass does not complete their tactical AI.

## Multiplayer pressure

Combat units receive persistent player assignments, balanced separately for each unit type across surviving players. The least-served player receives the next dispatch; total dispatches across unit types break equal-count ties, followed by distance and deterministic owner ID. This also spreads small mixed-type cohorts instead of sending the first of every new type to the same closest base. Counts track dispatched units rather than surviving units, so losses at a nearby base do not pull every reinforcement away from distant players. Mothers and Fathers retain their existing support behavior.

Probes approach their assigned Anchor and evaluate that player's visible assets. Local commitment recruits only probes with the same player assignment. Attacks after Medusa death retain those assignments instead of reverting to the nearest Anchor. Retreats and wall breaching preserve the assigned player; eliminated players are excluded even when their Anchors survive disconnection. Raid assignments remain host-side and are omitted from enemy snapshots.

This balances intended pressure, not identical arrival times: travel distances, defenses, interception and terrain can still change when a raiding force reaches each base. Spawn placement is unchanged.

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

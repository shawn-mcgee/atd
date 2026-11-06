# Enemy behavior and pressure

`engine/predator_director.gd` owns pack intent, pacing, reinforcements and hive alarms. `predator_tactics.gd` owns observations, target priorities and boundary positions. `predator.gd` owns movement and immediate probe retreat. All decisions use fixed simulation time and stable actor order; presentation does not drive the AI.

## Encounters

- **Lurking:** patrol the visible, dim fringe of human illumination. A locally observed unit or structure with protective illumination below 0.15 can be hunted. Personal emergency lamps do not provide protective illumination. An ongoing hunt is not interrupted by the gathering timer.
- **Staging:** gather at reachable fringe positions, then wait briefly before acting. Packs choose probe or assault intent before gathering. Damage to a probe gathering causes withdrawal; damage to an assault gathering launches its assault early. Waiting packs never acquire an opportunistic attack that overrides their staging or retreat.
- **Probing:** one runner advances while the larger members wait at the boundary. Any damage immediately stops that runner's attack and causes the pack to withdraw, including when the runner is killed between AI updates. Four uninterrupted seconds actually threatening a target in melee range can trigger an assault after setup grace. Travel time does not count. An unsuccessful probe withdraws after 18 seconds.
- **Assault:** cross illumination and attack observed vulnerable/valuable targets. Brutes breach observed walls or closed gates blocking the approach; stalkers flank support targets before closing. Ordinary assaults eventually regroup; committed hive defense and core retrieval override these pauses.
- **Retreating:** seek dark ground, recover slowly there, and finish withdrawing before considering another target. An exposed target cannot cancel retreat.

Noncommitted movement heavily penalizes protective illumination, including probes and dark hunts. Starting an assault invalidates a previously light-avoiding route. Boundary destinations are cached briefly to avoid turning in place and refreshed when strongly illuminated or blocked.

## Species and information

Runners favor workers and perform probes. Stalkers favor generators, relays, spotlights and extractors and approach from a flank. Brutes favor defensive weapons and breach obstructing fortifications. Target scores combine strategic value, missing health and observed defensive coverage; distance breaks ties. A short target commitment prevents oscillation.

Packs share local sightings, retaining last-known positions for at most 35 seconds. They do not follow unseen actors' live coordinates. Dark hunting requires a recent sighting. Later packs can investigate the known landing site, discovering targets on arrival. Hive alarms communicate the attack location; theft broadcasts the core location.

## Pacing and hive alarms

The tunables live in `config/gameplay.json` under `predators_ai`:

| Setting | Default |
| --- | --- |
| First boundary activity | 18 seconds |
| HQ attack grace | 120 seconds, or a longer layout grace |
| Escalation to full normal pressure | 480 seconds after grace |
| Normal population limit | 16 rising to 32 |
| Extra members per late pack | 3 |
| Replacement interval | 15 seconds, falling to 8.25; 7.5 after theft |
| Hive alert radius | 55 hex tiles, inclusive |
| Hive defense alarm | 45 seconds, refreshed by damage and nearby observed intruders |
| Unresisted probe confirmation | 4 seconds |

As pressure rises, gathering falls from 10 to 4 seconds, regrouping from 24 to 6, and retreat from 12 to 6. Normal assaults can last 25 to 75 seconds. Assault preparations become more frequent: initially one in four cycles, then one in two, and finally every cycle. Exposed targets beyond the HQ grace perimeter remain vulnerable during setup.

Hive damage immediately alerts packs whose **habitat anchors** are within 55 hex steps of the hive; this is axial/cube distance rather than world-unit distance. Those packs bypass grace, preparation and retreat to defend the hive. Other packs continue normally. The hive's own guards also respond to nearby observed intruders.

Once the core has been taken, every pack permanently assaults, even after the carrier drops it. Damage, low health, preparation timers and distance cannot send these attackers back to probing or retreat. Replacement pressure continues within a 32-creature limit. Observed local targets remain attack opportunities while the core supplies a colony-wide pursuit destination.

## Validation

`test-enemy-tactics.gd` covers commitments, runner probes, first-hit withdrawal, dark routes, roles/flanking/breaching, target priorities, exact hive-radius boundaries, escalation and permanent theft aggression. `test-predators.gd` covers visibility, hunting, observation limits and safe replenishment. `test-predator-pressure.gd` runs actual early combat and checks setup safety and recurring contacts. `test-engine.gd` checks deterministic replay and late pressure.

The historical 3D checkpoint suite uses `fixtures/original_predator_director.gd` to retain its original enemy behavior; it does not constrain the new AI to the old encounter pacing.

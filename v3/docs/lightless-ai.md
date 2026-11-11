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

CPU Wombs grow armor and Chyme Glands on available adjacent Gloom. Completed
Glands require a matching adjacent Womb; they disconnect on its destruction and
can reconnect to a replacement. Surviving Mothers can continue Womb expansion
after the Medusa dies. Gather units retreat to a reachable Medusa or Stoma when
full or damaged and retain cargo if no organ is reachable. During extraction,
ordinary raiders prioritize the shortest remaining countdown and retarget after
elimination, returning to their previous assignments when extraction threats end.

After its Womb priorities, the CPU builds forward Stomas for distant Chyme
carriers. It favors the fullest carrier (stable ID breaks ties), then the nearest
reachable, unoccupied dark Gloom tile that shortens that carrier's delivery trip.
`lightless.cpuDesiredStomas` limits existing and planned Stomas (default 2; zero
disables construction). `lightless.cpuStomaMinOrganDistanceTiles` sets minimum
hex-center spacing from other Stomas and the Medusa (default 6); carriers already
within that center-to-center distance of a completed organ need no new drop-off.
Glands and initial Wombs retain priority. Stomas use the existing expansion timer,
Chyme reserve, 30-Chyme structure cost, Mother travel/transformation, and ordinary
20-second gestation. Damage delays completion. Replacement Mothers resume orphaned
blueprints without another payment; unfinished Stomas accept no deliveries.

The CPU queues a Father after completing its initial Womb goals. Fathers recruit available combat units within local range or through the global Gloom channel, apply an Attack stance, and move toward an assigned enemy Anchor. Recruits rally to their Father, while within local range or standing on any Gloom patch. Recruitment transfers check eligibility and capacity before replacing an existing assignment. Father overrides survive Medusa death and extraction; loss of recruitment restores the post-Medusa Attack stance or the current baseline network stance.

Damaged Lightless structures signal available, non-recruited combat units through the global Gloom channel. Defenders distribute across active calls, engage the known attacker within the configured defensive radius, and return to their former stance when the threat leaves or dies. A unit retains an active call after leaving Gloom. Father recruits and the post-Medusa global Attack response take priority.

Defend units group near a friendly structure, or their Father when recruited, and engage visible enemies only within the configured radius.

The Medusa stores a network stance: Attack, Defend, Gather, or Probe. Its current
stance reaches combat units on every Gloom patch, including isolated patches, new
spawns and units returning to Gloom. Units off Gloom retain their last stance and
orders. No continuous path is required, and the Medusa need not stand on Gloom. Changing stance clears obsolete combat orders; repeating the current
stance preserves them. Mothers and Fathers keep their support behavior, and Father
recruits keep their override. Releasing a recruit restores the current Medusa stance
when standing on any Gloom patch; otherwise it retains the Father's last stance.
Medusa death still forces unrecruited combat units to Attack, including units off Gloom, and subsequent recruitment release adopts Attack.

Automatic raid objectives are opposing Commonwealth Anchors. An unassigned raid
never resolves to the Lightless player's own Medusa. Probe, Attack and Gather
units retain the default CPU's enemy-Anchor navigation goals even when a human
controls the colony, so unexplored fog does not leave them idle. Planning alone
does not reveal an Anchor or allow firing on it before normal visibility permits.
Hidden autonomous targets and their coordinates are omitted from owner snapshots. Stale friendly automatic objectives
are discarded. Explicit player attack orders retain the game's friendly-fire rules.

Players can launch **Play as Lightless** from the expedition menu. In multiplayer,
the host's **Lightless** selector assigns CPU, Host, or one connected player before
launch. This uses one of the existing five participant slots. Assignment is exclusive;
the colony CPU makes no strategic decisions while a player controls it. Passive
income, spawning, gestation, Gloom, defense calls and stances still run. A departing
Lightless guest returns control to the CPU; host loss still ends the match.

Select the Medusa for network stances and paid manual spawns. Queue chips show
progress and cancel orders, refunding only unstarted work. Select an unrecruited Mother, then **Grow Womb** or **Grow Stoma** and click a
revealed site. Womb placement defaults to Scavengers, remembers the last choice,
and offers an optional type submenu without requiring a choice before placement.
Right click an abandoned blueprint with a Mother to resume it; select an unstarted
blueprint to cancel/refund it. Illumination does not interrupt Mother gestation.
Select a completed Womb for corresponding spawns and adjacent armor/Chyme Glands.
Select a Father for recruited-unit stances, **Recruit unit** targeting, and **Release
recruits**. Only unrecruited Mothers and Fathers accept direct movement or Stop.
Combat units, including recruits, do not accept move/attack/Stop/burrow orders;
players guide them through the Medusa network or a Father's position and stance.
Threshers autonomously emerge for travel/rallying and burrow when holding position.
The HUD shows Chyme, owned queues and role-specific objectives;
Lightless vision includes their units, organs and every Gloom tile globally, including
disconnected/unsupported patches. Gloom growth and loss update sight immediately;
Gloom alone does not illuminate terrain or share vision with Commonwealth players. Hidden Commonwealth
identities and colony Chyme remain filtered in network snapshots.

Solo Lightless play runs a Commonwealth AI through ordinary `WorldState` commands
and costs. It trains replacement Engineers, mines Ore and Gas, expands Ore/Gas
storage near capacity, builds/rebuilds its Armory and power support, equips Marines,
repairs its damaged Anchor, and scouts/attacks visible organs. Wounded Marines
withdraw to Anchor healing and rejoin after recovery; visible threats and extraction
keep available Marines defending home. After Medusa death, Engineers recover Nacre
and start extraction when eligible. The AI reserves the cost of an Engineer kit and
Operator before discretionary construction/personnel spending. Recovery still
requires resources: an opponent with no workers and no replacement funds cannot
recover for free. Multiplayer Commonwealth factions remain human-controlled.

`lightless.soloCommonwealthAI` configures the decision interval, desired Engineers/
Marines, attack-group size, Gas reserve, storage-expansion threshold, Anchor repair
threshold, retreat/resume health fractions, base-defense radius and regroup radius.
Retreat uses hysteresis: a Marine remains recovering until the higher resume
threshold, rather than oscillating between orders at low health.

## Multiplayer pressure

Combat units receive persistent player assignments, balanced separately for each unit type across surviving players. The least-served player receives the next dispatch; total dispatches across unit types break equal-count ties, followed by distance and deterministic owner ID. This also spreads small mixed-type cohorts instead of sending the first of every new type to the same closest base. Counts track dispatched units rather than surviving units, so losses at a nearby base do not pull every reinforcement away from distant players. Mothers and Fathers retain their existing support behavior.

Probes approach their assigned Anchor and evaluate that player's visible assets. Local commitment recruits only probes with the same player assignment. Attacks after Medusa death retain those assignments instead of reverting to the nearest Anchor. Retreats and wall breaching preserve the assigned player; eliminated players are excluded even when their Anchors survive disconnection. Raid assignments remain host-side and are omitted from enemy snapshots.

This balances intended pressure, not identical arrival times: travel distances, defenses, interception and terrain can still change when a raiding force reaches each base. Spawn placement is unchanged.

| State | Behavior |
| --- | --- |
| Probe | Approach a known Anchor using dark-weighted navigation. Look for visible enemy units and structures, excluding vehicle occupants. Approach into weapon range, including across illumination, to test a target. |
| Pressure | Actual damage to the current target starts the resistance timer; merely seeing a target does not. Taking actual damage before commitment triggers retreat. An unopposed probe recruits nearby idle/probing Scavengers into an attack. Already committed attackers keep their objectives. |
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

## Womb capacity and reconfiguration

Both free and paid production share per-type caps: configured base allowance plus
`wombPopulationIncrease` for each completed active Womb of that type. Spawn buttons
show current population/cap. Destroying capacity preserves existing units even
above cap, but blocks further spawns until there is room.

Select Change type on a completed Womb or unstarted blueprint to open the same
seven-type submenu used by placement. A completed Womb cannot remove its old type's
capacity below the living population and requires its own manual queue to be empty.
Unstarted blueprints change immediately; gestating Wombs cannot change type.
`lightless.wombReconfigureSeconds` defaults to 5. During this cooldown the Womb
provides neither old nor new capacity, unlocks, spawning or Gland support. Passive
spawn progress resets. Existing Medusa orders pause if their unlock is lost and keep
their paid progress. Glands retain their type, disconnect from mismatched or
reconfiguring Wombs, and reconnect when an adjacent active matching Womb exists.
`controls.wombHotkeys` supplies contextual submenu shortcuts. The interface remembers
the last chosen type for subsequent placements, matching Depot behavior.

Gloom communication is receiver-based: a Father can recruit a distant unit on any
Gloom tile even while the Father is off Gloom. Local recruitment still works off
Gloom. Losing a bridge between patches never drops a recruit; leaving Gloom beyond
local range does. Father overrides and atomic transfer/capacity checks remain.
Defense calls also reach available units on any Gloom patch. This global messaging
rule does not change frontier-based growth, illumination damage or withering.

## Father roster and CPU recovery

A selected Father displays recruited units, health percentages and current count/
limit. Click a roster card to release that unit; Release recruits still releases
all. Recruitment targeting identifies the current Father so transfers are explicit;
a full destination roster leaves the previous assignment intact. Targeted release
validates that the selected Father owns that recruit.

CPU Fathers synchronize their recruits to the same opposing Anchor, including
ordinary extraction priority. Wounded Fathers switch their existing recruits to
Gather and return toward the Medusa, restoring Attack after healing. Configure the
health hysteresis with `cpuFatherRetreatHealthFraction` (0.35) and
`cpuFatherResumeHealthFraction` (0.85). This never replaces player colony orders.

After establishing its initial Womb types, the CPU adds capacity when population
reaches `cpuWombCapacityPressure` (0.8) of the shared type cap, bounded by
`cpuAdditionalWombsPerType` (2). Blueprint payment, Mother travel/transformation,
placement restrictions, expansion intervals and Chyme reserves still apply.
Recursive attacks remain deferred.

## Thresher movement and bounded navigation

Automatic Thresher deployment uses tentacle range and line of sight. It preserves
combat objectives through deployment/emergence, stops an obsolete melee route
when a valid firing position is reached, and emerges to reposition around blocked
shots or follow a distant Father. Probe/Gather use the current buried/surface
weapon consistently; buried units never search for walking routes.

Failed Probe movement retries use `combatRepathSeconds` rather than every tick.
Attack-position and retreat searches issue at most `maxPathQueriesPerDecision`
(default 4) full A* queries per decision. Cursors continue through remaining
candidates on subsequent decisions, so failed nearby candidates do not starve
reachable alternatives. Search metadata remains host-only in filtered snapshots.
The regression fixture records four path requests over 100 blocked Probe ticks,
checks both query budgets and obstruction recovery, and verifies ranged firing
while buried. This is a bounded simulation result, not a browser frame-time claim.

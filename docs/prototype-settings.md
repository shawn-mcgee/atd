# Prototype settings

[prototype.json](../config/prototype.json) is the editable browser-alpha tuning specification. The Godot foundation loads it at startup and implements a subset of its systems. Definitions for pending systems remain design data; see [implementation status](implementation-status.md) before assuming a configured feature is playable.

Values repeat confirmed rules where available. All other numbers are proposed initial tuning choices made to give the first implementation a complete starting point; they require playtesting. The README defines confirmed mechanics, and the first-playable and expedition documents explicitly identify implementation choices.

Use [the generated configuration reference](config-reference.md) to search every configured default by JSON path. `npm run config:check` runs native validation; `npm run config:reference` regenerates the index. See [the developer guide](developer-guide.md) for rule ownership and extension points.

## Editing contract

- Edit the JSON, not source-code literals. Gameplay implementations must load these definitions and reject invalid settings before starting a match. The loader validates the implemented configuration contracts; coverage and limits are documented in the developer guide. It does not fill missing gameplay values silently.
- Time is simulation seconds, distance is tile inner diameters, and resource counts/costs/capacities/recipe amounts are whole numbers. Damage and health rates may be fractional.
- All participants in multiplayer must use the same resolved simulation settings and map seed. Exclude `camera` and local input preferences from that simulation hash. Freeze gameplay balance at match start; camera preferences remain local and single-player speed can change during the match. Changing balance requires a new match.
- Simulate at `match.simulationTicksPerSecond` fixed steps. Scale elapsed real time by speed; do not change damage-per-tick merely because the display frame rate changes.
- Flame intervals are one simulation step in this preset. If simulation frequency changes, update flame intervals and per-hit damage together to preserve the intended damage per second.
- Ranges must be nonnegative; seconds, health, and active intervals must be positive. Resource quantities, armor bonuses, capacities, slots, population limits, and power quantities must be nonnegative integers.
- Costs of `null` on the starting Anchor and Medusa indicate no build/purchase recipe. One Anchor per player and one Medusa per mission are already present at deployment. An eliminated player cannot rebuild.
- Every weapon, production source, unit type, and upgrade target must reference a defined identifier. An infinite Nacre deposit is a rule, not a JSON infinity value.
- A recipe must fit its output buffer as a whole batch. Input deduction and output reservation are atomic, so two facilities cannot spend the same global inventory.
- Startup loading, a gameplay-settings compatibility hash, and foundational configuration checks exist. Full schema validation, a balance settings UI, and hot reload are not implemented.

## Confirmed values preserved

Five Commonwealth players maximum; one Anchor per player; 100 starting Ore and Gas; Anchor capacities 100 Ore, 100 Gas, 10 Alloy, 10 Polymer, 10 Crystal, and 1,000 Nacre; extraction at 500 Nacre for 90 seconds; five starting Scavengers and 100 Chyme; a starting Father for the testing player; five kits per structure including completed kits; one cargo space per resource unit; six adjacent Glands per Womb; seating counts; and the 120% overload threshold are established rules. Infantry/worker vision of two tiles and the six-tile edge inset are initial values for previously approximate ranges.

## Core defaults

| Setting group | Initial choice | Purpose |
| --- | --- | --- |
| Simulation | 20 steps/second; speed 1 | Deterministic simulation-time basis. |
| Map | Hex radius 36; inset 6 | Room for five corner starts and a central nest. |
| Deposits | 10,000 units per Ore/Gas patch | Finite, rich sources. |
| Extra fields | 6 Ore and 4 Gas fields per player | Additional contested deposits beyond starting fields. |
| Depot | +200 capacity of selected resource; 5-second reconfiguration | Early storage expansion is inexpensive and explicit. |
| Worker cargo | Operator and Engineer: 20 | Engineer advantage is throughput, not carrying capacity. |
| Work cycles | Operator 1, Engineer 2 items per second | Applies to direct mining and buffer collection. |
| Ranger / Excavator cargo | 100 / 250 | Moderate haul vehicle versus large industrial carrier. |
| Anchor power | 2 | Enough for a 1-power Floodlight and 1-power Sentry. |
| Generator / Reactor | 6 / 20 capacity | Higher-generation tiers without introducing another resource. |
| Generator fuel | 1 Gas per 10 seconds | Whole-number deduction funds a finite running interval. |
| Reactor fuel | 1 Crystal per 20 seconds | Same mechanism as the Generator. |
| Build / repair work | 20 / 10 health per Engineer-second | Additional Engineers add linearly. Repair costs 1 Ore per second. |
| New construction | 1 health | Configurable starting health, as requested. |
| Father | 12 recruits; local range 6 | Limits each coordinated group. |
| Gloom | 20 health; illumination damage 10/second | A lit tile clears in 2 seconds under this preset. |
| Unsupported Gloom | Withers at 1 health/second | A fresh unsupported tile lasts up to 20 seconds without light. |
| Medusa income | 1 Chyme/second | Supports development even before combat. |
| Chyme Gland income | 1 Chyme/3 seconds | Incremental income through Womb slots. |
| Medusa death | +500 Chyme; Womb production rate x2 | Initial magnitude for the confirmed escalation. |
| Minimum damage | Clamp at zero | A configurable prototype choice; the design question remains open. |
| Unit separation | Maximum 1.2 tiles/second | A local overlap correction, applied against collision radii without moving into blocked cells. |
| Move formation spacing | 0.55 tiles | Separates destinations for basic group movement. |
| Dark-route penalty | Illuminated tiles cost x40 | Encourages non-attacking Lightless to take longer dark routes. Probes stop at light until committing to an attack. |

## Human units and vehicles

All human infantry and workers have vision 2 and illumination 0. Vehicle ranges below apply only with a driver. Vehicle light/vision cones follow heading and remain blocked by cliffs, Walls, and closed Gates. Ranges are radial unless the forward value is specified.

| Unit | Health | Armor | Speed | Cargo | Vision | Light | Forward light | Cost of vehicle only |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| operator | 60 | 0 | 1.8 | 20 | 2 | 0 | 0 | n/a |
| engineer | 80 | 0 | 1.8 | 20 | 2 | 0 | 0 | n/a |
| marine | 100 | 1 | 1.8 | 0 | 2 | 0 | 0 | n/a |
| flamer | 130 | 2 | 1.6 | 0 | 2 | 0 | 0 | n/a |
| lancer | 100 | 1 | 1.5 | 0 | 2 | 0 | 0 | n/a |
| scout | 200 | 2 | 3.6 | 0 | 4 | 2 | 5 | 40 ore, 10 alloy |
| ranger | 350 | 3 | 2.6 | 100 | 4 | 2 | 4 | 60 ore, 15 alloy, 10 polymer |
| excavator | 650 | 5 | 1.2 | 250 | 5 | 3 | 0 | 80 ore, 25 alloy, 10 polymer |
| reaper | 550 | 5 | 1.4 | 0 | 5 | 3 | 0 | 40 alloy, 15 polymer |
| cremator | 650 | 6 | 1.2 | 0 | 5 | 3 | 0 | 40 alloy, 25 polymer |
| javelin | 450 | 4 | 1.2 | 0 | 5 | 3 | 0 | 50 alloy, 20 crystal |

Unit collision radii are 0.15 tiles for people and small Lightless, and 0.35 for vehicles, Ravagers, and Threshers. Structure collision is the union of its footprint hexes, with Gate state controlling its obstruction. These values and shape identifiers are editable.

Speeds are tiles/second. Vehicle forward cones are 90 degrees. Forward vision extends two tiles beyond forward light. Work from structure footprints uses distance beyond the occupied footprint; unit ranges use collision-surface distance. Operators cost 10 Ore and 5 Gas, take 12 seconds at an Anchor or 6 at a Cradle. Specializations add their kit cost to that existing person; automatic personnel requests add the Operator price once.

## Kits and Fabricator upgrades

| Kit | Cost | Assembly seconds | Sources |
| --- | --- | ---: | --- |
| engineer | 10 ore, 5 gas | 8 | anchor, cradle |
| marine | 10 ore, 5 gas | 8 | armory |
| flamer | 10 ore, 5 polymer | 12 | armory |
| lancer | 5 alloy, 5 crystal | 15 | armory |

An Engineer, Marine, Flamer, and Lancer each have one independently purchasable Fabricator armor upgrade. Each costs **10 Alloy and 5 Polymer**, takes **20 Engineer-seconds**, and adds **1 armor** to all current and future instances of that specialization for the rest of the match. Upgrades cannot be repurchased. Multiple Engineers add their work rates linearly. Operator and vehicle armor upgrades are not included.

Upgrade Glands initially offer the already discussed armor effect: **+1 armor per active Gland**, capped at **three constructed copies colony-wide per unit type**. Disabled surviving Glands still count toward this construction cap; destroying one frees its slot. Each Gland costs **40 Chyme**. Chyme Glands cost **50 Chyme**, have no colony-wide count cap, and share their Womb's six physical slots. Other effects remain undesigned.

## Weapons

| Weapon | Damage per hit | Interval seconds | Range | Mechanism |
| --- | ---: | ---: | ---: | --- |
| marine_rifle | 8 | 0.25 | 4 | unit_target |
| reaper_gun | 14 | 0.15 | 5 | unit_target |
| sentry_gun | 10 | 0.2 | 5 | unit_target |
| flamer_flame | 1 | 0.05 | 2 | cone |
| cremator_flame | 2 | 0.05 | 3 | cone |
| torch_flame | 2 | 0.05 | 3 | cone |
| lancer_laser | 100 | 3 | 6 | unit_target |
| javelin_laser | 180 | 3.5 | 7 | unit_target |
| lance_laser | 160 | 3 | 7 | unit_target |
| scavenger_bite | 3 | 0.75 | 0.75 | unit_target |
| stalker_claw | 12 | 0.75 | 0.75 | unit_target |
| ravager_melee | 20 | 1.5 | 1 | unit_target |
| thresher_melee | 15 | 1 | 0.75 | unit_target |
| thresher_tentacle | 20 | 1.5 | 4 | unit_target |
| shade_attack | 12 | 2 | 10 | unit_target |

Flame weapons apply one hit per 0.05-second simulation tick. Armor is applied per hit, so armored targets can completely resist weak flames in the zero-floor preset. The Ravager adds **60 damage against structures before armor**. Current lasers and other unit-target weapons hit one eligible target; geometry variants are not being reintroduced. Biological workers have no weapon in this preset. Friendly targets require an explicit attack order except where a defined area effect permits incidental friendly fire.

## Structure defaults

A footprint radius of 0 is one hex; radius 1 is a seven-hex cluster. Glands remain single-hex to fit each of the Womb's six adjacent sites. The Womb itself is single-hex. All consuming electrical footprints match build footprints unless an extension is listed.

| Structure | Health | Armor | Cost | Footprint radius | Power draw | Capacity | Electrical extension | Light extension | Vision extension |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| anchor | 2000 | 5 | n/a | 1 | 0 | 2 | 3 | 3 | 5 |
| wall | 600 | 3 | 5 ore | 0 | 0 | 0 | 0 | 0 | 0 |
| gate | 600 | 3 | 10 ore | 0 | 0 | 0 | 0 | 0 | 0 |
| depot | 400 | 1 | 20 ore | 0 | 0 | 0 | 0 | 0 | 1 |
| cradle | 600 | 2 | 40 ore, 20 gas | 0 | 1 | 0 | 0 | 0 | 1 |
| armory | 600 | 2 | 50 ore, 20 gas | 0 | 1 | 0 | 0 | 0 | 1 |
| factory | 900 | 3 | 70 ore, 20 alloy, 10 polymer | 1 | 4 | 0 | 0 | 0 | 1 |
| generator | 400 | 2 | 40 ore, 20 gas | 0 | 0 | 6 | 3 | 0 | 1 |
| reactor | 600 | 3 | 30 alloy, 10 polymer, 10 crystal | 0 | 0 | 20 | 3 | 0 | 1 |
| relay | 250 | 1 | 10 ore, 5 gas | 0 | 1 | 0 | 8 | 0 | 1 |
| floodlight | 200 | 1 | 15 ore, 5 gas | 0 | 1 | 0 | 0 | 6 | 8 |
| extractor | 500 | 2 | 30 ore, 10 gas | 0 | 2 | 0 | 0 | 0 | 1 |
| sentry | 400 | 2 | 20 ore, 10 gas | 0 | 1 | 0 | 0 | 0 | 2 |
| torch | 450 | 2 | 30 ore, 5 polymer | 0 | 2 | 0 | 0 | 0 | 2 |
| lance | 450 | 2 | 20 alloy, 10 crystal | 0 | 3 | 0 | 0 | 0 | 2 |
| foundry | 500 | 2 | 40 ore, 20 gas | 0 | 2 | 0 | 0 | 0 | 1 |
| refinery | 500 | 2 | 40 ore, 20 gas | 0 | 2 | 0 | 0 | 0 | 1 |
| synthesizer | 600 | 2 | 50 ore, 10 alloy, 10 polymer | 0 | 3 | 0 | 0 | 0 | 1 |
| rampart | 600 | 3 | 20 alloy, 10 polymer, 10 crystal | 0 | 3 | 0 | 0 | 0 | 2 |
| radar | 350 | 1 | 30 ore, 10 alloy | 0 | 2 | 0 | 0 | 0 | 2 |
| fabricator | 650 | 2 | 50 ore, 10 alloy, 10 polymer | 0 | 2 | 0 | 0 | 0 | 1 |
| medusa | 3000 | 5 | n/a | 1 | 0 | 0 | 0 | 0 | 8 |
| stoma | 300 | 1 | 30 chyme | 0 | 0 | 0 | 0 | 0 | 3 |
| womb | 600 | 2 | 60 chyme | 0 | 0 | 0 | 0 | 0 | 4 |
| gland | 200 | 0 | 40 chyme | 0 | 0 | 0 | 0 | 0 | 2 |
| chyme_gland | 200 | 0 | 50 chyme | 0 | 0 | 0 | 0 | 0 | 2 |

Production buildings draw only while working. Relays, Floodlights, Radar, Ramparts, and enabled defenses draw continuously while functioning. Radar detection extends 12 tiles beyond its footprint; Scout detection is 8 tiles. Ramparts add 3 armor within four tiles beyond their footprint, do not stack, and protect themselves and other structures. Armor drops immediately when the provider loses power. These coverage choices are prototype defaults.

## Lightless population and production

| Type | Health | Armor | Chyme cargo | Base cap | Added cap/Womb | Manual Chyme | Manual seconds | Womb passive seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scavenger | 30 | 0 | 10 | 20 | 20 | 5 | 4 | 10 |
| stalker | 90 | 1 | 20 | 0 | 12 | 20 | 8 | 14 |
| ravager | 650 | 6 | 60 | 0 | 6 | 80 | 20 | 30 |
| thresher | 250 | 3 | 30 | 0 | 8 | 60 | 16 | 24 |
| shade | 90 | 0 | 25 | 0 | 8 | 50 | 15 | 22 |
| mother | 120 | 0 | 0 | 4 | 4 | 25 | 12 | 20 |
| father | 200 | 1 | 0 | 2 | 2 | 60 | 20 | 30 |

The Medusa passively produces one Scavenger per 8 seconds. Wombs only passively produce their corresponding type. Manual queues hold 10 orders; one manual order is worked per structure alongside its independent passive slot. At the population cap, both slots can reach 100% and wait; ready manual orders have priority.

Lightless structures take **20 seconds** to gestate undamaged; Glands take **12 seconds**. Passive construction adds `(maximum health - starting health) / gestation seconds` health per second. Damage removes progress and extends completion; regeneration never adds a second source of gestation progress. Completed structures and units on Gloom heal at **2 health/second**, with no damage delay in the preset.

## Recipes and buffers

| Facility | Whole-number recipe | Seconds/batch | Output buffer |
| --- | --- | ---: | ---: |
| Extractor | 4 units of its source | 1 | 50 |
| Foundry | 4 Ore to 2 Alloy | 4 | 20 |
| Refinery | 4 Gas to 2 Polymer | 4 | 20 |
| Synthesizer | 4 Ore + 4 Gas to 1 Crystal | 6 | 20 |

Buffers hold only their defined output resource. A new batch starts only when inputs and space for its entire output are available. Direct mining uses worker cycles, so extraction machinery is faster without removing the direct-mining fallback. A depleted source yields only its remaining whole units. Clearing a cliff produces 20 Ore into the Excavator, up to its available capacity; excess is lost.

## Power and boundary cases

Evaluate normal operation first: demand at or below capacity is normal, even where rounding 120% yields the same integer as capacity. Above capacity, demand below `floor(1.2 * capacity)` is brownout; demand at or above that threshold is blackout. A zero-capacity grid cannot supply consumers. A latched blackout clears only at demand at or below capacity.

Blackout retains its connection graph and requested demand for recovery checks. Switching off a Relay or physically severing it still removes its footprint; a blackout alone must not repeatedly detach/reconnect consumers and oscillate. After topology changes, recompute capacity and requested demand, then evaluate the latch. An isolated Relay without a producing source provides no useful power.

Brownouts use fixed multipliers: illumination range x0.75, resource and other production rates x0.5, turret targeting time and attack intervals x2. Round flood-fill ranges down. A Generator or Reactor pays one whole fuel unit to run its configured interval; fuel already paid for is not refunded on shutdown. Enabled sources consume fuel while available, including at idle demand. No startup resource or delay is added.

## Validation before implementation acceptance

Check JSON parsing, positive timings, integer inventories, reference integrity, batch/buffer compatibility, zero illumination for infantry/workers, passenger counts, starting supply within capacity, one-Anchor limit, five-kit accounting, and boss disabled. Validate economic reachability: a Depot costs only Ore; Foundry and Refinery need only raw resources; advanced material requirements can therefore be reached from direct mining and the starting stockpile. Multiplayer must reject mismatched resolved settings before simulation starts.

These checks validate the design data, not play balance, pathfinding, AI quality, networking, or runtime behavior. Those require the actual game.

## Local camera settings

The `camera` object supplies a perspective RTS view modeled on the requested StarCraft II style. It is local presentation data rather than synchronized simulation state. Numeric defaults are project-specific proposals.

Initial pitch is 55 degrees down, vertical field of view 40 degrees, and focus distance 24 tiles, clamped between 12 and 32. Wheel steps change distance by 2 tiles. Default panning is 18 tiles per real-time second, scaled by zoom; edge scrolling uses a 12-logical-pixel band. Zoom and temporary rotation response times are 0.12 seconds.

Arrow-key panning, middle-button dragging, edge scrolling, and wheel zoom are all enabled. Insert/Delete hold temporary 90-degree left/right rotation and return on release; pitch and roll are not freely controlled. Rebindable actions, focus handling, hex-map bounds, paused navigation, and UI input capture are specified in [the engine plan](engine-and-distribution.md).

The future configuration loader must validate `minimumDistanceTiles <= defaultDistanceTiles <= maximumDistanceTiles`, a perspective field of view between 0 and 180 degrees, positive distances and response times, and a nonnegative edge band. Camera updates use real-time presentation delta rather than simulation ticks or game-speed scaling.

## Browser alpha and connectivity

The local `presentation` group controls damage numbers, sound enablement and levels, visual motion interpolation, and the particle budget. These values affect presentation only and are excluded from the gameplay compatibility hash alongside camera preferences. See [art direction](art-direction.md) for the visual targets and asset sources.

The alpha uses Godot's browser export with Trystero/WebRTC player-hosted multiplayer. `features.nativeDesktopExports` is false; native Windows/Linux exports and desktop interoperability are deferred. Gameplay tuning is otherwise unchanged by the platform scope decision.

[networking.json](../config/networking.json) holds separate connectivity choices: Trystero 0.26.0, application namespace, Nostr signaling, ICE/TURN configuration, and disconnection policies. The host-authoritative foundation uses this configuration. TURN servers are currently empty; different-network coverage remains to be validated.

Match compatibility checks include protocol/build and resolved gameplay settings. Local camera preferences are excluded. Connectivity endpoints and local transport settings are not gameplay balance, though peers must use compatible room discovery settings. The adapter and early cross-site checks are specified in [Browser alpha networking](networking.md).

Host loss is configured as `end_match`; host migration and recovery are disabled. Non-host disconnection is `eliminate_keep_assets_and_orders`: eliminate the player, retain asset orders and stances, and unload vehicle occupants.

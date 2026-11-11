# Implementation status

## Current milestone: runnable foundation

The repository now contains a Godot **4.7.2** project and a single-threaded browser export, with Godot **WebRTCMultiplayerPeer**, the custom coordinator and Metered TURN. The native Windows/Linux x86_64 editor/runtime also supports networking. This is the first implementation milestone, not the completed alpha described in the design documents.

The current art pass combines procedural industrial models, basic procedural animation, a generated ground material and title illustration, a revised command interface, and original synthesized sound. Models and audio still need production refinement. See [art direction and asset provenance](art-direction.md).

## Current completion pass

Multiplayer now defers snapshot compression until transmission, shares compressed
broadcast payloads, and coalesces received guest snapshots to one application per
presentation frame. Commands and packet formats are unchanged. A measured route-
copy candidate was slower and was excluded from production.

Thresher navigation now throttles failed Probe routes, bounds attack-position and
retreat A* queries, preserves objectives through automatic transitions, uses the
buried tentacle for Probe/Gather, and emerges to clear obstructed shots. Search
cursors stay out of client snapshots. Regression coverage includes query counts
and actual movement after emergence.

Father selection now includes a health/count roster with individual authoritative
release and assignment-aware recruitment targeting. Commonwealth solo AI now
maintains Engineers, Ore/Gas gathering, storage expansion, Armory/power rebuilding,
Anchor repairs, wounded-Marine recovery and home/extraction defense. CPU Fathers
recall wounded cohorts and synchronize their opposing Anchor; capacity pressure
can trigger additional typed Wombs within configurable limits.

Remaining Lightless combat units and organs have distinct procedural silhouettes,
SVG icons and matching portrait glyphs. Move orders retain blocked destinations
and retry; convoy vehicle loss clears obsolete seat reservations while survivors
continue on foot. Competing extraction completions in one tick now select the
earlier timer, with player-slot ordering for exact ties. Recursive attacks and the
Nacre wallet remain deferred. Internet multiplayer acceptance and gameplay balance
still require real-player sessions; local checks do not establish those outcomes.

## Single-player interaction pass

Gloom communication is now global rather than component-connected. Any unit on any Gloom patch receives the Medusa stance or can be remotely recruited by a Father, even when the sender is off Gloom. Local off-Gloom recruitment, Father overrides, retained off-Gloom stances and post-Medusa Attack priority remain. Structure defense calls also use the global channel. Connected-component calculation/caching was removed; growth still spreads through adjacent frontier tiles.

Global Lightless Gloom sight explicitly includes disconnected and unsupported patches, independently of unit/organ range or the Medusa network. Growth/removal refresh sight immediately, and losing sight preserves explored terrain without retaining enemy-unit visibility. Gloom sight maps store boolean visibility rather than Gloom health values.

Player-controlled Lightless now retain the normal autonomous Probe/Attack/Gather navigation goals. These units no longer wait indefinitely for the human to scout an enemy Anchor first. Enemy visibility and firing eligibility remain filtered, hidden goals are scrubbed from owner snapshots, and the own-Medusa targeting guard remains in place. Human control still replaces colony strategy rather than individual unit behavior.

Lightless combat units now reject individual move, attack, Stop, burrow and self-release orders at the simulation boundary. Only unrecruited Mothers and Fathers accept direct movement/Stop; Fathers release recruits. Typed Womb placement uses an optional submenu, defaults to Scavengers and remembers the last choice. Spawn badges show shared population/cap. Wombs can change type before gestation, or reconfigure after completion with queue checks, population-safe capacity removal, a five-second cooldown, reset passive progress and preserved typed Glands. See [Lightless controls](controls.md#lightless).

The Mother now appears as a large-headed, hunched shambler with sunken eyes, a slack jaw, long arms and splayed feet. Its asymmetric gait adds a dragging leg, shoulder sway and head lag; the portrait and command icon match. Motion is configurable under `presentation.motherMotion` and freezes while paused. Native captures of two walking phases, simulation/interface tests, web export, and the focused browser Lightless-controls check passed. See [art direction](art-direction.md#mother-shambler).

The Father now has a distinct floating squid silhouette: a plated mantle, fins, glowing eyes, eight trailing tentacles, hover/lean motion, and staggered arm animation. Its portrait and command icon match the new model. Motion tuning lives under `presentation.fatherMotion`; see [art direction](art-direction.md#father-silhouette). Native visual captures at two animation phases, the simulation/interface suite, web export, and the focused browser Lightless-controls check passed.

Lightless are now player-controllable: the solo expedition menu adds Play as Lightless with a Commonwealth AI opponent, and the multiplayer host can assign one existing player slot to the colony. Medusa/Womb spawning and queue cancellation, Mother organ placement, Glands, network/Father stances, recruitment/release, direct movement/Stop for unrecruited Mothers/Fathers have real command-panel controls. Combat units follow network/Father stances and Threshers transition autonomously. Unassigned colonies retain the CPU; a departing Lightless guest returns the colony to it. See [controls](controls.md#lightless) and [Lightless AI](lightless-ai.md).

The CPU now grows forward Stomas after its initial Womb priorities, choosing reachable Gloom sites that shorten distant Chyme carriers' delivery trips. Existing and planned organs enforce configurable count/spacing limits, with normal reserve checks, paid blueprints, Mother transformation, damage-delayed gestation, and replacement-Mother recovery. See [Lightless AI](lightless-ai.md).

Medusa network stances now propagate Attack, Defend, Gather, and Probe to combat units standing anywhere on Gloom. Returning to Gloom and new spawns adopt the current stance; leaving Gloom retains existing stance/orders. Father recruits keep their overrides, release on Gloom restores the global Medusa stance, and Medusa death retains global Attack priority. The validated `WorldState.command(-1, {"action": "medusa_stance", "target": medusa_id, "stance": "defend"})` entry point is available for host-side testing; the Medusa interface now exposes these commands. See [Lightless AI](lightless-ai.md).

Multiplayer CPU raiders now balance dispatches by unit type across surviving players, retain their assignments through probing and post-Medusa attacks, and recruit only within the assigned group. This prevents the nearest spawn from drawing the entire colony. Travel times and terrain remain meaningful. See [Lightless AI](lightless-ai.md).

Selection now uses icon-led task cards, progress and health/cargo meters, specific amber waiting reasons, and resource-by-resource cargo chips. Groups summarize tasks, blocked counts and mixed cargo. World task icons and pulsing known-target markers connect a selected worker to its blocker. Detailed stats and guidance remain available on hover; repeated inspector paragraphs and objective instructions are no longer permanently displayed. Status queries do not mutate the simulation, and owning clients receive authoritative activity data because host routes are omitted from snapshots.

The viewport now expands to the window aspect ratio without side letterboxing. Edge-pan bands are 32 logical pixels, with pulsing directional double arrows drawn above the HUD. HUD hover no longer shrinks the edge bands; minimap interaction and captured drags retain priority.

Three always-available single-player missions now group mining/construction/power, industry/hauling/personnel, and combat/recovery/extraction. Each uses seeded setup, live objectives and ordinary commands, with no unlock requirement. The first two are peaceful; the compact extraction scenario has a small central nest and timed extraction assaults. See [mission controls and tuning](missions.md). Ordinary expeditions retain standard rules.

Construction no longer cancels paid sites when routes become blocked, enemies occupy a footprint, or passing traffic crosses a site. Unstarted sites wait; active traffic retains its orders; idle friendly bodies are asked to move. Engineers retry interrupted approaches. Stop leaves the site intact, and explicit cancellation still refunds only before actual work starts. Combat destruction continues to lose the investment.

Explored fog terrain, resource silhouettes and remembered structures are brighter, with reduced smoke opacity and stronger ambient/key lighting. Unknown terrain stays opaque and enemy visibility rules are unchanged. Switching between mission and standard map sizes reallocates the visibility texture correctly.

The [multiplayer provider research](multiplayer-options.md) is historical. Networking now uses the custom Cloudflare coordinator and Metered TURN from multiplayer-experiment through Godot WebRTCMultiplayerPeer, including native Windows/Linux x86_64 runtime support. See [networking](networking.md).

The Medusa now reserves one seeded random inset corner, with players placed at separate corners. Its starting Scavengers, bounded Gloom and guaranteed approach routes follow that nest. The nest stays hidden until scouted. Death creates Nacre at the actual Medusa cell; explored-cell snapshots synchronize the resource type without disclosing an undiscovered corpse location.

Idle Engineers seek reachable friendly construction within a configurable six-tile footprint search radius, then repair nearby structures with the ordinary Ore charge. Checks run every half second while idle; player jobs and queued orders take priority. Walls support a full-line drag preview, budget-aware partial placement, and Shift queue/repeat through an authoritative `build_line` command. Models are full-tile hexagonal prisms. Construction checks cover payment, interruptions, ownership and unreachable sites; the native `--walls` fixture checks real pointer dragging and captures the preview.

The CPU pass batches overlapping sight propagation, caches unchanged visibility, indexes sight obstruction, updates only affected terrain/dark-path weights, retains navigation graph topology, and reduces mesh picking, silhouette and material work. Production sessions skip test diagnostics. A bounded benchmark and its limits are documented in [CPU performance](performance.md); the sub-4-ms target remains unmet in active combat.

Terrain presentation now includes fragmented stratified basalt cliffs, sparse instanced scree, gravel surface normals, eroded gas vents with visible-only vapor, soft contact shadows, and warm service-light spill from operating facilities. These do not change collision, resource supply, vision, or simulation illumination.

Fog of war has an animated black smoke fringe with curled tendrils and a translucent veil over remembered terrain. Current-vision interiors stay clear, and deep unexplored space remains black. This is a configurable presentation shader; simulation visibility and concealment are unchanged.

Routes now start from each unit's actual position and simplify clear terrain into straight segments. Repeated orders no longer route through the current tile center. Movement preserves valid off-grid endpoints, spends the whole tick budget across waypoints, and checks swept body clearance against obstacles and gates. Larger vehicles use clearance-aware graph edges; non-attacking Lightless retain dark detours. See [navigation behavior and tuning](navigation.md).

Scavenger probes now commit across an unopposed light perimeter using the CPU's existing knowledge of Anchor locations. Committed attackers engage visible blocking walls and resume their original objective after breaching them. Attack positions and retreat destinations require complete paths; interrupted retreats retry reachable Gloom. A configurable structure bonus lets basic Scavenger bites chip unshielded Anchors. See [Lightless behavior and tuning](lightless-ai.md).

The scene now includes distinct infantry and structure silhouettes, continuous textured ground, fractured cliffs, filtered fog edges, warm work lights, walking/work/recoil motion, impact effects, a clickable fog-aware tactical map, mission stages, health/cargo bars, route lines, command markers, construction previews, production progress, grid load, and an end-of-mission panel. The command deck uses bundled typography, resource readouts, and technical portraits. Damage numbers are optional and off by default. Selection, orders, combat, mining, and completion have audio cues, with a sound toggle and ambient drone.

Engineers repair completed structures and vehicles using Ore over time. The Anchor heals nearby biological units. Right-clicking an Anchor or Depot with loaded carriers redirects their delivery; full storage retains the remaining cargo. **X** stops selected units without discarding cargo, and **Home** centers the camera on the Anchor. Defensive units enforce their home leash, concealed targets stop receiving new shots, and a spatial separation pass reduces unit overlap.

Scavengers now begin by probing rather than immediately attacking the Anchor. Uncommitted probes favor dark routes and retreat to Gloom when damaged; an unopposed probe can commit nearby Scavengers after the configured resistance window. This is an initial implementation of probing, not the full Lightless strategy or economy. Gloom grows through connected dark frontier tiles, takes illumination damage, and withers after losing structure support. Biological Lightless on Gloom and completed Lightless structures regenerate.

## Command interface and mechanics

Relay previews and selected-Relay coverage now explicitly include zero-demand grid participants at both ends of links. They show neighboring electrical footprints, candidate endpoint rings, link counts and off-state potential links. Selected Relays expose Switch off/on; switching recomputes downstream supply and visibility immediately without advancing paused simulation.

The minimap supports captured left-drag camera movement, right-click context commands and armed-order targeting. Shift appends bounded per-unit orders, including paid-immediately blueprint work; replacement orders and Stop clear pending plans. Owned plans survive snapshots and display queued waypoints. Visible units occluded by structures receive silhouettes without exposing concealed units. Targeting modes have distinct cursors, stance controls refresh after accepted changes, and contextual shortcuts cover stances, personnel, kits, vehicles and Depot resources. Automatic Operator requests now use one player-wide setting, including future facilities. Depot placement defaults to Ore, remembers the last type and offers optional resource buttons rather than a mandatory dropdown.

Commonwealth facilities now have distinct industrial silhouettes, an open Factory assembly bay, visible kit cases and queued personnel capsules, warm operating lamps, production machinery/process windows, and power/fuel warning indicators. Cold ambient lighting, darker terrain and weathered metal strengthen the night-time industrial setting. These presentation changes read existing simulation state; queue props are owner-only and do not reveal hidden production. See [art direction and visual review captures](art-direction.md).

Clicks now hit the bounds of visible model parts, including raised geometry and the outer parts of large structures. The nearest intersected model takes priority; small entities retain the existing center-click tolerance. Hidden models and hidden parts do not participate, and remembered structures remain selectable using their displayed models.

The command interface now separates inspection, queues, and actions. It uses textured metal panels, original SVG command icons, visible resource costs, full unit combat/cargo stats, structure power and recipe details, and click-to-select role subgroups. Deposits can be selected to inspect remaining supply. Queue chips show progress or readiness and expose cancellation/refund rules in their tooltips. Controls update affordability without rebuilding open personnel menus.

New mechanics in this pass: completed Depot reconfiguration removes old capacity immediately and adds the new type after its cooldown, with stored-inventory checks; unstarted Depot blueprints can change type; personnel requests use each facility's selected source and one player-wide toggle; Operator queues can be canceled; Fabricator armor upgrades require powered Engineer work, support multiple Engineers, retain progress, and survive Fabricator destruction after completion. Specialized units can no longer pick up a different specialization kit.

## Running locally

Requirements: Node.js 24, Python 3, and a supported desktop browser. The setup helper installs a pinned portable editor locally and downloads only the web templates required for this project. It supports development on Windows or Linux; it does not create native game exports.

```sh
npm ci
python tools/setup-engine.py
npm run export:web
npm run serve
```

Open `http://127.0.0.1:8080/`. Choose **Deploy expedition** to use the current scene. The project can also be opened directly in Godot; network rooms require the browser export.

`npm run serve` also starts a local custom-protocol WebSocket coordinator on port 8081 for development. Open the game with `?coordinator=ws://127.0.0.1:8081` in two browser contexts to test actual WebRTC peer connections without relying on public relay availability. This changes signaling only; gameplay packets still travel through Godot WebRTC.

Without that parameter, sessions use the configured Cloudflare Worker coordinator and Metered ICE servers. Live native relay-only connectivity with the configured Worker and Metered subscription passed. Different-network coverage and live Pages/itch.io deployment require separate validation. A localhost test does not prove Internet connectivity for every player pairing.

To package the web export for itch.io after verification:

```sh
python tools/package-web.py
```

The ZIP appears at `build/atd-0.1.0-web.zip`, with `index.html` at its root. No publication has been performed. CI builds/tests the browser artifact but has no deployment credentials or publication step.

## Controls in this milestone

- Left click selects an entity; drag selects owned units; Shift adds to the selection.
- Right click issues a context order: movement, attack, resource collection, kit pickup, or work on an unfinished structure.
- **M** followed by clicking a patch or production facility starts a coordinated expedition, including selected vehicles and their friendly crew. Drivers, passenger workers, guards, gathering/loading, regrouping and repeated physical delivery share a persistent group order.
- **B** opens construction. Select a structure type, then left click a revealed site. Escape cancels placement mode; select an unfinished building to cancel it.
- B then D arms the last-selected Depot capacity type, initially Ore. Place immediately or choose a resource with the five buttons and O/G/A/P/C hotkeys. Depot reconfiguration uses the same five actions.
- Construction previews cover the entire footprint and turn red for blocked, unrevealed, or unaffordable sites. Hold Shift when placing to keep the current type selected.
- Right click a damaged friendly structure with an Engineer to repair it. Right click an Anchor/Depot with loaded carriers to deposit cargo. **X** stops orders; **Home** centers the Anchor; click the tactical map to pan.
- Boarding moves selection onto the occupied vehicle; selection guidance is contextual and does not overwrite order feedback on income updates. The selection panel offers unit stances, Operator requests, Engineer/infantry kits, extraction, construction cancellation, and applicable structure toggles.
- Select a Depot to change its capacity type. Select an Armory to configure its personnel source and automatic Operator requests. Queue chips cancel individual orders; only unstarted orders refund their own cost.
- Build a Radar for unidentified enemy-tile contacts. Select a turret and right click a contact to override its target; infantry still require vision. Select Radar/Rampart or place their blueprints to preview coverage.
- Ramparts add a fixed armor layer to friendly structures; the inspector shows the effective armor and shield contribution.
- Gates have separate Open/Close and Lock/Unlock controls. Unlocked friendly Gates open for units whose routes pass through them, then close once traffic clears.
- Build a Factory to queue vehicles. Configure automatic Operator requests and their source; requested Operators board their assigned vehicle when ready. Select infantry and use **Board vehicle**, or right click a vehicle. **Unload crew** unloads passengers first, then the driver.
- Select workers and use **Load cargo** to transfer mixed resources into a Ranger or Excavator. Right click an Anchor/Depot with a driven cargo vehicle to deliver. Select a driven Excavator and right click a revealed cliff to clear it.
- Scout passenger weapons follow the Scout?s stance, use its vision, and can fire while it moves. Other passengers cannot fire. Vehicles without a driver cannot move, attack, illuminate, or reveal terrain.
- Build a Fabricator, purchase a specialization armor upgrade, then select Engineers and right click the Fabricator to assign research work. Multiple Engineers speed it up; power loss pauses it.
- WASD or arrow keys pan; middle drag pans; viewport edges scroll; wheel zooms; Insert/Delete temporarily rotate.
- Space pauses single-player simulation. Camera and order input remain available while paused. Speed selection affects single player only.
- Browser rooms use **Host**, share/paste the full invitation, **Join**, then let the host launch.

All listed Commonwealth construction buttons are now available, including Radar and Rampart. CPU Mother/Womb construction is implemented; player Mothers now place typed Wombs/Stomas, and Wombs expose Gland construction. Mixed construction and repair selections now retain military protection.

## Coverage

| System | Current implementation |
| --- | --- |
| Project and web export | Pinned Godot project, Compatibility renderer, non-threaded templates, relative-path browser adapter, build/package tools. |
| Map and movement | Seeded hex disk, cliffs, resource fields, separated starts, accessible starting fields, routes to the Medusa, continuous path-following and spatial unit separation. Automatic friendly gate passage, independent manual/lock controls, and delayed closing are implemented. Advanced collision recovery still needs work. |
| Camera and selection | Perspective RTS view, four navigation methods, temporary rotation, zoom limits, pause-independent navigation, selection, context orders, tactical map and Anchor centering. |
| Resources | Individual workers mine/collect, mixed cargo, physical delivery, full-storage waiting, Depot type changes and reconfiguration cooldown/capacity checks. Nacre is Anchor-only. Manual vehicle cargo loading and delivery are available; automated expeditions allocate selected crews, transport workers, load cargo and repeat deliveries. Source depletion, destroyed dropoffs, lost drivers, storage limits and manual interruptions are handled by the group controller. |
| Construction | Blueprint payment, pre-start refund, approach/occupancy checks, Engineer construction work, health progress, persistent unfinished work, post-start resource loss. |
| Production | Operator queues and cancellations, separate kit queues, five-kit accounting including finished kits, request toggles/configured personnel sources, queue inspection and cancellation UI, kit collection, buffers and recipes. Factory vehicle queues, optional Operator requests, and automatic driver assignment are implemented. |
| Power | Footprint-connected grids, fuel cycles, active-production demand, fixed brownout rates, blackout latching/recovery, enabled toggles. Detailed Relay loss behavior and all coverage edge cases need further testing. Unlocked friendly Gates open for routed passage and close after traffic clears; manual opening and locking are separate controls. |
| Combat | Target attacks, flat armor, configurable minimum damage, flame cones, obstruction checks, turret engagement, defensive leash, concealment checks, healing/repairs and Fabricator armor upgrades. Radar/vision/illumination targeting rules, buried-area immunity, Thresher transitions, nonstacking powered Rampart armor, and turret contact overrides are implemented. Full stance edge cases and Lightless upgrades remain incomplete. |
| Visibility and Gloom | Vision/illumination flood fills, personal vision without light, remembered terrain, visible entity filtering, Gloom frontier spread, illumination damage, unsupported withering and regeneration. Powered Radar and driven Scout detection expose unidentified occupied-tile contacts on the battlefield/minimap. Enemy identities are filtered consistently in rendering and snapshots; shared illumination remains separate from vision. Per-viewer last-seen structure records freeze hidden state and are cleared on rediscovery. Global Gloom membership supports Father recruitment and structure defense calls; Medusa stances propagate to all combat units on Gloom through a validated host-side testing command; player Medusa/Father stance controls are available. |
| Lightless | Starting Chyme and Medusa income; CPU-paid Mother queues; reachable paid Womb blueprints, Mother transformation and health-based gestation; typed Womb caps/unlocks and free spawning; parallel paid queues with manual-first shared caps; retained capped/locked progress; post-Medusa Womb acceleration. Stalkers, Ravagers, Threshers and Shades now enter normal play through Wombs. Combat damage fills finite personal Chyme reserves, which deposit near a built Medusa or Stoma. Gather units return to reachable organs when full or damaged; CPU Wombs grow armor and income Glands, which reconnect to surviving or replacement Wombs. Existing Mothers can grow additional Wombs after Medusa death. CPU Fathers recruit through local range or any Gloom patch, guide recruits, and preserve their stance overrides. Threatened structures call available defenders on any Gloom patch, distributing them across calls without overriding Father recruits. Defend units protect a nearby structure or their Father within a bounded radius. One player may control Lightless in solo or multiplayer; solo adds a Commonwealth AI opponent. CPU Fathers coordinate targets and recover wounded cohorts; population pressure triggers bounded additional Wombs. Advanced strategy still needs playtesting. |
| Vehicles | Factory production; drivers and passenger limits; passenger-first unloading; empty-vehicle commandeering; protected occupants; destruction/elimination unloading; driver-dependent vision/light; forward headlight cones; Scout passenger weapons following the Scout stance; manual worker-to-vehicle cargo transfer; Excavator cliff clearing and rubble. Automated convoy execution, crew replacement, and vehicle-loss continuation are implemented. |
| Combat/work feedback | Bounded audience-filtered events survive frame/snapshot skips; weapon profiles drive tracers, flashes, recoil and sound. Hit/shield/death feedback, health trails, grouped damage labels, ready/delivery cues, working machinery, and visible Scout passengers are implemented. Effect budgets and look/audio values are configurable. See [feedback](feedback.md). |
| Extraction | Medusa death exposes Nacre; Anchor delivery, 500/1,000 thresholds, 90-second timer, and elimination outcomes are implemented at state level. Ordinary raiders prioritize active extractions and retarget when an extracting player is eliminated. Concurrent countdown ordering is deterministic; full balance and Internet match acceptance remain unverified; boss stays disabled. |
| Networking | Player rooms, compatibility check, host player slots, validated host-side orders, sequence deduplication, filtered snapshots, binary transport, bounded/coalesced state queues, terminal host loss. Non-host departure eliminates that player while retaining assets/orders. |
| Release and persistence | Web packaging and build/test CI. Public deployment, saved Nacre wallet, account/cross-origin persistence policy, and final release verification remain pending. |

## Verification

2026-11-11 multiplayer snapshot pass: full npm tests passed, including five native
peers and the new compression/backpressure regressions. Final simulation/interface
checks and web export passed; focused browser checks passed both browser-host/
native-guest admission and native-host/Lightless-guest movement with terminal host
loss. The final unsent-state replacement refinement passed the affected native
transport test. Unit route-copy omission was excluded after its benchmark showed
higher mean cost. See [CPU performance](performance.md#multiplayer-snapshot-pass).

2026-11-11 completion/Thresher pass: simulation, interface, configuration and
native transport tests passed; the web export and two focused Lightless browser
checks passed. Native visual review covered creature/organ silhouettes and the
Father roster. The initial full browser run passed 11 checks; its guest-role check
ran while native configuration had advanced beyond the browser export. Rebuilding
and rerunning that check passed authoritative movement and terminal host loss.
The unrelated browser checks were not repeated after the Thresher fix.
Regression coverage includes replacement Engineers, Marine/Father recovery,
capacity-driven Wombs, individual recruit release, convoy vehicle loss, blocked
move recovery, concurrent extraction ordering, bounded path queries and Thresher
obstruction recovery. Asset import/export now use recovery mode to avoid the open
Windows editor's temporary native-extension DLL lock; runtime tests remain normal.

2026-11-11 global communication change: full tests, web export and the focused browser Lightless-controls check passed. Regressions cover Medusa stances across isolated patches, off-Gloom senders, remote Father recruitment, broken bridges, leaving/returning to Gloom, local recruitment, Father overrides, global defense calls and post-Medusa release behavior.

2026-11-11 global Gloom sight pass: full tests, web export and the focused browser Lightless-controls check passed. New checks cover disconnected unsupported patches, enemy occupants, observer isolation, owner snapshots, immediate sight removal after withering, preserved terrain memory, and immediate sight on newly grown tiles beyond organ vision.

2026-11-11 controlled-colony autonomy fix: full tests, web export and the focused browser Lightless-controls check passed. New checks cover Probe/Attack/Gather movement toward unexplored enemy territory for host and guest roles, eventual autonomous Anchor engagement, preserved fog/snapshot privacy, and Medusa safety. The browser test now requires starting Scavengers to move without any player order before checking the command panel.

2026-11-11 indirect-control/Womb pass: the full simulation/interface/configuration/native-transport suite passed. Focused AI checks also passed after autonomous Thresher rally/defense transitions were added. Regressions cover denied individual combat orders, cap-safe reconfiguration, paid queue retention, immediate capacity removal, cooldown timing, Gland reconnection, snapshots, blueprint type changes and remembered submenu choices. Web export and the focused browser Lightless-controls check passed; the submenu and visible population badges were inspected in native/browser captures.

2026-11-11 friendly-targeting fix: raid fallback `-1` no longer resolves to the Lightless player's Medusa, and stale friendly automatic objectives are rejected. Native transport checks passed; simulation/interface/configuration checks passed sequentially after an initial editor DLL-loading conflict. Web export and the focused browser Lightless-controls check passed, including activating Attack and confirming that Medusa health remains unchanged. Regression coverage exercises both host and guest Lightless slots and discovered enemy Anchors.

2026-11-11 player Lightless pass: `npm test` and web export passed. Focused native checks cover role exclusivity, host/guest assignment, CPU fallback, solo AI production, command validation, Mother construction/refunds, snapshots, movement and buried Thresher controls; native interface checks exercise actual launch/stance/spawn/cancel buttons. Exported browser checks passed `/v3/` loading/selection and Lightless command panels. The headless-main-host/browser-Lightless-guest check passed authoritative movement and terminal host loss. The unrelated full browser suite was not repeated.

The redundant long RTS browser flow was removed; its keyboard, selection, group and build behavior remain covered by native interface checks. The long versioned-scene flow was reduced to its unique `/v3/` loading/selection smoke check. Two simultaneous software-rendered browser scenes caused false host-loss failures, so the multiplayer role/order test now uses the actual headless main-scene host and one rendered browser guest. The reverse browser-host/native-guest check and five-peer native transport checks remain.

2026-11-11 CPU Stoma pass: `npm test`, `npm run export:web`, and the focused `npm run test:browser -- --grep "native guest joins"` smoke check passed. New simulation checks cover reserve/cap enforcement, deterministic placement, Mother loss/replacement, gestation damage, blocked sites, and actual Chyme delivery. The full browser suite was not repeated; its earlier timeouts remain unresolved.

2026-11-11 Medusa network stance pass: `npm test` and `npm run export:web` passed. The single full `npm run test:browser` run finished with 10 passed and two 180-second timeouts: versioned-scene selection/mining/navigation and RTS controls. Browser acceptance remains incomplete; no automatic rerun was performed. Simulation coverage includes command validation, paused propagation, split/reconnected Gloom, new units, Father overrides/release, Medusa death, and JSON snapshots.

2026-11-10 task pass: `npm test` and `npm run export:web` passed, including command-driven completion of all three missions and construction recovery/refund checks. Shawn independently completed all three missions. The final browser run passed mission selection/objectives, wall painting and minimap input; the remaining browser checks were stopped at the user's request to limit further verification. Earlier tracing-enabled runs encountered UI-test failures and rendering timeouts; do not interpret this pass as a complete browser or Internet multiplayer acceptance run.

The controls pass passed the headless suite, focused order/interface checks, and a native viewport-input check for minimap capture and Shift commands. Its combined software-rendered browser input check hit a 90-second total budget before completion; full browser verification of the new controls remains incomplete. No repeat multiplayer suite was run for this pass.

```sh
npm test
npm run test:browser
```

The simulation suite runs real Godot code headlessly. It checks seeded layout, hex conversions, access to the Medusa, resource conservation, full-storage waiting, construction/refunds, power recovery, kit completion, personnel transformation, snapshots, elimination, extraction timing, healing, repair costs, delivery interruption, separation, concealment, defensive leash, probe reactions, Gloom growth/withering, vehicle production/crew/cargo, Scout passenger fire, headlight cones, excavation, crew/terrain serialization, radar anonymity, shared illumination, buried targeting/area immunity, Rampart stacking/power loss, automatic gates/locks, configuration validation/hash behavior, presentation-event retention/privacy/serialization, hit overlays, health trails, and fog disappearance without false deaths.

Browser tests use actual Chromium, the exported Godot game, Godot WebRTC connections, and the local signaling relay. They exercise selection/mining and camera controls, cross-origin local browser clients, host-confirmed movement and host departure. The native suite covers five-peer binary transport, and real attack feedback in the exported renderer. They are not a substitute for a five-player full gameplay session on different networks.

Local verification on Windows: headless simulation/interface/configuration suites pass. The latest full browser run passed all five checks, including actual fire/hit feedback through legal friendly fire. Earlier two-scene software-rendered runs occasionally stalled during startup, so startup timing remains an area to watch. The exported scene was also inspected visually. Linux CI is configured but has not been run from this workspace. The ZIP is built and checked for required files and archive integrity; public publication remains pending.

On Windows, tests default to the system Chrome executable. Set `CHROMIUM_BIN` to another Chromium binary if required. On Linux, install Playwright Chromium with `npx playwright install --with-deps chromium`. Browser startup under software rendering can be slow; tests record a trace on failure.

The `?test=1` URL parameter enables a narrow browser test-command queue and diagnostics. Normal gameplay does not need that parameter. Test commands use the same order/ownership validation as the UI rather than bypassing host authority.

## Next implementation work

1. Complete movement/steering, source/destination recovery, and construction/repair edge cases, and vehicle arrival/unloading edge cases.
2. Exercise expedition formations and transport recovery on dense maps and during full multiplayer matches.
3. Complete remaining combat/stance edge cases and improve both factions' CPU strategies. Typed Womb production now connects the other combat units, including Threshers, to ordinary matches.
4. Exercise and balance the ordinary extraction assault; complete persistence policy, browser lobby polish, and full-match acceptance.
5. Validate real hosted Pages/itch.io rooms, different-network/TURN behavior, frame-time budgets, and the full five-player match before publishing an alpha as complete.

Configuration now validates at startup and through `npm run config:check`; `npm run config:reference` regenerates the full default-value index. See [developer guide](developer-guide.md) for configuration coverage limits and system contracts.

The design documents remain the target. Where coverage is incomplete, this status file takes precedence over interpreting a design paragraph as an already implemented feature.

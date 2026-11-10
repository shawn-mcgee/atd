# Implementation status

## Current milestone: runnable foundation

The repository now contains a Godot **4.7.2** project and a single-threaded browser export, with Godot **WebRTCMultiplayerPeer**, the custom coordinator and Metered TURN. The native Windows/Linux x86_64 editor/runtime also supports networking. This is the first implementation milestone, not the completed alpha described in the design documents.

The current art pass combines procedural industrial models, basic procedural animation, a generated ground material and title illustration, a revised command interface, and original synthesized sound. Models and audio still need production refinement. See [art direction and asset provenance](art-direction.md).

## Single-player interaction pass

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
- **M** followed by clicking a patch assigns individual worker mining. Full vehicle-assisted expeditions are not implemented yet.
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

All listed Commonwealth construction buttons are now available, including Radar and Rampart. CPU Mother/Womb construction is implemented; human Lightless construction controls and automated mining expeditions remain pending.

## Coverage

| System | Current implementation |
| --- | --- |
| Project and web export | Pinned Godot project, Compatibility renderer, non-threaded templates, relative-path browser adapter, build/package tools. |
| Map and movement | Seeded hex disk, cliffs, resource fields, separated starts, accessible starting fields, routes to the Medusa, continuous path-following and spatial unit separation. Automatic friendly gate passage, independent manual/lock controls, and delayed closing are implemented. Advanced collision recovery still needs work. |
| Camera and selection | Perspective RTS view, four navigation methods, temporary rotation, zoom limits, pause-independent navigation, selection, context orders, tactical map and Anchor centering. |
| Resources | Individual workers mine/collect, mixed cargo, physical delivery, full-storage waiting, Depot type changes and reconfiguration cooldown/capacity checks. Nacre is Anchor-only. Manual vehicle cargo loading and delivery are available; full hauling failure recovery and automated expeditions remain pending. |
| Construction | Blueprint payment, pre-start refund, approach/occupancy checks, Engineer construction work, health progress, persistent unfinished work, post-start resource loss. |
| Production | Operator queues and cancellations, separate kit queues, five-kit accounting including finished kits, request toggles/configured personnel sources, queue inspection and cancellation UI, kit collection, buffers and recipes. Factory vehicle queues, optional Operator requests, and automatic driver assignment are implemented. |
| Power | Footprint-connected grids, fuel cycles, active-production demand, fixed brownout rates, blackout latching/recovery, enabled toggles. Detailed Relay loss behavior and all coverage edge cases need further testing. Unlocked friendly Gates open for routed passage and close after traffic clears; manual opening and locking are separate controls. |
| Combat | Target attacks, flat armor, configurable minimum damage, flame cones, obstruction checks, turret engagement, defensive leash, concealment checks, healing/repairs and Fabricator armor upgrades. Radar/vision/illumination targeting rules, buried-area immunity, Thresher transitions, nonstacking powered Rampart armor, and turret contact overrides are implemented. Full stance edge cases and Lightless upgrades remain incomplete. |
| Visibility and Gloom | Vision/illumination flood fills, personal vision without light, remembered terrain, visible entity filtering, Gloom frontier spread, illumination damage, unsupported withering and regeneration. Powered Radar and driven Scout detection expose unidentified occupied-tile contacts on the battlefield/minimap. Enemy identities are filtered consistently in rendering and snapshots; shared illumination remains separate from vision. Per-viewer last-seen structure records freeze hidden state and are cleared on rediscovery. Gloom communication remains pending. |
| Lightless | Starting Chyme and Medusa income; CPU-paid Mother queues; reachable paid Womb blueprints, Mother transformation and health-based gestation; typed Womb caps/unlocks and free spawning; parallel paid queues with manual-first shared caps; retained capped/locked progress; post-Medusa Womb acceleration. Stalkers, Ravagers, Threshers and Shades now enter normal play through Wombs. Gather/Defend coordination, combat Chyme delivery, Glands, Father recruitment, human Lightless controls and post-Medusa CPU expansion remain pending. |
| Vehicles | Factory production; drivers and passenger limits; passenger-first unloading; empty-vehicle commandeering; protected occupants; destruction/elimination unloading; driver-dependent vision/light; forward headlight cones; Scout passenger weapons following the Scout stance; manual worker-to-vehicle cargo transfer; Excavator cliff clearing and rubble. Automated convoy execution remains pending. |
| Combat/work feedback | Bounded audience-filtered events survive frame/snapshot skips; weapon profiles drive tracers, flashes, recoil and sound. Hit/shield/death feedback, health trails, grouped damage labels, ready/delivery cues, working machinery, and visible Scout passengers are implemented. Effect budgets and look/audio values are configurable. See [feedback](feedback.md). |
| Extraction | Medusa death exposes Nacre; Anchor delivery, 500/1,000 thresholds, 90-second timer, and elimination outcomes are implemented at state level. Full end-to-end balance and match acceptance remain unverified; boss stays disabled. |
| Networking | Player rooms, compatibility check, host player slots, validated host-side orders, sequence deduplication, filtered snapshots, binary transport, bounded/coalesced state queues, terminal host loss. Non-host departure eliminates that player while retaining assets/orders. |
| Release and persistence | Web packaging and build/test CI. Public deployment, saved Nacre wallet, account/cross-origin persistence policy, and final release verification remain pending. |

## Verification

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
2. Implement the documented mining expedition state machine and its interruption/cargo invariants.
3. Complete remaining combat/stance edge cases, combat Chyme delivery, Glands, Gloom coordination, Father recruitment, human Lightless controls and post-Medusa CPU expansion. Typed Womb production now connects the other combat units, including Threshers, to ordinary matches.
4. Build out the ordinary extraction assault, persistence policy, browser lobby polish, and full-match acceptance.
5. Validate real hosted Pages/itch.io rooms, different-network/TURN behavior, frame-time budgets, and the full five-player match before publishing an alpha as complete.

Configuration now validates at startup and through `npm run config:check`; `npm run config:reference` regenerates the full default-value index. See [developer guide](developer-guide.md) for configuration coverage limits and system contracts.

The design documents remain the target. Where coverage is incomplete, this status file takes precedence over interpreting a design paragraph as an already implemented feature.

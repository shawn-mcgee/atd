# Against the Darkness - Hive Recovery

A Godot 4.7.2 sci-fi horror RTS on a planet without sunlight. Command engineers, infantry, and piloted vehicles against the **Lightless**. Materials and methane enter global reserves only after physical delivery. Local generators and repeaters distribute power.

Open `project/project.godot`, press **F5**, then **Begin Expedition**. Restart the scene after code changes.

## Simulation and presentation

The experiment now runs a headless deterministic gameplay core in `project/engine/` and a separate top-down 2D view in `project/view/`. The original gameplay rules remain: the view draws the approved unit, building, terrain, resource, and effect sprites. Structure footprints remain authoritative for placement and selection. HQ retains its seven-cell hexagonal footprint, generators retain triangular three-cell footprints, and single-cell structure bounds remain 80 percent tile size. Transparent building art has no filled polygon foundation. Ramps and platforms still affect navigation, elevation, and sight lines.

The model assets, Asset Forge pipeline, 3D renderer, and shaders have been removed. The [sprite integration guide](project/docs/sprite-integration.md) documents atlas preparation, orientation corrections, and procedural gates. A future 2D or 3D renderer can read the same core and submit the same commands. See [engine architecture](project/docs/engine.md) for the command API, replay format, and boundaries. The [asset generation brief](project/docs/asset-generation-brief.md) defines the shared art style, technical specifications, and eight batched sprite sheets.

## Mission

1. Scout for the extraction beacon and hive. Their locations appear only after friendly illumination discovers them. Send an engineer to the ruined **Extraction Beacon** and right-click it; repairs take 12 seconds.
2. Send infantry to the discovered **CORE** marker at the **Lightless Hive**. Right-click the hive to take the **Hive Core**. Extraction must be repaired before the initial theft.
3. Bring the carrier within **7m** of the beacon and hold for **60 seconds**. Boarding a vehicle keeps the core with its carrier.

The Lightless defend their hive aggressively. Theft triggers committed pursuit, twice the population ceiling (32), and faster reinforcements. If the carrier dies, the core drops; another infantry unit can retrieve it with a right-click. A Lightless reaching the dropped core loses the mission. Destroying HQ also loses the mission.

Leaving the extraction radius resets the timer. A destroyed extraction beacon becomes repairable ruins and resets extraction; it can be repaired again. Delivering materials supports expansion and no longer ends the mission.

## Controls

| Control | Action |
| --- | --- |
| Click / drag | Select a unit or group; Shift adds to selection |
| Double-click | Select visible units of the same type |
| Right-click | Contextual order: move, board, build, repair, gather, deliver, retrieve core, or attack visible Lightless |
| Shift + order | Append to the selected unit's order queue; an immediate order clears its queue |
| Q, then click | Attack a visible Lightless/hive, or attack-move toward terrain; pursue visible enemies before resuming the route |
| V, then click | Defend a location, structure, or unit; pursue within an 8m leash and return to the defense point |
| P, then click | Patrol between the current position and the destination; Shift-click adds route points; Escape exits targeting |
| M, then click | Mining expedition; choose a surveyed patch or a Material Depot/Methane Tank |
| E, then click | Exploration expedition; choose terrain to begin an autonomous map survey |
| C, then click | Selected drill vehicle clears a rock or mesa tile |
| Delete | Destroy selected owned structures or units; no refund |
| Y | Toggle selected repeaters |
| B / U | Board nearby infantry / unload passengers, then driver |
| L / J / H | Collect nearby carried cargo / deposit cargo / return a vehicle to a home receiver |
| G / R / X | Escort / repair targeting or selected turret reload / stop and clear orders |
| Z | Toggle automatic reload on selected ammunition turrets |
| N | Toggle automatic recharge on selected vehicles |
| F1 | Open controls and mission help |
| 1-0 | First ten construction choices for engineers; factory production shortcuts otherwise |
| T | Rotate a construction footprint, ramp, or gate |
| WASD / arrows | Pan the camera; attack-move uses Q |
| Wheel / middle drag | Zoom / drag the map |
| Alt + middle drag | Rotate the top-down map |
| Comma / period / Home / F | Rotate camera / reset camera / focus HQ |
| Space / Escape | Pause / cancel targeting or selection |

Selection details and contextual commands share the bottom dock. Commands display their hotkeys in brackets. Engineers have a Build tab, with resource icons, construction costs, and visible key badges on each card; structures without a numeric shortcut are marked **Click**. Production cards show the number for the selected factory. The minimap stays in the bottom-right corner. F1 opens the full controls, including construction modifiers. Selected units show target/destination lines. Firing infantry face their shot target; flashes, tracers, and flames originate at sprite weapon attachments. Synthetic beeping has been removed.

## Starting scenario and generation

Each new mission generates a seeded layout of rock ridges, passages, resource fields, extraction, and the hive. The landing zone and approaches to every resource field/objective stay clear. Restarting generates a different level. The help overlay and end screen show the seed; reproduce a map with `& .\Godot_v4.7.2-stable_win64.exe --path .\project -- --seed=42`.

Start with **HQ, one engineer, and one marine**, **100 MAT**, and **100 CH4**. There are no starting vehicles, generators, repeaters, depots, tanks, barracks, or garages. HQ holds **100 MAT / 100 CH4**, accepts both delivered resources, relays power within **7m**, and supplies **4 auxiliary power** without methane. HQ consumes none of its own output when idle, so all four units are available to connected consumers. Its dim light reaches **5.93m**, one tile step farther than before. HQ produces engineers with **1** and scout vehicles with **2** (60 MAT + 25 CH4, 10 seconds). Scouts still need a driver. Build infrastructure and recruit the rest of the expedition. The starting area has a two-minute damage grace for preparation; leaving it is dangerous immediately after initial probing begins.

Structure polygons carry short labels; labels never participate in selection. Mission objectives remain hidden until scouted. Resource patches are discovered individually by friendly illumination and remain recorded on the minimap afterward. HQ starts beside three material cells (172 each, 516 total) and one methane cell (129). Distant fields require scouting; HQ has no resource scan.

## Coordinated tactics and turret ammunition

Attack-move, defense, and patrol become shared missions when commanding a mixed squad or a crewed vehicle. A vehicle reserves a pilot and boards engineers into available passenger seats; infantry remain outside as escorts. Marching speed follows the slowest walker. Infantry protect engineers on foot when transport is unavailable. A defense command can protect a specific unit or structure and returns from pursuits outside an 8m leash. A patrol shares its waypoints across the crew. Direct unit orders detach that unit, manual unloading cancels vehicle coordination, and Shift can queue a tactical mission after current work.

A crewed scout can investigate approximate sensor contacts during these missions. Investigations stay bounded and time out before resuming the assigned route. A contact does not illuminate or reveal its creature, and weapons still require vision.

| Turret | Power | Magazine | Reload | Attack |
| --- | --- | --- | --- | --- |
| Minigun | 3 | 30 | 8 MAT, 4 seconds | Fast targeted bursts |
| Laser | 8 | Unlimited | None | Slower, stronger targeted shots |
| Flame | 4 | 12 | 6 CH4, 5 seconds | Area damage to visible enemies |

Ammunition turrets automatically reload when empty. Select turrets and press **R** for a manual reload, or **Z** to toggle automatic reload. Reloads consume their full cost once, cannot start without resources, disable firing, and pause during a power outage. A full magazine cannot be manually reloaded. The three types reuse the existing turret chassis with distinct colors.

## Economy, construction, and power

Resources are **Materials (MAT)** and **Methane (CH4)**. Remote fields comprise seven one-cell patches; starter deposits are smaller. Move units or crewed vehicles into the darkness to illuminate and discover resource cells. Mining automation only follows discovered patches. Click a surveyed patch to inspect its remaining amount and the field total. Engineers physically carry resources to the matching receiver; vehicles transport larger shipments. Mining expeditions require at least one working engineer and a separate driver for every vehicle.

An **Extractor** costs 70 MAT + 10 CH4, occupies a resource patch, and consumes 2 power. An engineer gathers **3 resources per cycle** from an operating extractor, or 1 by hand. Extraction still requires an engineer and delivery. Manual and expedition mining require the engineer to stand on the deposit or an adjacent hex, within physical reach and at the same elevation. Selecting a receiver for mining chooses the nearest surveyed active field of its resource type.

Construction spends banked resources immediately, but an engineer must reach and complete the blueprint. Nearby maintenance chains completed work to other repairs or blueprints. Occupants move safely aside before a blueprint becomes solid.

Hex radius is **1m**, half the earlier size, while the map keeps its world extent. HQ reserves seven cells (center plus six neighbors); generators and barracks reserve compact three-cell triangles; the garage reserves a four-cell diamond. Other buildings use one cell, except two-cell ramps. Footprints rotate with T, and their previews match occupied cells. Adjacent terrain cells no longer cause a circular placement exclusion.

HQ supplies four free auxiliary power; generators supplement it and burn methane only for demand beyond that auxiliary supply. A generator supplies **12 power** within **3.5m** (about two tile steps). A repeater extends the network over **10.4m**. Turning a repeater off disconnects its branch. Power overlays show each source's actual range and planned/offline connections. Consumers receive automatic priority; methane burn follows served demand. Enemy sensors on scouts and Scanner structures still provide approximate hostile contacts without revealing enemies or resources.

Select a connected structure, infantry unit, or vehicle to see its local grid usage and spare power beside the power icon. Separate grids are never combined into a global power total.

Health bars appear above damaged units, vehicles, structures, and visible enemies, then disappear at full health. Vehicle battery bars remain below the circles.

HQ also recharges vehicles within its operating relay range. All vehicles require a driver. Batteries drain **0.25 percentage points per second while driving** and recharge **8 points per second** within an operating generator or repeater's range. Automatic recharge starts enabled; toggle it with **N** or the vehicle command button. An empty battery stops propulsion and headlights; charging resumes the existing route. Emergency beacons remain. The Garage can produce a **Drill** (140 MAT + 45 CH4): clearing a rock or mesa tile takes three seconds and costs exactly **5 CH4**. Insufficient methane leaves the tile and reserves unchanged.

## Repository and validation

### GitHub Pages

The repository uses **Settings > Pages > Build and deployment > Source: GitHub Actions**. The workflow in `.github/workflows/github-pages.yml` exports and deploys pushes to `main`. Pull requests to `main` build the web export without deploying; **Actions > Build and deploy Godot Web > Run workflow** can also rebuild `main` manually.

Game URL after the first successful deployment: **https://shawn-mcgee.github.io/atd/**.

Commit the `project/` sources together with the workflow and `project/export_presets.cfg`. CI downloads the pinned Godot **4.7.2** Linux editor and matching export templates, verifies their official SHA-512 checksums, imports the project, exports `build/web/index.html`, and uploads the web directory as the Pages artifact. No personal access token or repository secret is required by the workflow.

The Web preset uses Compatibility/WebGL 2, disables threads and native extensions, and disables the PWA service worker. It works on ordinary Pages hosting without cross-origin isolation headers, including the repository's `/atd/` URL prefix. Generated output and local export credentials stay ignored.

To preview locally, install the **4.7.2** export templates through Godot's **Editor > Manage Export Templates**, then run from the outer repository root in PowerShell 7:

```powershell
pwsh -NoProfile -File tools/build-web.ps1
python -m http.server 8000 --directory build/web
```

Open **http://localhost:8000/**. `build-web.ps1` also accepts `-GodotExecutable` for another local engine path. The local portable PowerShell 7 installed during setup is available at `$env:LOCALAPPDATA\ATD-Tools\PowerShell\pwsh.exe` if `pwsh` is not on PATH. Exported games need an HTTP server; opening `index.html` directly from disk will not work.

### Project files and checks

- `project/engine/`: gameplay state, fixed ticks, commands, seeded map generation, replay and diagnostics.
- `project/view/`: 2D input adapter, primitive renderer, HUD, minimap, and status bars.
- `project/tools/`: headless regression suites and deterministic fixtures.
- `tools/`: test runner and web export helper.
- `project/docs/engine.md`: core API and presentation boundaries.

Run from the outer repository root:

```powershell
& .\Godot_v4.7.2-stable_win64.exe --editor --path .\project
python tools/test-game.py --jobs 3
python tools/test-game.py --name engine --name top-down
& .\Godot_v4.7.2-stable_win64.exe --path .\project --script res://tools/preview-prototype.gd -- --engineer --seed=42
```

Use `--godot <path>` if the engine executable is elsewhere. The test runner imports first, rejects script errors regardless of exit code, and retains logs in ignored `project/art_source/.build/test-results/`. The suites cover deterministic replay, old-gameplay checkpoints, view isolation at different frame rates, footprint geometry, picking, contextual commands, logistics, construction clearance, expeditions, power, and predator behavior. Mission tests cover beacon repair, theft, carrying, timer resets, extraction, and loss conditions.

The legacy GPU picking, mesh occlusion, and 3D camera tests have been replaced by 2D geometry-picking, projection, resize, and view-isolation checks. Gameplay regressions now run without loading a world scene. Render previews save to the same ignored diagnostics folder.

## Current limits

First-pass balance and placeholder effects; the longer extraction hold and minimal start need playtesting. No save/load, campaign, research tree, or full crowd collision. Gameplay illumination does not cast wall shadows, although weapon sight lines and navigation respect obstacles. Deterministic replay targets the same Godot version and math implementation; cross-platform network lockstep has not been established. Destroying structures gives no salvage. Drill clearing currently supports rock obstacles and natural mesa cells; constructed ramps/platforms use the normal destroy command. Mining and exploration automation persist until interrupted or complete; queued direct orders wait for the current task to finish. Tentative designs stay in `ideas.md`; grouped actionable lists and their status are linked from `project/todo.md`. Historical specifications in `project/docs/` describe earlier iterations; this README describes the current game.

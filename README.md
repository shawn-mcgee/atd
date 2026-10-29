# Against the Darkness - Hive Recovery

A Godot 4.7.2 sci-fi horror RTS on a planet without sunlight. Command engineers, infantry, and piloted vehicles against the **Lightless**. Materials and methane enter global reserves only after physical delivery. Local generators and repeaters distribute power.

Open `project/project.godot`, press **F5**, then **Begin Expedition**. Restart the scene after code changes.

## Mission

1. Scout for the extraction beacon and hive. Their **EX**/**CORE** minimap markers appear only after friendly illumination reveals them, and remain recorded afterward. Send an engineer to the ruined **Extraction Beacon** and right-click it; repairs take 12 seconds.
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
| A, then click | Attack a visible Lightless/hive, or attack-move toward terrain; pursue visible enemies before resuming the route |
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
| F1 / ? | Open controls and mission help |
| 1-0 | First ten construction choices for engineers; factory production shortcuts otherwise |
| T | Rotate a construction footprint, ramp, or gate |
| Arrows / WSD | Pan; A is reserved for attack-move |
| Wheel / middle drag | Zoom / drag the map |
| Alt + middle drag | Orbit and tilt |
| Comma / period / Home / F | Rotate camera / reset camera / focus HQ |
| Space / Escape | Pause / cancel targeting or selection |

Selection details and contextual commands share the bottom dock. Engineers have a Build tab, with resource icons beside construction costs. The minimap stays in the bottom-right corner. Hover over commands for keyboard shortcuts; F1 opens the full controls. Selected units show target/destination lines and queued destinations; patrols show their route.

## Starting scenario and generation

Each new mission generates a seeded layout of rock ridges, passages, resource fields, extraction, and the hive. The landing zone and approaches to every resource field/objective stay clear. Restarting generates a different level. The help overlay and end screen show the seed; reproduce a map with `& .\Godot_v4.7.2-stable_win64.exe --path .\project -- --seed=42`.

Start with **HQ, one engineer, and one marine**, **100 MAT**, and **100 CH4**. There are no starting vehicles, generators, repeaters, depots, tanks, barracks, or garages. HQ holds **100 MAT / 100 CH4**, accepts both delivered resources, relays power within **7m**, and supplies **4 auxiliary power** without methane. HQ consumes none of its own output when idle, so all four units are available to connected consumers. Its dim light reaches **5.93m**, one tile step farther than before. HQ produces engineers with **1** and scout vehicles with **2** (60 MAT + 25 CH4, 10 seconds). Scouts still need a driver. Build infrastructure and recruit the rest of the expedition. The starting area has a two-minute damage grace for preparation; leaving it is dangerous immediately after initial probing begins.

Names float over structures only while selected. Mission objectives and their world models remain hidden until scouted. Resource patches are discovered individually by friendly illumination and remain recorded on the minimap afterward. HQ starts beside three material cells (172 each, 516 total) and one methane cell (129). Distant fields require scouting; HQ has no resource scan.

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

An **Extractor** costs 70 MAT + 10 CH4, occupies a resource patch, and consumes 2 power. An engineer gathers **3 resources per cycle** from an operating extractor, or 1 by hand. Extraction still requires an engineer and delivery. Selecting a receiver for mining chooses the nearest surveyed active field of its resource type.

Construction spends banked resources immediately, but an engineer must reach and complete the blueprint. Nearby maintenance chains completed work to other repairs or blueprints. Occupants move safely aside before a blueprint becomes solid.

Hex radius is **1m**, half the earlier size, while the map keeps its world extent. HQ reserves seven cells (center plus six neighbors); generators and barracks reserve compact three-cell triangles; the garage reserves a four-cell diamond. Other buildings use one cell, except two-cell ramps. Footprints rotate with T, and their previews match occupied cells. Adjacent terrain cells no longer cause a circular placement exclusion.

HQ supplies four free auxiliary power; generators supplement it and burn methane only for demand beyond that auxiliary supply. A generator supplies **12 power** within **3.5m** (about two tile steps). A repeater extends the network over **10.4m**. Turning a repeater off disconnects its branch. Power overlays show each source's actual range and planned/offline connections. Consumers receive automatic priority; methane burn follows served demand. Enemy sensors on scouts and Scanner structures still provide approximate hostile contacts without revealing enemies or resources.

Select a connected structure, infantry unit, or vehicle to see its local grid usage and spare power beside the power icon. Separate grids are never combined into a global power total.

Health bars appear above damaged units, vehicles, structures, and visible enemies, then disappear at full health. Vehicle battery bars remain below the models.

HQ also recharges vehicles within its operating relay range. All vehicles require a driver. Batteries drain **0.25 percentage points per second while driving** and recharge **8 points per second** within an operating generator or repeater's range. Automatic recharge starts enabled; toggle it with **N** or the vehicle command button. An empty battery stops propulsion and headlights; charging resumes the existing route. Emergency beacons remain. The Garage can produce a **Drill** (140 MAT + 45 CH4): clearing a rock or mesa tile takes three seconds and costs exactly **5 CH4**. Insufficient methane leaves the tile and reserves unchanged.

## Repository and validation

### GitHub Pages

The repository uses **Settings > Pages > Build and deployment > Source: GitHub Actions**. The workflow in `.github/workflows/github-pages.yml` exports and deploys pushes to `main`. Pull requests to `main` build the web export without deploying; **Actions > Build and deploy Godot Web > Run workflow** can also rebuild `main` manually.

Game URL after the first successful deployment: **https://shawn-mcgee.github.io/atd/**.

Commit the `project/` sources and generated assets together with the workflow and `project/export_presets.cfg`. CI downloads the pinned Godot **4.7.2** Linux editor and matching export templates, verifies their official SHA-512 checksums, imports the project, exports `build/web/index.html`, and uploads the web directory as the Pages artifact. Asset Forge is not needed on the runner because generated models are committed. No personal access token or repository secret is required by the workflow.

The Web preset uses Compatibility/WebGL 2, disables threads and native extensions, and disables the PWA service worker. It works on ordinary Pages hosting without cross-origin isolation headers, including the repository's `/atd/` URL prefix. Procedural audio uses stream playback on Web. Generated output and local export credentials stay ignored.

To preview locally, install the **4.7.2** export templates through Godot's **Editor > Manage Export Templates**, then run from the outer repository root in PowerShell 7:

```powershell
pwsh -NoProfile -File tools/build-web.ps1
python -m http.server 8000 --directory build/web
```

Open **http://localhost:8000/**. `build-web.ps1` also accepts `-GodotExecutable` for another local engine path. The local portable PowerShell 7 installed during setup is available at `$env:LOCALAPPDATA\ATD-Tools\PowerShell\pwsh.exe` if `pwsh` is not on PATH. Exported games need an HTTP server; opening `index.html` directly from disk will not work.

### Project files

- `project/`: the Godot project, gameplay, assets, scenes, model sources, and game tests. `res://` paths are relative to this folder.
- `tools/`: Asset Forge bridge, model build/verification tooling, and the test runner.
- `Godot_v4.7.2-stable_win64.exe`: local untracked engine executable.

Run commands from the outer repository root:

```powershell
& .\Godot_v4.7.2-stable_win64.exe --editor --path .\project
python tools/test-game.py --jobs 3
python tools/test-game.py --name mission-upgrade
& .\Godot_v4.7.2-stable_win64.exe --path .\project --script res://tools/test-picking.gd
& .\Godot_v4.7.2-stable_win64.exe --path .\project --script res://tools/test-occluded-units.gd
```

The runner treats script errors as failures even if Godot exits with code zero, and writes logs under `project/art_source/.build/test-results/`. The occlusion test requires rendering and is excluded from its headless suite. Existing headless tests cover logistics, navigation, construction clearance, camera/HUD/minimap input, expeditions, selection, power, and predator behavior. `test-mission-upgrade.gd` covers the Hive Recovery lifecycle and new controls/economy systems.

Key new systems: `scripts/hive_mission.gd`, `tactical_orders.gd`, `structure_footprints.gd`, `resource_fields.gd`, `vehicle_systems.gd`, `scenario_layout.gd`, `tactical_groups.gd`, and `turret_system.gd`. Balance constants remain in those files and `expedition_rules.gd`.

Rendered previews use `res://tools/preview-prototype.gd`; flags include `--briefing`, `--engineer`, `--outpost`, `--creatures`, `--terrain`, and `--live`. Screenshots and logs remain in ignored `project/art_source/.build/`.

Generated drill, extractor, beacon, and hive models use the project-owned Asset Forge Lua bridge and gameplay wrapper scenes. Regenerate only with the PowerShell 7 wrapper described in [tools/README-models.md](tools/README-models.md). Local executables, collections, runtime dependencies, bridge jobs, and `tools/assetforge.local.psd1` are excluded from Git.

## Current limits

First-pass balance and placeholder art/audio; the longer extraction hold and minimal start need playtesting. No save/load, campaign, research tree, or full crowd collision. Gameplay illumination does not cast wall shadows, although weapon sight lines and navigation respect obstacles. Destroying structures gives no salvage. Drill clearing currently supports rock obstacles and natural mesa cells; constructed ramps/platforms use the normal destroy command. Mining and exploration automation persist until interrupted or complete; queued direct orders wait for the current task to finish. Tentative designs stay in `ideas.md`; grouped actionable lists and their status are linked from `project/todo.md`. Historical specifications in `project/docs/` describe earlier iterations; this README describes the current game.

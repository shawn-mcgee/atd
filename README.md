# Against the Darkness - Hive Recovery

A Godot 4.7.2 sci-fi horror RTS on a planet without sunlight. Command engineers, infantry, and piloted vehicles against the **Lightless**. Materials and methane enter global reserves only after physical delivery. Local generators and repeaters distribute power.

Open `project/project.godot`, press **F5**, then **Begin Expedition**. Restart the scene after code changes.

## Mission

1. Send an engineer to the **EX** marker on the minimap and right-click the ruined **Extraction Beacon**. Repairs take 12 seconds.
2. Send infantry to the **CORE** marker at the **Lightless Hive**. Right-click the hive to take the **Hive Core**. Extraction must be repaired before the initial theft.
3. Bring the carrier within **7m** of the beacon and hold for **30 seconds**. Boarding a vehicle keeps the core with its carrier.

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
| Q | Scan from the selected Command Center; costs 120 charged electricity |
| B / U | Board nearby infantry / unload passengers, then driver |
| L / J / H | Collect nearby carried cargo / deposit cargo / return a vehicle to a home receiver |
| G / R / X | Escort a vehicle / repair targeting / stop and clear orders |
| 1-0 | First ten construction choices for engineers; factory production shortcuts otherwise |
| T | Rotate a construction footprint, ramp, or gate |
| Arrows / WSD | Pan; A is reserved for attack-move |
| Wheel / middle drag | Zoom / drag the map |
| Alt + middle drag | Orbit and tilt |
| Comma / period / Home / F | Rotate camera / reset camera / focus HQ |
| Space / Escape | Pause / cancel targeting or selection |

Context commands appear on the right. Engineer construction appears at the bottom left; Extractor, Scanner, Platform, and Ramp are available through their buttons. The command panel scrolls when needed to preserve minimap space at the minimum window size. Selected units show target/destination lines and queued destinations; patrols show their route.

## Economy, construction, and power

Resources are **Materials (MAT)** and **Methane (CH4)**. Each field comprises seven one-cell patches, with the original field yield preserved. Scanning reveals the nearest active field of each resource. Click a surveyed patch to inspect its remaining amount and the field total. Engineers physically carry resources to the matching receiver; vehicles transport larger shipments. Mining expeditions require at least one working engineer and a separate driver for every vehicle.

An **Extractor** costs 70 MAT + 10 CH4, occupies a resource patch, and consumes 2 power. An engineer gathers **3 resources per cycle** from an operating extractor, or 1 by hand. Extraction still requires an engineer and delivery. Selecting a receiver for mining chooses the nearest surveyed active field of its resource type.

Construction spends banked resources immediately, but an engineer must reach and complete the blueprint. Nearby maintenance chains completed work to other repairs or blueprints. Occupants move safely aside before a blueprint becomes solid.

Hex radius is **1m**, half the earlier size, while the map keeps its world extent. HQ reserves seven cells (center plus six neighbors); generators and barracks reserve compact three-cell triangles; the garage reserves a four-cell diamond. Other buildings use one cell, except two-cell ramps. Footprints rotate with T, and their previews match occupied cells. Adjacent terrain cells no longer cause a circular placement exclusion.

A generator supplies **12 power** within **3.5m** (about two tile steps). A repeater extends the network over **10.4m**. Turning a repeater off disconnects its branch. Power overlays show each source's actual range and planned/offline connections. Consumers receive automatic priority; methane burn follows served demand and scanner charging.

All vehicles require a driver. Batteries drain **0.25 percentage points per second while driving** and recharge **8 points per second** within an operating generator or repeater's range. An empty battery stops propulsion and headlights; charging resumes the existing route. Emergency beacons remain. The Garage can produce a **Drill** (140 MAT + 45 CH4): clearing a rock or mesa tile takes three seconds and costs exactly **5 CH4**. Insufficient methane leaves the tile and reserves unchanged.

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

Key new systems: `scripts/hive_mission.gd`, `tactical_orders.gd`, `structure_footprints.gd`, `resource_fields.gd`, and `vehicle_systems.gd`. Balance constants remain in those files and `expedition_rules.gd`.

Rendered previews use `res://tools/preview-prototype.gd`; flags include `--briefing`, `--engineer`, `--outpost`, `--creatures`, `--terrain`, and `--live`. Screenshots and logs remain in ignored `project/art_source/.build/`.

Generated drill, extractor, beacon, and hive models use the project-owned Asset Forge Lua bridge and gameplay wrapper scenes. Regenerate only with the PowerShell 7 wrapper described in [tools/README-models.md](tools/README-models.md). Local executables, collections, runtime dependencies, bridge jobs, and `tools/assetforge.local.psd1` are excluded from Git.

## Current limits

First-pass balance and placeholder art/audio. No save/load, campaign, research tree, or full crowd collision. Gameplay illumination does not cast wall shadows, although weapon sight lines and navigation respect obstacles. Destroying structures gives no salvage. Drill clearing currently supports rock obstacles and natural mesa cells; constructed ramps/platforms use the normal destroy command. Mining and exploration automation persist until interrupted or complete; queued direct orders wait for the current task to finish. Historical specifications in `project/docs/` describe earlier iterations; this README describes the current game.

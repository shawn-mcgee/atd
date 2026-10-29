# Against the Darkness — First Expedition

A Godot 4.7.2 sci-fi horror RTS prototype. Expand into permanent darkness with engineers, infantry, piloted vehicles, and powered illumination. Minerals and gas are global **after physical delivery**; power exists on local generator/repeater networks.

Open `project.godot`, press **F5**, then **Begin Expedition**. Restart the scene after code updates. The original 2D `world.tscn` and `tiles.tres` remain separate and unchanged.

The window expands the visible map without changing unit scale; the HUD stays anchored to its edges. When running inside Godot's embedded Game view, choose **Game → menu → Stretch to Fit** rather than **Fixed Size**. That editor setting is separate from the game's own resize settings.

The bottom-right minimap stays north-up and shows explored terrain, owned structures and on-foot units/vehicles, surveyed resource patches, and currently visible enemies. Unknown terrain stays dark; explored terrain remains recorded after its light is lost. Hidden enemies and unscanned patches are omitted. A white outline follows the camera's view, including orbit and zoom. Click or drag inside the hex map to pan the camera without changing selection or issuing orders. The panel fits below the contextual commands when resizing.

## First expedition

1. Select the **Command Center** and press **Q**. A scan spends **120 electricity** from its capacitor and reveals the nearest active mineral and gas patches. Amber and green rings indicate approximate locations. A farther patch of the same kind remains hidden until the nearer one is depleted and another scan is paid for.
2. Select the jeep and **B** to send nearby infantry aboard. The first person to reach a free driver seat becomes the driver; the jeep has three additional passenger seats. Any infantry can drive. To choose a particular driver, select that person and right-click the empty vehicle before boarding the rest.
3. Right-click toward the mineral signal. Headlights illuminate the route. **U unloads passengers first**, leaving the driver and headlights operational. **U again unloads the driver**. The vehicle stays selected between presses.
4. Select a ground engineer. Near the mineral deposit, construct a **Generator [2]** and a **Spotlight [1]** within 32m of one another. The engineer must reach and work at each site. Costs come from the global bank; vehicles no longer deliver construction supplies to sites.
5. Right-click the mineral deposit with an engineer to gather. Engineers carry 20 resources and automatically transfer full batches into a nearby vehicle with free cargo space. A driver is not required for parked cargo access. With no nearby carrier, workers deliver to the nearest appropriate receiving structure and return to gather.
6. Protect the engineer until the jeep carries at least **30 freshly mined minerals**. Select the jeep and **H** to return to a home Mineral Depot. Depositing that shipment after establishing the powered outpost wins.
7. Gas works the same way, but must reach a **Gas Tank**. **J** sends a vehicle to the nearest appropriate receiving structure. A powered scanner provides approximate enemy contacts; a spotlight is still required to reveal those creatures for combat.

The scenario begins with two engineers, four marines, an unpiloted jeep, a Command Center, Mineral Depot, Gas Tank, Generator, Spotlight, Barracks, and Garage. Starting reserves are **400 minerals and 140 gas**, already deposited. Additional units can be produced immediately if affordable.

The starting base is at the center of a large hexagonal map, approximately 197m across, with three mineral patches and three gas patches. Connected, full-cell hexagonal cliff prisms form canyon passages and force detours. The eastern gas mesa is also made of raised hex tiles; its natural two-tile ramp is the ground approach.

## Vehicles and emergency light

- Jeep: **one driver + three passengers**, shared cargo capacity 160 minerals/gas.
- Scout: **one pilot, no passenger seats**, shared cargo capacity 40.
- Unpiloted vehicles cannot move or use their headlights. They retain a dim 4m emergency beacon.
- Boarding an abandoned vehicle fills its driver seat first and restores movement/headlights. Cargo remains intact.
- Drivers and passengers cannot shoot, gather, construct, or repair while aboard.
- Vehicle destruction ejects occupants with 30 damage; healthy crew can survive. Wrecks retain a fading emergency beacon for 30 seconds.
- The Command Center has a persistent 4m emergency light whenever it is alive, even without power or gas. Its normal large illumination requires power.
- Emergency beacons and infantry lamps help locate personnel and reveal very close threats, but **do not deter predators**. Operational headlights and spotlights provide protective light.
- Vehicles have no driving-fuel meter in this prototype. Gas pays for vehicle production and electrical generation.

## Resources and power

Minerals and gas can be spent anywhere once banked. Carried resources remain physical, unspendable cargo until deposited at the correct receiving structure. Engineers harvest both resources at one unit per 0.7 seconds. Deposits are finite.

The Command Center contributes emergency storage capacity of 100 minerals and 40 gas. Each completed Mineral Depot adds 400 mineral capacity; each Gas Tank adds 200 gas capacity. Losing storage reduces capacity but preserves already banked resources. Further deliveries wait until there is space. Mixed cargo travels to separate appropriate receivers.

Each generator supplies **12 power**. Generators and repeaters connect over **32m** links; other powered structures can connect to a source within **32m**. Distances are center-to-center; overlapping circles alone do not create a link. Separate grids cannot share spare generation. Generation burns **0.025 gas per served power per second**, so unused output consumes no gas. The starting base uses four power and burns 0.10 gas/second. Gas is drawn from the global bank.

The Command Center begins with a charged **120-electricity scan capacitor**. A successful scan empties it and has a 30-second cooldown. Charging uses up to 12 spare power per second from the Command Center's own network, after ordinary consumers are served; this extra load burns gas normally. The starting generator has eight spare power, so an empty capacitor takes 15 seconds and three gas to recharge. A scan cannot skip an active nearer patch. If there is nothing new eligible to reveal, it spends no charge. Charge does not bypass an unpowered Command Center.

Normal Command Center light and Spotlights use two power each; Turrets use three; Gates use one; Scanners use two. Storage and production buildings need no power in this pass. If overloaded, automatic priority preserves headquarters light, spotlights, and gates before turrets and scanners. Add generation or improve connectivity; there are no power-sector switches. The HUD shows served power, total capacity, requested demand, and fuel rate. A low-gas warning appears before shutdown.

Power links appear when an engineer or grid device is selected. Destroying a repeater can disconnect lights and defenses immediately. The Command Center emergency light remains available for recovery.

While placing any electrical structure, its 32m power-connection circle follows the cursor and all existing generator/repeater ranges are shown. Mint rings indicate online sources, amber indicates offline/disconnected sources, and blue indicates construction plans. A preview line identifies the prospective source; the construction panel reports missing links, planned connections, fuel outages, or capacity warnings. These overlays describe electrical reach; a Spotlight's illumination remains 13m. Leaving electrical placement hides the range overlays. Unpowered structures may still be placed for future expansion.

## Structures

Costs and timings are initial tuning values in `scripts/expedition_rules.gd`.

| Structure | Minerals | Gas | Purpose |
| --- | ---: | ---: | --- |
| Wall | 10 | 0 | Blocks movement and sight lines |
| Elevated Platform | 35 | 0 | One full hex tile raised 3m; supports units and structures |
| Ramp | 30 | 0 | Two adjacent hex tiles sloping from ground to the 3m level |
| Gate | 20 | 0 | Powered opening/closing; engineer can manually close during outage |
| Mineral Depot | 40 | 0 | Mineral receiving point; +400 global mineral capacity |
| Gas Tank | 40 | 0 | Gas receiving point; +200 global gas capacity |
| Generator | 80 | 25 | Supplies 12 power; consumes gas according to actual load |
| Repeater | 15 | 0 | Extends a grid through 32m links |
| Turret | 45 | 0 | Powered defense; engages illuminated enemies |
| Spotlight | 25 | 0 | Powered 13m area illumination |
| Command Center | — | — | Starting structure; cannot be constructed; destruction loses the mission |
| Barracks | 90 | 0 | Produces engineers, marines, and flamers |
| Garage | 120 | 30 | Produces unpiloted scouts and jeeps |
| Scanner | 60 | 20 | Powered 22m enemy detection; approximate tile contacts only |

Engineers must be on foot to construct or repair. Construction reserves the full global cost when ordered and takes 3–15 seconds of on-site work. Unfinished sites can be resumed by right-clicking with an engineer. Repairs spend one global mineral per eight health restored.

A powered selected Gate opens/closes with **O**. It will not close through an occupying unit. During an outage, **O** sends a nearby engineer to close it manually, or right-click the open gate with an engineer. Manual closure takes two seconds on site; opening always requires power.

Adjacent walls and gates connect automatically in all six hex directions, including corners and branches. Connections rebuild after placement or destruction, and their spans block movement and weapon sight lines. Platforms are tall hex tiles on the same grid. Place a ramp beside raised ground, with its high end toward that ground; **T** rotates through the six grid directions before placement. Ramps occupy two whole hex cells. Movement and terrain clicks follow their sloping surfaces; units cannot walk up sheer edges. Buildings may be placed on raised decks. The elevation system currently has ground and one raised level, without traversable space beneath decks.

## Units and production

| Unit | Minerals | Gas | Produced at |
| --- | ---: | ---: | --- |
| Engineer | 35 | 0 | Barracks |
| Marine | 45 | 0 | Barracks |
| Flamer | 65 | 20 | Barracks |
| Scout | 60 | 25 | Garage |
| Jeep | 100 | 35 | Garage |

Select a Barracks or Garage for its production commands. Costs are reserved when queued; up to five units can wait in a queue. **Cancel last** refunds the canceled reservation. Newly produced vehicles need a pilot. Marines attack visible enemies at range; flamers have a shorter-range area attack. Engineers cannot fight.

## Context controls

The HUD shows only commands applicable to selected units or structures. Ground engineers reveal construction and repair; vehicles reveal crew and cargo commands; infantry reveal boarding and escort; factories reveal production. Mixed selections combine their available actions. Deselecting engineers cancels construction/repair targeting.

| Input | Action |
| --- | --- |
| Left click / drag | Select one actor / a group |
| Shift + click/drag | Add to selection |
| Right click terrain | Move freely; cancel active placement |
| Right click vehicle with infantry | Board; first free driver seat is filled first |
| Right click deposit with engineer | Gather minerals or gas |
| Right click Depot/Tank with cargo carrier | Deliver matching cargo into global reserves |
| Right click unfinished/damaged building with engineer | Build/resume or repair |
| WASD / arrows / middle drag | Pan relative to the camera's current orientation |
| Alt + middle drag | Orbit around the camera's focus; vertical drag adjusts tilt (35°–75°) |
| Comma / period | Rotate left / right continuously |
| Home | Reset camera orientation, tilt, zoom, and starting framing |
| Wheel / F | Zoom / recenter headquarters |
| Minimap left click / drag | Pan the camera; preserve selection and current orders |
| Q with Command Center selected | Scan nearest active mineral/gas patches for 120 charged electricity |
| E / Expedition button | Arm expedition targeting; click a scanned resource patch; right click / Escape cancels |
| B | Board selected infantry, or nearby squad when a vehicle is selected |
| U | Unload passengers; press again for driver |
| L | Collect carried cargo from nearby on-foot personnel into selected vehicle |
| J / H | Deposit at nearest appropriate receiver / return cargo to home receiver |
| G | Selected infantry escort the nearest vehicle |
| R / X | Repair targeting / stop selected units |
| O | Operate selected gate or request manual closure |
| 1–0 with engineer selected | Spotlight, Generator, Repeater, Turret, Wall, Gate, Mineral Depot, Gas Tank, Barracks, Garage |
| Construction menu | Also contains Scanner, Elevated Platform and Ramp |
| T while placing | Rotate ramp / isolated fortification in 60° steps |
| 1–3 with Barracks selected | Engineer, Marine, Flamer |
| 1–2 with Garage selected | Scout, Jeep |
| Space / Escape | Pause / cancel placement and selection |

Only construction snaps to the hex grid. Movement uses continuous destinations, obstacle detours and smoothed paths; headings, motion, and visible light cones update every render frame. Combat, orders, fuel, and mission logic run at 10 Hz.

Selection uses an on-demand GPU ID render of model geometry, captured on mouse-down. Name labels and selection helpers do not intercept clicks. When no model is hit, orders use a terrain physics raycast. Selected units show a small line to their destination or current visible target. Gentle spacing helps units settle apart and pass approaching units; they can still move through each other, and parked unpiloted vehicles stay fixed.

Friendly units and already visible creatures receive a silhouette only where terrain or structures cover them. A separate GPU depth pass excludes actors, preventing body parts from highlighting one another. Hidden creatures and boarded personnel never receive silhouettes; name labels do not participate in either depth pass.

Select engineers and optional infantry/jeeps, then press **E** or click **Expedition** and click a scanned resource patch to start a repeating gathering expedition. Right-click or Escape cancels targeting. Ordinary right-clicks never start resource expeditions.

Without vehicles, engineers gather into their own packs, return to home receivers when a pack fills, deposit, and repeat; infantry escort them and patrol while they work. A lone engineer can run this order. With a jeep, crew board, travel, unload passengers, gather while infantry patrol, regroup when vehicle cargo is full, deposit at home, and repeat until exhausted. Packed jeeps use their existing crews without requiring hidden passengers to be selected. Multiple selected jeeps split the pooled crew into independent convoys, each requiring a driver and a separate working engineer; stopping one convoy leaves the others running. Each jeep gets a driver and engineer before remaining crew are distributed among vehicles. Insufficient crew prevents starting the expedition.

Resource guards patrol fixed perimeter waypoints, pause briefly to watch outward, then walk to the next point. They reserve separate watch points and skip blocked positions instead of continually chasing a moving circular target.

Convoys deposit vehicle and carried passenger cargo without unloading. Drivers and passengers keep their seats at the depot and during the next outbound trip; workers dismount at the work site.

With mixed jeep/infantry selections, ordinary right-clicking a structure still sends engineers to repair or finish construction while infantry defend it; a terrain destination transports the group without unloading its passengers. Existing riders stay aboard during terrain orders.

Driver preference is Marine → Flamer → Engineer; passenger preference is Engineer → Marine → Flamer. Overflow units walk as escorts. Jeeps match their slowest walking escort's speed, including ordinary escort orders. Direct orders detach individual units from coordinated tasks; stopping, redirecting, or manually unloading the jeep cancels its group task. Detached units never rejoin automatically. Gathering preserves carried cargo and waits if storage is full or the receiving structure is missing.

After finishing construction or repairs, engineers immediately look for the nearest reachable unfinished or damaged structure within 14 meters of the completed job. They continue from job to job while nearby work remains. With no available work, engineers and maintenance crews clear their movement orders and stay where they finished; they do not automatically return to HQ or board a vehicle. A defend order on an initially undamaged structure stays in place.

Camera orbit remains available while paused. Rotation preserves the current focus point, and panning and mouse orders follow the rotated view. F recenters headquarters while preserving the chosen orientation; Home restores the complete initial view.

## Predators and recovery

Creatures lurk, probe, stage, assault, and retreat. They remember local sightings for 35 seconds, respond to damage, and prefer avoiding operational light while lurking or regrouping. Emergency beacons do not create safe zones. Hidden scanner contacts do not reveal creature models or allow friendly weapons to target them. A powered Scanner can report broad staging activity without an exact attack announcement.

The first 55 seconds remain a grace period. Establishing the illuminated mineral perimeter attracts a small additional group. The Command Center's destruction always defeats the mission. Losing a vehicle permits crew rescue and replacement; losing engineers is recoverable through the Barracks when funds or incoming cargo can support recruitment. The mission ends when no viable crew/replacement route remains.

## Source and validation

- `scripts/expedition_rules.gd`: structure/unit costs, health, production and build times.
- `scripts/expedition_economy.gd`: global currencies, capacity, purchases and deposits.
- `scripts/expedition_power.gd`: local grids, capacity, automatic priorities and gas burn.
- `scripts/expedition.gd`: scenario, orders, gathering, production, crew, combat and contextual HUD.
- `scripts/expedition_unit.gd`: vehicles/infantry, seats, cargo, smooth movement and headlights.
- `scripts/expedition_structure.gd`: structures, powered presentation and gates.
- `scripts/gpu_picker.gd`: geometry-only GPU selection and headless triangle validation.
- `scripts/unit_focus_overlay.gd`: selected-unit destination and target lines.
- `scripts/soft_unit_spacing.gd`: gentle separation without solid unit collisions.
- `scripts/complex_commands.gd`: coordinated gathering, transport, structure support and crew assignment.
- `scripts/foot_expeditions.gd`: on-foot gathering trips, carrying, deposits and infantry guards.
- `scripts/expedition_patrol.gd`: shared perimeter patrols with stable paths and watch pauses.
- `scripts/expedition_terrain.gd`: hex map boundaries, raised-cell heights and two-cell ramp geometry.
- `scripts/occluded_units.gd`: world-only occlusion depth and visibility-gated silhouettes.
- `scripts/minimap.gd`: explored terrain, visibility-safe markers and camera navigation.
- `scripts/illumination.gd`: gameplay illumination versus creature deterrence.
- `scripts/predator*.gd`: creatures and observed-information group behavior.

```powershell
$config = Import-PowerShellDataFile .\tools\assetforge.local.psd1
& $config.GodotExecutable --headless --path . --script res://tools/test-prototype.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-context-hud.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-window-resize.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-camera.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-power-placement.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-unit-spacing.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-complex-commands.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-expedition-rosters.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-expedition-patrol.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-terrain-world.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-minimap.gd
& $config.GodotExecutable --headless --path . --script res://tools/test-engineer-maintenance.gd
& $config.GodotExecutable --path . --script res://tools/test-occluded-units.gd # Rendered self-occlusion regression
& $config.GodotExecutable --headless --path . --script res://tools/test-picking.gd
& $config.GodotExecutable --path . --script res://tools/test-picking.gd # Actual GPU readback
```

The integration suite exercises actual boarding, staged unloading, pilot restrictions, emergency lighting, crew survival, global purchases and deposits, storage loss, gas harvesting, grid outages, scanner visibility separation, manual gates, recruitment, and a complete expedition that returns a real mined shipment.

Rendered previews:

```powershell
& $config.GodotExecutable --path . --script res://tools/preview-prototype.gd -- --outpost
& $config.GodotExecutable --path . --script res://tools/preview-prototype.gd -- --emergency
```

Other preview flags: `--briefing`, `--engineer`, `--headlights`, `--convoy`, `--terrain`, `--fortifications`, and `--live` for a six-second live runtime sample. Terrain/fortification previews use full-map lighting for visual inspection. Images/logs remain in ignored `art_source/.build/`.

Asset Forge building models are reused; troop, vehicle, gate and wall geometry remains placeholder. Regenerate models only through `tools/build-model.ps1`; see `tools/README-models.md`. The documents under `docs/` preserve earlier design specifications; this README and `expedition_rules.gd` describe the current iteration.

## Current limits

Three mineral fields, three gas fields, one creature type, two terrain levels, and first-pass balance. No save/load, campaign, research tree, separate vehicle fuel, or full crowd collision. Gameplay light does not yet account for wall shadows, although navigation and weapon sight lines respect obstacles. Construction has no salvage/cancellation refund yet. Production cancellation refunds its cost. Vehicles can be re-crewed and recovered while intact; destroyed hulls are temporary visual wrecks rather than repairable units. Graphics, animations, and audio remain placeholders.

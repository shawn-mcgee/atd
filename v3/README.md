# Design and mechanics

[Play the browser alpha](https://shawn-mcgee.github.io/atd/) | [Controls](docs/controls.md)

### Run the current foundation

A runnable Godot browser foundation is now implemented. It includes the 3D scene/camera, initial simulation and economy, and built-in Godot WebRTC transport. It is **not the complete alpha**. See [implementation status and controls](docs/implementation-status.md) for exact coverage and remaining systems.

```sh
npm ci
python tools/setup-engine.py
npm run export:web
npm run serve
```

Open `http://127.0.0.1:8080/`. Run `npm test` for headless simulation checks and `npm run test:browser` for browser/WebRTC checks. The editor version is pinned in `.godot-version`; the setup helper downloads its portable binary and required web templates into ignored `.tools/`.

### Browser alpha

The first playable is an alpha distributed primarily through the **browser** targeting all confirmed systems in this document, including single player, up to five players in player-hosted Godot WebRTC multiplayer, the complete current roster and economy, complex mining expeditions, and optional player-controlled Lightless. The Godot editor/native Windows/Linux x86_64 runtime also supports network play; downloadable desktop exports are deferred. This is a substantial RTS implementation and should be built through integrated milestones.

The **extraction boss is excluded from the first version**. Unique commander differences, additional undesigned upgrade effects, and between-match purchases remain later design work. The initial Fabricator content is one armor upgrade for each specialization: Engineer, Marine, Flamer, and Lancer.

- [Browser-alpha scope, implementation choices, and acceptance criteria](docs/first-playable.md)
- [Detailed mining expedition coordination](docs/mining-expeditions.md)
- [Implemented vehicle production, crew, cargo, and excavation](docs/vehicles.md)
- [Combat and work feedback: visuals, sound, and tuning](docs/feedback.md)
- [Developer guide and system extension points](docs/developer-guide.md)
- [Searchable configuration reference](docs/config-reference.md)
- [Editor startup troubleshooting and script UID checks](docs/editor-troubleshooting.md)
- [Prototype values and configuration contract](docs/prototype-settings.md)
- [Editable prototype settings](config/prototype.json)
- [Godot engine, platform, and distribution plan](docs/engine-and-distribution.md)
- [Player-hosted networking](docs/networking.md)
- [Replayable single-player missions](docs/missions.md)
- [Low-cost multiplayer options and recommendation](docs/multiplayer-options.md)
- [Art direction, presentation, and asset provenance](docs/art-direction.md)

The JSON contains confirmed values and explicitly proposed tuning defaults for previously unresolved values. Implemented systems load those settings; remaining definitions guide subsequent milestones. The engine is **Godot**, using **3D presentation** and targeting the **browser for the alpha**. Deployment targets are **GitHub Pages and itch.io**. Multiplayer is **player-hosted through Godot WebRTC, the custom coordinator, and Metered TURN**. Native Windows/Linux exports and downloads are deferred; macOS remains outside the test scope. The current foundation is runnable, while broader Internet connectivity acceptance, the 3D asset pipeline, persistence, and the remaining gameplay systems still need implementation and acceptance testing.

### Narrative

You are sent to the planet Erebus to command a small band of expeditionary forces tasked with killing the Medusa and recovering Nacre from its remains. Establish a foothold beneath the planet's dark skies, secure resources, and extend a network of powered outposts into increasingly hostile territory. Every advance brings the expedition closer to its objective and farther from the safety of its orbital tether. Bring the harvested Nacre back to your Anchor and withstand the Lightless assault while you extract.

### Mechanics

#### Time and unit control

The game is a real-time strategy game. Players control individual Solar Commonwealth units, issuing commands while the simulation advances.

In single player, the player can pause the simulation and issue commands while paused. The player can also change game speed at any time. In multiplayer, game speed must be decided before the match begins.

If the multiplayer host leaves or its connection is lost, the match ends for everyone once that loss is detected. There is no host migration, reconnection recovery, or resuming the ended match. A host losing its Anchor can continue hosting while connected; gameplay elimination is separate from leaving.

#### Camera

Use a StarCraft II-style perspective RTS camera with an elevated default viewing angle, bounded wheel zoom, and temporary left/right rotation that returns to the default orientation on release. Support edge scrolling, keyboard panning, middle-mouse dragging, and wheel zoom. Camera navigation remains available while paused and does not affect unit vision or fog of war.

The proposed camera values and input behavior are documented in the [engine and distribution plan](docs/engine-and-distribution.md) and configurable under `camera` in [prototype.json](config/prototype.json). The numeric defaults are this project's initial tuning, not verified StarCraft II constants.

#### Participants and factions

Matches support up to **five players**. The host may assign exactly one of those slots to the Lightless; all remaining players control Solar Commonwealth factions. If no slot is assigned, the CPU controls the Lightless. Solo **Play as Lightless** adds a Commonwealth AI opponent.

In multiplayer, players are hostile to one another. They compete for access to the Medusa's remains and the Nacre harvested there.

The three Commonwealth factions currently use the same mechanics. Their only meaningful difference at present is faction color:

| Faction | Color |
| --- | --- |
| Atlas Mining Company | Blue |
| Interplanetary Mining Commission | Green |
| Frontier Syndicate / Pirates | Red |

Mechanical differences between the player factions are planned but have not yet been defined here.

Players will choose from additional commanders within each faction. Commanders are intended to have unique units and/or abilities, with the roster and those differences to be defined later. Commander selection and colors for multiple players from the same faction remain to be specified.

#### Mission setup

Each mission takes place on a randomly generated map. The Lightless begin with one Medusa, **five Scavengers**, and **100 stored Chyme**. The initial Gloom radius begins fully covered. The Medusa passively generates Chyme, providing income for producing units and structures. The proposed preset covers the Medusa's full eight-tile Gloom extension and generates one Chyme per second; both values are configurable.

Player-controlled Lightless start with **one Father** in addition to the normal colony, allowing immediate recruitment and coordination.

Each player faction begins with:

- One Anchor.
- One Engineer.
- One Marine.

The Medusa starts at one randomly selected map corner. That corner is reserved for the Lightless; players occupy separate corners chosen to maximize separation from one another. All starting positions use the configured boundary inset, provisionally **about six tiles**. The deterministic placement and tie-breaking algorithm is documented in the first-playable specification.

The Medusa remains hidden until scouted. Its initial Scavengers and Gloom surround its chosen corner, and its remains produce Nacre at that location after death.

The Anchor provides **100 starting Ore** and **100 starting Gas**. It contributes the following ordinary-resource capacities:

| Resource | Capacity provided by the Anchor |
| --- | ---: |
| Ore | 100 |
| Gas | 100 |
| Alloy | 10 |
| Polymer | 10 |
| Crystal | 10 |

Only one Anchor may exist per player. Its destruction eliminates that player, so the starting Anchor cannot be replaced after defeat. The Anchor also has the separate 1,000-Nacre capacity described under extraction. Starting Ore and Gas each fill their initial capacity.

The Anchor illuminates three tiles beyond its footprint and provides vision five tiles beyond its footprint in the proposed preset. These ranges are configurable; its personal healing applies only to biological units.

#### Objective and extraction

The player's objective is to kill the Medusa, harvest Nacre from its remains, transport that Nacre to their Anchor, and survive extraction.

1. **Kill the Medusa.** Its death sets all Lightless to Attack stance. They receive a massive injection of Chyme, and all Wombs receive a permanent spawn-rate buff. Fathers can still override the Attack stance for units they currently recruit, but only while those units remain recruited.
2. **Establish Nacre harvesting.** Mine the Medusa's remains directly, or build a powered Extractor on top of the corpse to improve extraction efficiency. The corpse has an infinite Nacre supply. The first playable keeps harvesting available during extraction; the later boss-enabled version ends harvesting when the boss emerges.
3. **Transport Nacre to the Anchor.** Harvested Nacre must be physically carried back to the player's Anchor. It cannot be deposited in a Depot. Nacre held at the harvesting site or in transit has not yet been delivered to the Anchor.
4. **Choose when to extract.** The Anchor can store up to **1,000 Nacre**. Once it holds at least **500 Nacre**, the player can select the Anchor and choose to begin extraction. Reaching the threshold makes extraction available; the player initiates it manually.
5. **Survive the extraction assault.** Beginning extraction triggers a full Lightless assault. The Anchor must survive the **90-second** extraction period; preserving other units or structures is not an extraction requirement. The first playable uses ordinary Lightless for this assault and does not spawn a boss.

Nacre harvesting and delivery continue during the 90-second countdown in the first playable, allowing the player to increase the amount held at the Anchor up to its capacity. The harvesting cutoff below belongs to the later boss-enabled version.

**Extraction boss: later version**

When the boss feature is implemented and enabled, only the first extraction summons one. It erupts from the Medusa's remains, destroys nearby structures, and permanently ends Nacre harvesting. No emergence, destruction, or harvesting cutoff occurs while the feature is disabled. The affected area remains part of the deferred boss design.

If the first extracting Anchor is destroyed, the boss can change targets. Later extractions do not summon additional bosses. Retargeting priorities remain to be specified.

The boss's identity, appearance, attacks, movement, and detailed behavior are undecided and deferred to a later version. Its emergence and harvesting cutoff are defined here, without assigning a combat design.

**Anchor survival and defeat**

If the Anchor is destroyed, the player loses. This applies throughout the match, including during extraction.

An eliminated player loses control of their remaining assets, which retain their last orders and combat stances. Elimination does not force neutral stance or cancel existing commands. Vehicles automatically unload all occupants, including their drivers. Once empty, vehicles are subject to the normal driver requirements and commandeering rules. The assets are not automatically destroyed on elimination.

**Multiplayer harvesting**

No faction can claim ownership of the defeated Medusa. An Extractor physically prevents direct mining underneath it. If an enemy Extractor occupies the corpse, it must be destroyed before workers can mine there or a replacement Extractor can be built.

Multiple players can begin extraction, but the first to complete it wins. That successful extraction ends the multiplayer match for everyone; other players do not continue playing out their own countdowns.

**Multiplayer elimination victory**

The last surviving Commonwealth player also wins immediately when all opposing players have been eliminated. Destroying an opponent's Anchor eliminates that player. Elimination victory does not require 500 Nacre, killing the Medusa, or completing an extraction countdown.

An elimination winner keeps the Nacre already delivered to their Anchor. Nacre still in transit or elsewhere outside the Anchor is not included in that reward.

**Progression between matches**

Nacre is a currency the player may choose to spend between matches. Collecting beyond the minimum 500 provides more of that currency on extraction. Its purchases, progression effects, and faction-specific or shared account rules are undecided; no particular between-match benefit is defined yet.

#### Map, distance, and placement

The map is a large hexagon composed of pointy-top hexagonal tiles. Its size is configurable, and an impassable wall encloses the map boundary. The basic unit of distance is *tiles*: one tile of distance is the inner diameter of a hexagon, measured edge to opposite edge.

Structure placement is aligned to the hex grid. Some structures occupy a footprint spanning multiple hexes. Terrain such as cliffs occupies an entire tile and blocks construction; existing structures also block construction.

Unit movement is continuous rather than a sequence of discrete tile occupations. Multiple units can share a tile, and units steer to avoid bunching up. Movement collision is calculated separately from the placement grid, using the collision shapes of structures.

Cliffs are impassable until cleared. There are currently no elevation levels or ramps. A Father's floating movement follows the same obstacle restrictions as ground units.

**Resource fields and reachability**

Deposits spawn in fields containing **one, three, or seven patches**. A three-patch field forms a triangle of hexes meeting at one shared vertex. A seven-patch field occupies a center hex and all six neighboring hexes.

Each starting Anchor has a Gas field of **one patch** and an Ore field of **three patches**, within the Anchor's vision range and guaranteed accessible without an Excavator.

Other deposits can occur beneath cliffs or other obstructions. Map generation must make the Medusa reachable, but does not need to make every resource reachable.

**Gate operation**

Players can manually open, close, and lock Gates. A lock prevents units from automatically opening or closing the Gate. Units should operate an unlocked Gate only when pathfinding through it, not merely because they are nearby.

Closed Gates block weapon fire, illumination, and vision. Open Gates permit illumination and vision to propagate. The proposed implementation permits physical enemy passage through an open Gate, prevents enemies from operating it automatically, and waits for occupancy to clear before closing. Timings are configurable; see the first-playable specification.

#### Resources, storage, and transport

**Global supply**

Commonwealth resources become accessible through a global supply after delivery to an Anchor or a Depot. Material at a resource patch, inside a production facility's buffer, or carried by a unit has not yet been added to that supply.

Global storage capacity is capped. Players expand capacity for a resource by building additional Depots of the relevant type. Nacre has separate delivery restrictions: it must be carried to the Anchor and cannot be deposited in a Depot. The Anchor's Nacre capacity is 1,000.

Any Depot accepts any ordinary resource type, regardless of its configuration. The Depot's configured type determines which resource's global capacity it increases, not which resources can be delivered there.

**Immediate costs and refunds**

Orders and blueprints are paid for immediately: placing one deducts its cost from the global supply. Beginning work does not charge the cost a second time.

The relevant action determines how long cancellation remains refundable. Where a refund is permitted, it can raise global supply above current capacity. Existing rules still prevent newly delivered resources from entering supply without available capacity.

**Carrying resources**

Operators, Engineers, Rangers, and Excavators can carry resources, including Nacre. Carriers have fixed carrying capacities. One unit of any resource consumes one cargo capacity, and carriers can mix resource types within that capacity. If a carrier is killed, all resources it was carrying are lost permanently; they are not dropped for recovery.

Workers can load nearby vehicles with resources to increase the amount transported back to a Depot. Units and vehicles deposit cargo instantly when within range of an eligible Depot or Anchor, subject to available global storage capacity.

**Depot configuration**

Depot blueprints default to Ore, then remember the player's last selected capacity type for subsequent placements. Selecting a type is optional: the player may place the blueprint immediately. After choosing Depot in the construction catalogue, five resource buttons offer Ore, Gas, Alloy, Polymer, and Crystal with contextual hotkeys. The type can also be changed while the site remains an unstarted blueprint. Completed Depot reconfiguration uses the same five-button interface.

An existing Depot can be reconfigured only if removing its current capacity would leave capacity greater than or equal to the current global supply of that resource. For example, reducing capacity from 800 to 600 is permitted when the stored supply is 500.

Reconfiguration immediately removes the Depot's old capacity. After a short configuration cooldown, its new capacity becomes available. The old and new capacities do not overlap during the cooldown.

If a Depot is destroyed, stored resources are retained even when the loss leaves supply above capacity. New resources cannot enter the global supply without available capacity; existing resources are not discarded to enforce the reduced limit.

**Deposits and Extractors**

Ore and Gas deposits are finite but extremely rich. The Medusa's remains provide an infinite Nacre supply, including during extraction in the first playable. In the later boss-enabled version, the boss's emergence permanently ends harvesting.

Extractors handle Ore, Gas, and Nacre through the same process:

1. Build an Extractor on top of the resource source.
2. Supply the Extractor with power.
3. The Extractor fills its internal resource buffer.
4. Operators or Engineers collect the material from the buffer for transport and delivery.

Extractors improve extraction efficiency, but are not strictly required for mining. Workers can mine directly while adjacent to a resource patch, including the Medusa's remains for Nacre.

**Excavator clearing**

Excavators are specialized drills that destroy terrain such as cliffs. Destroying a cliff places raw resources directly into the Excavator's cargo. If its cargo is already full, those resources are lost.

The cleared cliff leaves aesthetic rubble that blocks neither movement nor construction. The proposed preset yields 20 Ore directly into the Excavator, accepts only what fits, and loses any excess. Cliff health and yield are configurable.

**Passive production and collection**

Extractors, Foundries, Refineries, and Synthesizers passively fill internal output buffers. Operators or Engineers collect their output; a worker does not need to remain assigned for passive production to progress. Workers must be adjacent to a facility to collect its output, or adjacent to a resource patch to mine directly. Engineers mine and collect more resource items per cycle than Operators. This advantage concerns worker throughput rather than increasing a facility's passive production rate.

Foundries, Refineries, and Synthesizers draw their production inputs directly from the global supply. Their inputs do not require physical delivery to the facility.

| Facility | Inputs | Output |
| --- | --- | --- |
| Foundry | Ore | Alloy |
| Refinery | Gas | Polymer |
| Synthesizer | Ore and Gas | Crystal |

Recipe quantities and batch sizes are configured in `economy.recipes`. They consume and produce whole-number resource amounts. The preset uses single-resource output buffers and reserves space for an entire batch before starting; input costs are deducted atomically from global supply.

These facilities consume power only while producing resources. If the output buffer is full, or a processing facility cannot retrieve enough inputs from global supply to craft the next item, production pauses and the facility does not consume power.

For powered production structures, losing power pauses production and restores it when power returns, retaining progress. Kit production, vehicle production, and Fabricator upgrade work follow this rule where their structures require power. These structures consume power only while actively producing or progressing work.

#### Hauling orders

Assigning a worker to a resource or facility creates a repeating collect-and-deliver loop:

1. **Gather:** Mine the assigned resource or collect the assigned facility's output.
2. **Choose a destination:** When gathering is finished and the worker begins its delivery trip, select the nearest eligible Anchor or Depot. Nacre must be delivered to the Anchor.
3. **Travel:** Carry the gathered resources to the destination. If the destination is destroyed, select a new destination.
4. **Deposit:** Once in range, instantly deposit as much cargo as available storage capacity permits.
5. **Wait if necessary:** If cargo cannot be fully deposited, wait at the destination for capacity to become available.
6. **Repeat:** After completing delivery, return to the assigned gathering task.

**When gathering ends**

A worker leaves to deliver when its cargo is full, its resource patch is depleted, or its assigned structure is not producing. A structure may stop producing because it lacks power or sufficient inputs from global supply, for example. These conditions allow a worker to deliver a partial load.

If a facility's buffer empties while the facility remains operational, the worker waits for more output to appear instead of leaving immediately with a partial load.

**Destination selection and redirection**

The delivery destination is selected when the worker leaves to deposit, rather than fixed when the gathering assignment is first issued. A unit with cargo can also be redirected to a Depot or Anchor to deposit its resources. If the destination lacks capacity for all of the cargo, the unit deposits what it can and waits with the remainder until capacity becomes available.

Vehicle-assisted hauling belongs to the complex-command framework below. The detailed allocation, loading, travel, and recovery rules are documented in [Mining expeditions](docs/mining-expeditions.md).

#### Complex commands and expeditions

A complex command intelligently organizes selected units to perform a specific task together. It accommodates arbitrary numbers and combinations of units with few minimum requirements, assigning useful behavior according to the participating units' roles.

**Issuing a mining command**

Select a group of units, press **M** for *mine*, and select a resource patch or Extractor. This forms a mining expedition. The selection can include Operators, Engineers, military units, and vehicles such as Rangers.

A mining command requires at least one Operator or Engineer when issued. Vehicles and military escorts are not required. When included, military units escort, patrol, and defend intelligently rather than needing separate orders for every stage of the trip.

**First-playable coordination**

Prefer Operators as drivers and keep Engineers in Ranger passenger seats. Preserve occupied driver seats and allocate at least one available driver per participating vehicle where personnel allow, without consuming the last available gatherer. Remaining military units escort the convoy and defend the worksite. On arrival, workers disembark while drivers remain aboard, keeping vehicles lit and operational.

Workers load nearby vehicle cargo and then their personal cargo. The group regroups, delivers together, unloads workers to deposit personal cargo, and repeats. Nacre requires the Anchor; ordinary cargo can use any Depot. Personal and vehicle cargo remain separate, and no passenger is treated as a resource slot.

The full proposed algorithm, role priorities, deterministic tie-breaking, boarding and departure conditions, full-storage waits, depleted-source search, and handling of casualties or interrupted participants are in [Mining expeditions](docs/mining-expeditions.md). Timings, radii, role preferences, and capacities live in [prototype.json](config/prototype.json).

A manually interrupted participant leaves the command and does not automatically rejoin. The command remains alive after all workers are lost, with remaining military units defending and retained drivers providing light. It reports the missing workers rather than silently recruiting unrelated personnel.

#### Personnel, equipment, and production

**Operators and specialization**

Operators are the base human unit. Structures can produce kits that upgrade an Operator into a Marine, Flamer, Lancer, or Engineer. Operators share Engineers' general gathering and logistics capabilities, but cannot build or repair structures. Engineers also provide greater efficiency when mining and operating machinery, and are required to work Fabricator upgrades.

Commonwealth population is currently unlimited.

**Operator production**

Anchors and Cradles produce Operators through production queues. The Operator resource cost is the same at either structure, but a Cradle calls Operators down faster than an Anchor. Players can request Operators directly or through another structure's personnel requests.

Operator production uses a queue separate from the Engineer-kit queue. Visually, Operators and Engineer kits are produced from different sides of the Anchor or Cradle.

The proposed preset charges 10 Ore and 5 Gas per Operator, with 12-second Anchor production and 6-second Cradle production. Direct orders and personnel requests share the Operator queue in arrival order. Values live in `personnel`.

**Requesting personnel**

Automatic Operator requests use one global toggle per player, available when a structure is selected. When enabled, the cost of each newly ordered kit or vehicle includes a new Operator at every facility, including facilities built later. Changing the toggle leaves existing queues unchanged. Personnel-source assignments remain specific to each production structure.

When a structure such as an Armory or Factory is placed, it selects the nearest Anchor or Cradle as its personnel source by default. The player can change this assignment by selecting the production structure and choosing a different personnel source. The structure requests Operators from its configured source.

**Kit queues and specialization**

| Kit | Production structures |
| --- | --- |
| Engineer | Anchor or Cradle |
| Marine | Armory |
| Flamer | Armory |
| Lancer | Armory |

Different kits share one kit queue per structure, with a maximum of **five kits**, including completed kits awaiting collection. For example, three completed kits and two unfinished orders fill the queue. The player cannot reorder it. Only one kit is assembled at a time, in queue order. Completed kits do not block assembly of already queued orders: once one finishes, the structure begins assembling the next.

Kits can be canceled at any time, including discarding a completed kit. Only kits whose production has not started receive a full refund; partially assembled and completed kits receive no refund.

Kits can be queued at the structures that produce them. Operators assigned to a kit-producing structure collect the finished kit at the top of its queue. If the kit is unfinished, the Operator waits for completion. If no kit is available, an assigned Operator waits for one to become available.

Queued kits exist in an internal buffer. They cannot be stored separately, transported, or reused. Applying a kit is a one-way transformation of an Operator into its specialization. Specialized units cannot change their specialization.

**Production costs and losses**

Queuing a production request immediately deducts its resource cost. Once production or construction progress begins, the cost is no longer refundable. Destroying a production structure does not refund its orders, including unstarted orders. Completed kits inside the destroyed structure are lost.

#### Fabricator upgrades

The Fabricator offers a list of upgrades that can be purchased for a resource cost. Purchasing an upgrade does not complete it automatically: one or more Engineers must work at the Fabricator to finish the task.

Upgrade work progresses similarly to construction. Multiple Engineers can work together to increase completion speed. Operators do not perform this work.

**Costs, queues, and progress**

Purchasing an upgrade immediately deducts its resource cost. Queued upgrades that have not begun can be canceled for a full refund. Once an Engineer begins work and makes progress, cancellation is no longer refundable. The active upgrade can still be canceled, but receives no refund if any progress has been made.

Unfinished progress persists if Engineers leave. Destroying the Fabricator destroys its queue and unfinished progress without refunding any orders, including unstarted upgrades.

**Scope and persistence**

Completed Fabricator upgrades last for the remainder of the match. An upgrade applies to all of the player's units and structures of its corresponding type, including existing instances and those created later. Destroying the Fabricator does not remove completed upgrades.

The initial catalogue has one armor upgrade each for Engineer, Marine, Flamer, and Lancer. Each adds 1 armor, costs 10 Alloy and 5 Polymer, and takes 20 Engineer-seconds in the proposed preset. Each specialization upgrade can be purchased only once per player and applies to existing and future units of that specialization. Multiple Engineers add work linearly; one upgrade is worked per Fabricator at a time. See `upgrades.fabricatorArmor` for configurable values.

#### Vehicles, drivers, and passengers

Every vehicle requires a driver to move. Operators, Engineers, Marines, Flamers, and Lancers can drive vehicles. The first unit to enter an empty vehicle becomes its driver.

If automatic personnel requests are unavailable or not enabled, the Factory still produces the vehicle. It cannot act or move until the player assigns a driver.

**Seating and cargo**

Passenger capacity and resource cargo capacity are separate. Occupied vehicles can accept additional friendly passengers while seats remain available.

| Vehicle | Drivers | Passengers | Resource cargo |
| --- | ---: | ---: | --- |
| Scout | 1 | 1 | None |
| Ranger | 1 | 3 | Moderate capacity |
| Excavator | 1 | 0 | Large capacity |
| Reaper, Cremator, Javelin | 1 | 0 | None |

The proposed cargo capacities are 100 for Rangers and 250 for Excavators, configurable per unit. Operators and Engineers each carry 20; Engineers collect or mine two items per cycle to an Operator's one.

Vehicle lighting and vision are active only while a driver is present. An empty vehicle does not illuminate or reveal its surroundings.

**Unloading**

Pressing a vehicle's unload button unloads its passengers first. Pressing unload when the vehicle contains only a driver also unloads the driver.

**Commandeering**

Enemy units can commandeer an empty vehicle by entering it as the driver. Leaving a vehicle empty therefore allows an opposing player to take control of it.

**Combat and vehicle destruction**

Passengers and drivers cannot be targeted separately while inside a vehicle. Passengers generally cannot fire from inside, with the Scout as an exception: its passenger can make ranged attacks using their normal weapon and the Scout's vision. Destroying a vehicle unloads its passengers and driver with their current health. Driver specialization and driver skills do not exist at present.

#### Construction

Engineers can place any ordinary Commonwealth structure if the player can afford its material cost; there are no structure-unlock prerequisites. The unique starting Anchor is limited to one per player. Placement still requires the entire footprint to have previously been revealed, including every tile occupied by a structure spanning multiple hexes. Current vision is not required merely to place the blueprint.

Placing a blueprint immediately deducts its resource cost. Canceling it before construction begins refunds that cost. Once a blueprint has been placed, the Engineer follows this validation sequence:

1. **Approach the site.** Pathfind to the nearest reachable tile.
2. **Check construction range.** If the blueprint is too far from that reachable position, cancel it because it cannot be reached.
3. **Check the footprint.** If structures or terrain occupy the footprint, cancel the blueprint.
4. **Check unit occupancy.** Move friendly units out of the way. If enemy units occupy the footprint, cancel the blueprint.

This sequence checks conditions when the Engineer reaches the site, including obstructions that may not have been visible when the blueprint was placed.

**Construction progress and resource commitment**

After validation, the Engineer works over time to construct the building. Multiple Engineers can work on the same structure to accelerate construction.

Beginning construction ends refund eligibility; its cost was already deducted when the blueprint was placed. Canceling construction after work has begun provides no refund. If the partially constructed building is destroyed, those resources are lost.

Construction progress is represented by the partially constructed building's health. Engineer work advances construction by increasing that health. Damage reduces health and therefore sets construction progress back. When the building reaches 100% health, it becomes the finished structure.

A new construction site starts with **1 health** by default. This starting value must remain configurable rather than fixed in the implementation.

Construction progress persists when Engineers leave or die. The Anchor does not heal structures, including unfinished buildings. In the proposed preset, each Engineer adds 20 construction health per second and rates add linearly. Repair orders on unfinished buildings use construction work without a second repair charge. Rates and interaction ranges are configurable.

Idle Engineers automatically help nearby friendly construction before seeking damaged structures to repair. The default search reaches six tiles beyond the structure footprint and runs at half-second intervals. Automatic work uses normal construction and Ore-funded repair rules, skips unreachable sites, and yields to player orders, including queued orders.

Wall placement supports click-and-drag lines. Releasing commits affordable, revealed, unobstructed cells and queues them for the selected Engineer. Shift appends the line and keeps wall placement active; Escape or right click cancels before commitment. Blocked cells are skipped, and the ordinary order-queue limit applies. Walls fill their hexagons as solid raised hexagonal prisms.

#### Power generation and distribution

**Sources and electrical footprints**

Structures that produce, transmit, or consume power have electrical footprints. Two structures can connect when their electrical footprints overlap. For most consuming structures, the electrical footprint matches the build footprint.

Anchors, Generators, and Reactors produce power. Producers have electrical footprints larger than their build footprints, usually extending a couple of tiles around them. Relays transmit power through much larger electrical footprints, extending networks over large areas without generating power themselves.

Footprint overlap connects producers, consumers, and Relays into networks. When networks connect, their capacity and consumption combine into one larger network. Walls and cliffs do not obstruct electrical connections.

Relays consume no power and retain their electrical footprint during a blackout. They transmit existing supply and cannot generate it. Switching off or destroying a Relay disconnects its footprint; structures connected exclusively through it lose their source.

The starting Anchor supplies 4 power. A Floodlight consumes 1 and each turret consumes at least 3, allowing one Floodlight and one turret on the starting grid. A powered Floodlight has eight tiles of vision beyond its footprint; when switched off or unpowered, that shrinks to one tile and its illumination stops. Previously explored ground remains remembered.

**Capacity and consumption**

Each power-producing structure contributes a whole-number capacity to its grid. Each structure using power consumes a whole-number amount. When demand exceeds capacity, the grid enters a brownout or blackout depending on the degree of overload.

Idle production facilities remain connected while consuming no power. Most powered structures can be switched on or off, including Relays.

Enabled defenses passively consume power at all times, including while idle; their demand is not limited to periods of targeting or firing.

**Brownouts**

A moderate overload causes a brownout. Structures behave differently under reduced power:

| Structure | Confirmed brownout effect |
| --- | --- |
| Floodlight | Reduced illumination range. |
| Mining infrastructure | Less efficient mining. |
| Turret | Slower targeting and reduced fire rate. |

Brownout penalties are fixed per structure. They do not scale or become worse as demand increases within the brownout range.

Demand above capacity but below the blackout threshold causes a brownout. The blackout threshold is **120% of grid capacity, rounded down**, and demand at or above that threshold causes a blackout. For example, a grid with capacity **10** enters a brownout at consumption **11** and a blackout at consumption **12**.

**Blackouts**

A severe overload causes a blackout, during which everything on the affected grid turns off. Electrical connections remain intact during the blackout, so shutting down does not erase the network or resolve the excess demand by itself.

Disabling or destroying consumers can reduce demand and allow power to return. A grid in blackout comes back online only when demand is **at or below 100% of capacity**. Reducing demand merely to brownout levels does not restore it. For a capacity-10 grid that blacked out at demand 12, reducing demand to 11 is insufficient; demand must fall to 10 or below.

**Generation inputs**

| Source | Input | Confirmed behavior |
| --- | --- | --- |
| Anchor | None | Provides a free, limited-capacity grid sufficient for one Floodlight and one turret. |
| Generator | Gas | Passively consumes Gas drawn from global supply. |
| Reactor | Crystal | Passively consumes Crystal drawn from global supply. |

Power sources have no startup requirements. Gas and Crystal are added to and removed from global supply in whole numbers.

**Proposed fuel-cycle implementation:** An enabled Generator pays 1 Gas for a 10-second operating interval; a Reactor pays 1 Crystal for 20 seconds. Whole-number deductions fund each interval without fractional inventory. With no fuel for the next interval the source contributes no capacity until fuel becomes available. These choices are configurable in `power`; there is no startup delay.

#### Lightless economy and production

**Chyme generation and delivery**

Lightless generate Chyme by dealing damage to units and structures at a **1:1 ratio of damage to Chyme**. Individual units have varying Chyme carrying capacities. They must deliver their collected Chyme to an appropriate Medusa or Stoma before it is added to the global Lightless pool.

Generation uses actual health removed after all reductions, capped at the victim's remaining health. Overkill and damage prevented by armor do not create Chyme. The proposed minimum-damage preset clamps damage at zero and remains configurable.

Chyme delivery does not depend on Gloom. Once in the global pool, Chyme can be spent at any time and anywhere, without a Gloom connectivity requirement.

Global Chyme capacity is unlimited, while individual units retain their finite carrying capacities. Attack and Defend units do not interrupt their task to deposit first when full. Any additional Chyme generated beyond a unit's carrying capacity is lost.

**Passive Chyme income**

The Medusa also generates Chyme passively, so Lightless production does not depend entirely on damage harvested by units. The initial configurable rate is 1 Chyme per second.

Wombs can also produce **Chyme Glands**, which passively generate additional Chyme. They are created through the same placement and gestation process as other Glands and do not require a Mother. There is no colony-wide construction-count cap on Chyme Glands, but they still occupy a Womb's limited adjacent Gland slots.

Chyme Glands require a functioning connected Womb. If that Womb dies, they stop producing until a Womb reconnects them. The proposed preset costs 50 Chyme and generates 1 Chyme per 3 seconds.

**Medusa and Womb spawning**

Medusas and Wombs passively produce units without resource costs. The Medusa's passive production spawns **Scavengers only**. Wombs passively produce their corresponding unit type. Spawned units consume population capacity for their corresponding type.

Manual spawning spends Chyme for additional units. These orders are queued at a selected Medusa or Womb and produce units after some time. Manual production runs in parallel with passive production rather than interrupting it. Both spawning paths obey the same population cap for each unit type.

**Population checks and completion priority**

Population capacity is claimed when a unit actually spawns, not when an order is queued or production begins. Manual and passive production can advance the next unit to 100% even when its population cap is full. The completed unit then waits, retaining its progress until capacity becomes available.

Neither spawning path can exceed the relevant population cap. If manual and passive production are both at 100% and competing for available capacity, the manual unit spawns first. A waiting passive unit remains ready until capacity is available for it.

**Manual queue cancellation and loss**

Manual spawn orders can be canceled. An order that has not started receives a Chyme refund; a started order does not. Destroying a Medusa or Womb removes its orders without refunds.

Spawn times and queue limits are defined in the proposed settings. A queued Medusa order pauses with retained progress if its required Womb unlock is lost; restoring that unlock permits it to continue.

By default, manual Medusa production can spawn Mothers, Fathers, and Scavengers, while its passive production remains Scavenger-only. Each of these types has its own population cap. Building a Womb for that type increases its cap and supports upgrades through the Womb's Glands.

Other unit types require a relevant Womb. Placing a Womb of a particular type expands the population cap for that unit type and enables manual Medusa spawning for it. That type can then spawn from its relevant Womb or through a manual Medusa order.

Destroying a Womb reduces the population cap for its unit type. Existing population can temporarily exceed that reduced cap. For types that require a Womb to unlock Medusa spawning, losing the last relevant Womb removes that spawning option. Mothers, Fathers, and Scavengers are available at the Medusa by default and use their own base caps.

Womb placement defaults to Scavengers and offers an optional type submenu, remembering the last choice. Unstarted blueprints can change type. Completed Wombs can reconfigure only after clearing their own manual queue and only if removing old capacity still supports the current population. Old capacity is removed immediately; the new capacity and unlock arrive after the configurable five-second cooldown. Passive spawn progress resets, and Glands retain their original type rather than changing upgrades automatically.

When the Medusa dies, all Wombs receive the permanent spawn-rate buff described in the mission objective. Type caps, costs, spawn times, and the provisional twofold Womb production-rate buff are configurable in `units` and `lightless`.

**Glands and type-wide upgrades**

A Womb is associated with a specific unit type when placed. It can perform an action to spend Chyme and place an additional structure called a Gland on an adjacent tile. The Gland gestates like other Lightless structures, but does not require a Mother.

A Womb can support at most **six Glands at a time**, one on each adjacent tile. Upgrade Glands and Chyme Glands use these same adjacent slots.

Each Gland provides an upgrade for its connected Womb's corresponding unit type; different Glands may provide different upgrades, and some upgrades stack. A Womb can have multiple copies of the same Gland, supporting repeated upgrades where stacking is allowed.

Gland upgrades apply to all Lightless of the corresponding type, regardless of which Womb or Medusa spawned them. Their effects are not restricted to the parent Womb's own offspring. Stacking upgrades, such as increased armor, have colony-wide caps rather than separate caps for each Womb. Those caps limit both construction and benefit: additional Glands cannot be built beyond the corresponding upgrade's colony-wide cap. The initial configured effect is +1 armor per active Gland, capped at three constructed Glands per corresponding unit type across the colony.

Destroying a Gland removes its upgrade contribution. If its connected Womb is destroyed, the Gland remains but stops functioning. A replacement Womb can reconnect surviving Glands. The proposed reconnection requires an adjacent Womb of the same unit type. A disabled surviving upgrade Gland still counts toward its construction cap until destroyed; a Gland cannot connect to two Wombs at once.

**Mother transformation and gestation**

Mothers receive commands to navigate to a specified location and transform into a structure. Placement uses a blueprint, and a Mother travels to it to begin transformation. Mothers can establish structures anywhere the Lightless have revealed, subject to the same footprint and occupancy checks as ordinary construction in the proposed implementation. Tiles containing Gloom are always visible to the Lightless. Illumination neither prevents nor interrupts gestation.

The resource and transformation sequence is:

1. **Pay Chyme:** Placing the blueprint immediately deducts its Chyme cost from the global Lightless pool.
2. **Reach the site:** A Mother travels to the specified location. If she is killed before transformation, another Mother can be sent to the same blueprint.
3. **Begin transformation:** Starting transformation ends refund eligibility without charging Chyme again. The Mother becomes the gestating structure and no longer exists as a separate unit.
4. **Gestate:** The new structure passively advances its construction over time by increasing its health. Health represents gestation progress, so damage sets gestation back.
5. **Complete the structure:** Upon reaching 100% health, the gestating structure becomes the finished Lightless structure.

A blueprint can be canceled before gestation begins, refunding its paid Chyme cost. Once gestation starts, it cannot be canceled. If a gestating structure is destroyed, the Lightless recover no resources.

Gestation's passive health gain is its only source of progress; Gloom regeneration or other healing does not provide additional progress. The default starting health for a new construction site is 1 and remains configurable. The proposed rates complete an undamaged ordinary Lightless structure in 20 seconds or a Gland in 12 seconds, configurable independently.

#### Lightless knowledge and discovery

The Lightless CPU otherwise knows only what it can discover, with one starting advantage: it knows player Anchor locations by default. That location knowledge does not establish general knowledge of every player unit or structure.

Tiles containing Gloom are always visible to the Lightless. The proposed CPU uses discovered information plus its special Anchor-location knowledge, with target selection documented in the first-playable specification.

**Strategy development and testing**

The first-playable specification proposes a configurable baseline CPU for spawning, expansion, Womb construction, and Gland development; its long-term strategy remains open to testing. A Lightless player can control placement, upgrades, Medusa stances, and Fathers. This replaces the colony CPU and occupies one existing multiplayer slot; solo Lightless play supplies a Commonwealth AI opponent.

#### Lightless testing controls and coordination

The Lightless player controls structure placement and Womb upgrades, moves unrecruited Mothers and Fathers, chooses recruits, and sets stances. Combat units and recruited units do not receive individual move, attack, Stop or burrow orders, even from their Father. They organize around the Father's position and assigned stance.

**Medusa stance**

The player can set a global Lightless stance through the Medusa. It affects Lightless standing on any Gloom tile globally, subject to a recruited unit's Father override.

These Lightless coordination stances are separate from Commonwealth aggressive, defensive, and neutral combat stances:

| Stance | Behavior |
| --- | --- |
| Attack | Attack and pursue enemies, chasing beyond Gloom borders when necessary. |
| Defend | Group near structures and defend them, attacking nearby enemies with limited pursuit. |
| Gather | Attack to collect Chyme. Retreat to a Medusa or Stoma when Chyme capacity is full or upon receiving any damage, deposit collected Chyme, then choose a new target. |
| Probe | Explore beyond Gloom and test units or structures for resistance. A probing Scavenger facing little or no resistance can signal nearby Lightless to apply pressure and attack. If attacked before committing to an attack, it retreats to Gloom. |

Mothers and Fathers do not change their behavior in response to stance changes. Their construction or coordination behavior is not replaced by the combat and gathering behaviors in the table.

Proposed coordination values and CPU selection rules are documented in the first-playable specification and `lightless` settings; their strategic balance remains subject to testing.

**Father recruitment**

The player selects a Father and chooses units to recruit. Eligible units include those within the Father's local recruitment range and those connected through Gloom, allowing the Father to recruit remotely through the network as well as locally without it.

Each Father can recruit only a fixed number of units at a time. While the Father is selected, clicking a unit's portrait in its recruited roster releases that unit from recruitment. The proposed settings are 12 recruits and a six-tile local range, both configurable.

Fathers cannot recruit other Fathers. Other Lightless unit types can be recruited, including Mothers. Transferring units between Fathers is allowed. The recruitment interface must highlight or otherwise identify units already assigned to another Father.

**Orders and stance overrides**

Once recruited, a unit tries to pathfind to its Father. The player moves the Father and changes the group's stance to guide its behavior, rather than directly controlling each recruit. The Father itself remains unable to attack.

A Father's commands take precedence over Gloom and Medusa commands, including network requests for defense. Its recruited-unit stance override lasts while units remain recruited.

**Recruitment loss and stance restoration**

A unit becomes un-recruited only if it is both outside its Father's local range and no longer standing on Gloom. Any Gloom patch preserves remote recruitment; the Father need not stand on Gloom.

When recruitment ends, including release or the Father's death, a unit adopts the global Medusa stance if standing on Gloom. Otherwise, it retains the stance most recently assigned by its Father. The proposed transfer is atomic: verify the receiving Father's eligibility and free roster slot before releasing the old assignment.

**Medusa death response**

When the Medusa dies, all Lightless are set to Attack stance. A Father can still override that response for its recruited units, but only while they remain recruited. Releasing a unit or losing recruitment ends that override and subjects it to the post-Medusa Attack stance. Mothers and Fathers still do not change their own behavior in response to stance changes.

#### Illumination, vision, and detection

Illumination, vision, and detection are distinct mechanics. They describe whether something receives light, whether a tile is actively revealed, and whether an enemy is within sensor range, respectively.

**Illumination**

A tile or unit is illuminated when it receives light from a light source. Some units and structures emit illumination, which propagates across tiles using a flood-fill algorithm. Illumination affects Lightless pathfinding, Gloom, and whether a Shade can be targeted.

All vehicles emit light while occupied by a driver; both vehicle lighting and vehicle vision stop when no driver is present. Scouts and Rangers combine surrounding illumination with an additional forward-facing sector or cone, rather than using only a strict radius. Prototype radial ranges, forward ranges, and cone angles are defined in the configurable settings. Infantry and workers emit no light. They provide short-range vision, with a prototype radius of **two tiles**.

Walls and cliffs block the flood-fill propagation of illumination. Closed Gates also block illumination; open Gates permit it to propagate.

**Vision**

Vision actively reveals tiles. It propagates from units or structures using a flood-fill algorithm. Units and structures that emit illumination typically have a vision range extending one or two tiles beyond their illumination range, allowing units along the edge of the light to be visible.

Walls and cliffs block the flood-fill propagation of vision. Closed Gates also block vision; open Gates permit it to propagate. Illumination and vision usually cover similar areas, but illumination does not itself grant vision to every player. In multiplayer, an enemy faction's Floodlight can illuminate tiles without providing vision to friendly units.

**Fog of war**

Resources, structures, and terrain features remain recorded after they leave active vision. Units do not remain visible in fog of war merely because they were previously seen.

**Detection**

An enemy unit is detected when it is within range of a radar or scanner, subject to the unit's detection restrictions. Detection allows turrets to fire on enemies in darkness. Infantry still require vision to fire on enemies.

The Scout vehicle and Radar structure provide passive detection. The proposed ranges are eight tiles for the Scout and twelve beyond the Radar footprint, configurable per definition.

Radar highlights only the tiles occupied by enemies, including Lightless and hostile player-faction units. It does not identify the units occupying those tiles or provide other information about them. Turrets can target units on radar-highlighted tiles even though the nature of those units remains unknown to the player. Shades are an exception: neither radar nor scanners can detect them.

**Targeting requirements**

The following requirements describe eligibility for direct unit targeting. Attack-specific geometry and hit tests can impose additional requirements, as described under combat below.

| Attacker or target | Confirmed requirement |
| --- | --- |
| Turret attacking an enemy in darkness | Detection permits firing in darkness, subject to the target's special restrictions. |
| Infantry attacking an enemy | Vision is required; detection alone is insufficient. |
| Buried Thresher being targeted | Requires detection and a unit-target attack. Infantry also require vision. Area attacks cannot damage it. |
| Unburied Thresher being targeted | Uses normal targeting rules; does not require special detection merely for being a Thresher. |
| Shade being targeted by a turret or infantry | The Shade must be both illuminated and visible. Neither radar nor scanners can detect it. |

A Shade requires both illumination and vision, including when light comes from another player's structure. A buried Thresher's detection requirement is additional to infantry's normal vision requirement.

Concealment alone does not prevent incidental area damage: an unilluminated Shade can receive it without being a valid direct target. Buried units are a separate exception. They can only receive damage from unit-target attacks and cannot receive area damage, even when detected.

#### Combat orders and targeting

**Orders and stances**

Combat behavior is governed by aggressive, defensive, and neutral stances. There are no separate attack-move or hold-position commands. Units can receive movement, direct attack, patrol, and escort orders, with stance and the governing command determining how combat interrupts their task.

Combat infantry (Marines, Flamers, and Lancers) start in defensive stance. Operators and Engineers start in neutral stance. In the proposed preset, combat mechs start defensive, utility vehicles start neutral, and unrecruited Lightless begin in Probe under the baseline CPU.

A basic move command interacts with stance as follows:

| Stance during movement | Confirmed behavior |
| --- | --- |
| Aggressive | Can interrupt the move to attack and pursue an enemy. |
| Defensive | Can attack while trying to finish the move. |
| Neutral | Does not attack automatically and continues the move. |

**Combat stances**

Units have three combat stances:

| Stance | Confirmed behavior |
| --- | --- |
| Aggressive | Initiate combat while idle and pursue enemies until they are killed. Can interrupt patrols or other commands to pursue an enemy. |
| Defensive | Initiate combat while idle, engage within a limited radius of the intended position, and return toward that position when enemies retreat or leave range. |
| Neutral | Never attack unless explicitly directed to do so, including when attacked. |

**Defensive intended position**

A defensive unit has a position where it should be, determined by its current assignment. After a manual move, that position is the location the player directed it to. When an enemy retreats or moves out of range, the unit tries to return there.

During escort, structure defense, patrol, or an expedition, the intended position may change dynamically. The relevant command or state machine determines where the unit should be as its task progresses. Defensive units return toward that current intended position rather than necessarily returning to the place where combat began.

The proposed defensive leash is five tiles. The intended-position rules for mining expeditions are documented separately; other commands maintain their own moving or fixed intended position.

**Firing and movement**

Units cannot fire while moving. The Scout passenger is an exception and can attack while the Scout moves, using their normal weapon and the Scout's vision.

**Turret targeting**

Turrets automatically engage eligible enemies within range. The player can select a turret and override its target. When the target is killed, leaves range, or becomes concealed, the turret picks a new target. The proposed priority is an explicit player target, then an eligible attacker, then the nearest eligible hostile, with stable IDs breaking ties.

When a target becomes concealed, units move to its last known location, subject to their stance's pursuit constraints. Defensive range still limits pursuit of concealed targets; losing sight of an enemy does not permit a defensive unit to chase beyond its allowed range.

**Player-directed attacks on friendlies**

The player can explicitly direct units to attack friendly units and structures. Units do not choose friendly targets automatically. Incidental friendly fire is generally possible, but depends on the attack or damage definition rather than one universal rule.

#### Damage and attack mechanisms

**Commonwealth weapon roles**

Infantry, combat mechs, and defensive turrets have corresponding weapon roles. Their implementations vary while preserving the same broad purpose:

| Role | Infantry | Mech | Turret | Core behavior |
| --- | --- | --- | --- | --- |
| Generalist | Marine | Reaper | Sentry | Middling damage and a high rate of fire. |
| Swarm clearing | Flamer | Cremator | Torch | Lower damage applied over an area, multiplying its effect against groups. |
| Anti-tank | Lancer | Javelin | Lance | High damage and a low rate of fire. |

The Marine uses a ballistic weapon and the Flamer uses a flamethrower. Lancer, Javelin, and Lance weapons are single-burst lasers:

| Weapon | Hit mechanism |
| --- | --- |
| Lancer | Guaranteed-hit unit-target attack. |
| Lance | High-damage unit-target attack with a low rate of fire. |
| Javelin | High-damage unit-target attack with a low rate of fire. |

Lance and Javelin currently use simple unit-target attacks. Alternative attack patterns are deferred rather than part of their current definitions.

Flame attacks deal damage every tick to enemies and structures within their hit area, subject to buried-unit immunity to area damage. They currently leave no persistent fire. The proposed flame hit areas are forward cones, with damage every 0.05-second simulation tick. Weapon damage, intervals, range, angles, and friendly fire are configurable per attack.

**Lightless attacks**

| Organism | Confirmed attack behavior |
| --- | --- |
| Ravager | Melee attacks with a substantial damage bonus against structures. |
| Buried Thresher | Tentacles pierce the ground to make unit-target attacks against nearby enemies in range. Cannot use its melee attack while buried. |
| Unburied Thresher | Can make melee attacks, but cannot use its underground tentacle attack. |
| Shade | Very-long-range, guaranteed-hit unit-target attacks dealing damage to one target. Typically attacks from the shadows at the edge of illumination. |
| Father | Cannot attack. Floats around directing other Lightless. |

Threshers cannot move while underground. Burrowing and emerging both take time, and the Thresher cannot act during either transition. It becomes buried only when the burrowing animation completes. Transitions cannot be interrupted except by killing the Thresher. Above ground, it can be targeted normally. The proposed transitions each take two seconds; emergence retains buried targeting until completion. Durations and attack values are configurable.

**Damage and armor**

Damage is a flat value per instance. Applicable bonus damage against specific targets is added before armor, and armor provides a flat reduction:

`damage before any minimum-damage rule = base damage + applicable target bonus - base armor - Rampart armor bonus`

Minimum damage remains a configurable design choice. The prototype preset clamps at zero, allowing armor to completely prevent a weak hit; it must not be hardcoded. Targeting and damage have no added randomness.

**Attack composition**

Attack behavior depends on the attack's definition. Attacks can be defined recursively, with nested mechanisms triggered on a hit. A hit does not necessarily deal damage immediately: it can instead spawn another attack, as with a projectile or grenade that triggers a subsequent attack.

Confirmed forms include:

- Strict unit-target attacks that always hit their target.
- Attacks that use special geometry or hit tests.
- Attacks that spawn another attack on hit instead of immediately dealing damage.

Before making a guaranteed-hit attack, the attacker must have a guaranteed unobstructed shot. Once launched, the attack still hits if the target becomes concealed or a Gate closes in the shot's path. These changes do not invalidate an already launched attack.

Having vision of an enemy does not guarantee a clear shot for every attack. Obstruction and hit behavior depend on the attack mechanism rather than a random accuracy roll. The initial weapon definitions are listed in the settings; the first-playable specification defines obstruction, collision, and target eligibility for those attacks.

**Walls, Gates, and attack obstruction**

Weapons cannot fire over Walls or closed Gates. Guaranteed-hit attacks check for an unobstructed shot before launch; a Gate closing afterward does not stop that launched attack. Open Gates permit vision and illumination to propagate; closed Gates block both.

Some future attacks may explicitly ignore Walls, such as a lobbed grenade. That exception is planned for later implementation and is not part of the current weapon set.

**Area damage and concealment**

Area attacks can damage concealed enemies that cannot be directly targeted, including unilluminated Shades.

Buried units cannot receive damage from area attacks. They must receive damage through a unit-target attack, subject to its targeting requirements. Detection does not remove this restriction. Whether an area effect also damages friendlies depends on that attack's definition; friendly fire is generally possible.

**Rampart shields**

A powered Rampart adds a flat armor reduction to all structures within its shield footprint. This bonus stacks on top of each affected structure's own armor, if any. Damage is reduced by the combined armor after applicable target bonuses are added.

The shield is an armor buff rather than a separate pool of shield health. If the Rampart is destroyed or becomes unpowered, it stops buffing nearby structures.

Overlapping Ramparts do not stack their armor bonuses. Their fixed bonuses can both apply to the same structure, but the effective armor increase remains the single fixed Rampart bonus. The proposed bonus is 3 armor within four tiles beyond the Rampart footprint, including the Rampart itself and other Ramparts. Values and eligibility are configurable.

#### Healing and repairs

The Anchor passively heals nearby biological units. It does not heal vehicles or structures; those require Engineer repair. The proposed healing is 4 health per second within three tiles beyond the Anchor footprint, including during combat.

Engineers can repair damaged vehicles and structures, including during combat. Repair consumes resources over time, usually Ore. The proposed standard repair cycle consumes 1 Ore and repairs up to 10 health per Engineer-second. Values and cycle durations are configurable.

Lightless units passively regenerate while on Gloom. Completed Lightless structures passively heal without requiring Gloom. Gestating structures use only their passive gestation health gain to progress; reaching full health completes the structure, and taking damage sets that progress back. The proposed rate is 2 health per second with no damage interruption delay, both configurable.

#### Lightless responses to light

Light does not directly damage Lightless units. It influences their pathfinding: when they are not attacking a player, Lightless go to great lengths to avoid routes through illuminated areas.

Stalkers avoid light and do not advance alone into illuminated areas under their normal behavior. Fathers act as coordinators and can override Lightless behavior concerning both light and aggression. They can recruit nearby units without Gloom and remotely recruit any unit standing on any Gloom patch. Competing commands should split the Lightless population between them, but a Father's command always takes precedence over Gloom and Medusa commands. The CPU distributes available non-recruited defenders on Gloom among global active structure requests, using stable IDs to resolve equal priorities.

#### Gloom

Gloom is a global communication channel used by the Lightless. Each Gloom tile has health. Any unit standing on any living Gloom tile can receive colony communication; separate patches do not need a continuous connection.

**Growth**

Gloom spawns on dark tiles within range of Lightless structures. New growth must connect to existing Gloom or a Lightless structure, and spreads at random to eligible unilluminated frontier tiles. Walls and cliffs do not block Gloom spread, even though they block illumination and vision propagation.

**Illumination and withering**

Illumination deals damage to Gloom over time and prevents it from spreading onto illuminated tiles. Gloom persists after its supporting structure is removed. If a Gloom tile is no longer within range of any Lightless structure, it slowly withers.

**Communication**

Lightless standing on Gloom can receive Medusa commands or be recruited by a Father at any distance, including across disconnected patches. Only the receiving unit needs to stand on Gloom; neither the Father nor the Medusa needs Gloom underneath it to broadcast. Fathers can still recruit nearby units off Gloom.

The global channel supports several behaviors:

- **Structure defense:** A Lightless structure under attack can reach out through Gloom to recruit defenders, subject to the higher priority of Father commands.
- **Attack coordination:** A Father can recruit units for an attack through Gloom.
- **Colony stance:** The Medusa can specify attack, defend, gather, or probe stance for Lightless standing on any Gloom tile. A Father's recruited-unit stance overrides this while recruitment lasts.

**Orders outside Gloom**

A unit that leaves Gloom retains its orders. When those orders finish or are interrupted, the unit returns to its default behavior. In the proposed implementation, leaving Gloom retains the last global stance until returning to any Gloom tile or receiving a higher-priority override. Father recruitment ends only when the unit is off Gloom and outside local range.

Gloom health, radii, spread timing, illumination damage, and unsupported withering are defined in the proposed settings. Spread uses the map seed; illumination damage applies once per lit tile rather than stacking per light source.

### Factions

#### The Solar Commonwealth (SC)

A sprawling interplanetary civilization whose expansion depends on the resources of distant worlds. Its expeditions combine industrial machinery, disciplined military forces, and extensive logistical networks to establish footholds on hostile planets. On Erebus, Commonwealth interests converge on Nacre, bringing corporate ambition, regulatory authority, and frontier opportunism into uneasy cooperation.

**The Atlas Mining Company (AMC)**
Sometimes referred to as just *Atlas*

A powerful industrial corporation specializing in resource extraction on dangerous frontier worlds. Atlas supplies the machinery, personnel, and infrastructure needed to exploit Erebus, viewing its Nacre deposits as an opportunity worth extraordinary expense and risk. Its priorities center on maintaining production, protecting valuable equipment, and ensuring the expedition returns with a profitable haul.

**The Interplanetary Mining Commission (IMC)**
Sometimes referred to as just *The Commission*

A Commonwealth authority responsible for overseeing mining operations and enforcing extraction rights across settled and frontier space. The Commission seeks to place Erebus's valuable resources under controlled exploitation, balancing industrial demands against the need to contain the Lightless threat. Its presence brings official oversight and military discipline to an expedition driven by competing interests.

**The Frontier Syndicate (FS)**
Sometimes referred to as *Pirates*

A loose alliance of independent prospectors, smugglers, and raiders operating along the Commonwealth's outer reaches. The Syndicate survives by reaching valuable deposits before sanctioned expeditions and moving resources beyond the Commission's control. On Erebus, its members see Nacre as a chance to secure wealth and independence, even if claiming it means confronting both the Lightless and rival human forces.

#### The Lightless (L)

A network of predatory organisms that inhabits Erebus's darkness, consuming organic and inorganic matter to sustain its growth. Individual creatures serve the needs of a larger colony, harvesting Chyme, defending living structures, and developing specialized adaptations through interconnected tissue. Artificial light holds them at bay, but beyond the expedition's illuminated perimeter, the colony spreads and gathers strength.

### Units

General - Reliable, moderate damage against individual targets. Generalist units handle routine engagements and provide consistent firepower against enemies that do not require a specialized counter.

Swarm Defense - This is about clearing swathes of enemies. Lower damage than the generalist, but multiplied over many targets. This makes them essential without replacing the generalist.

Heavy Defense - Powerful, slow-firing attacks designed to penetrate heavy armor and eliminate durable enemies. Effective against individual high-priority targets, but easily overwhelmed by numerous weaker opponents.

Area Denial - Persistent effects that make an area dangerous to occupy or cross. These units control approaches, disrupt advancing enemies, and support defensive positions by limiting hostile movement.

Siege - Specialized attacks designed to destroy structures and break fortified positions. These units support deliberate assaults, relying on escorts to protect them from mobile threats.

**Operator (SC)**
*A versatile expedition worker trained in resource extraction, material transport, and basic field operations. Operators form the backbone of the expedition's logistics network, keeping industrial facilities supplied and construction projects moving.*

**Engineer (SC)**
*A specialized expedition technician equipped for construction, maintenance, and field repairs. Engineers establish critical infrastructure, restore damaged equipment, and reinforce defensive positions. Essential to expanding and sustaining the expedition's foothold in hostile territory.*

**Marine (SC)**
*A heavily equipped infantry soldier trained for combat in hostile planetary environments. Armed with a rapid-fire ballistic rifle, Marines provide reliable frontline firepower, escort vulnerable expedition personnel, and defend critical infrastructure against Lightless incursions. Most effective when deployed in coordinated squads.*

**Flamer (SC)**
*A specialized assault infantry unit equipped with a high-pressure flamethrower and protective thermal armor. Flamers unleash sweeping torrents of burning fuel, devastating tightly packed groups of Lightless at close range. Particularly effective at breaking enemy swarms and defending narrow approaches, but vulnerable to threats beyond their limited range.*

**Lancer (SC)**
*A specialized heavy infantry unit equipped with a portable single-burst laser weapon. Lancers deliver high-damage shots against durable targets, providing the expedition with dedicated anti-tank firepower. Their low rate of fire makes them effective against individual heavy enemies but vulnerable to overwhelming swarms.*


**Scout (SC, Vehicle)**
*A fast, lightly armored reconnaissance vehicle equipped with forward-reaching lights and detection equipment. The Scout carries a driver and one passenger, who can fire a ranged weapon from inside, but has no resource cargo capacity. Its mobility and sensors help expedition forces uncover threats and explore routes through the darkness.*

**Ranger (SC, Vehicle)**
*A rugged, armored utility vehicle designed to traverse the planet's hostile terrain. Equipped with powerful floodlights and ample cargo capacity, the Ranger transports personnel and supplies between remote outposts, providing a vital logistical lifeline through the darkness.*

**Excavator (SC, Vehicle)**
*A massive industrial drilling machine built to tear through the planet's dense rock and unforgiving terrain. Equipped with a powerful rotary drill, the Excavator carves passages through natural obstacles, opening new routes for expedition forces and reshaping the battlefield.*


**Reaper (SC, Vehicle)**
*A heavily armored combat mech equipped with a high-caliber machine gun capable of delivering devastating sustained fire. Designed to suppress advancing Lightless swarms, the Reaper combines formidable firepower with the mobility needed to reinforce defensive lines and support frontline assaults.*

**Cremator (SC, Vehicle)**
*A heavily armored combat mech equipped with a high-capacity flamethrower capable of engulfing entire swarms in searing fire. Designed for close-range engagements, the Cremator excels at incinerating advancing Lightless and clearing densely infested territory, turning the darkness into a blazing inferno.*

**Javelin (SC, Vehicle)**
*A heavily armored combat mech equipped with a single-burst laser cannon. The Javelin delivers high-damage shots against individual targets at a low rate of fire, providing mobile anti-tank support against durable enemies.*

**Scavenger (L)**
*A small, voracious organism and the weakest of the Lightless, used to probe expedition defenses and gather Chyme. Scavengers test units and structures, signaling nearby Lightless to attack when resistance is weak and retreating if attacked before committing. Their claws and jaws tear into exposed targets to harvest nutrients for the colony.*

**Stalker (L)**
*A swift, predatory Lightless organism adapted for hunting and ambush. Moving silently through the darkness, the Stalker uses its powerful limbs and razor-sharp claws to close on isolated prey, striking with lethal speed before retreating into the shadows. Stalkers avoid light and never advance alone into illuminated areas.*

**Ravager (L)**
*A heavily armored Lightless organism bred to endure sustained fire and break through defended positions. Powerful melee attacks deal substantial bonus damage against structures, making the Ravager particularly dangerous to expedition fortifications and machinery. Its durability demands concentrated fire from weapons suited to heavy enemies.*

**Thresher (L)**
*A defensive Lightless burrower that guards the colony's territory from beneath the surface. Immobile while buried, it uses tentacles to strike individual enemies within range and can only be damaged by unit-target attacks while detected. Burrowing and emerging take time. Above ground, it can be targeted normally and relies on melee attacks instead of underground tentacles.*

**Shade (L)**
*An elusive Lightless organism with very-long-range attacks, typically striking from the shadows at the edge of illumination. Undetectable by radar or scanners, the Shade can only be targeted while both illuminated and visible. Its attacks force the expedition to extend light and vision beyond defensive positions to expose the threat and return fire.*

**Mother (L)**
*A specialized Lightless organism that carries the biological material needed to establish new colony structures. Upon reaching a suitable location, the Mother anchors herself to the ground and transforms into a Lightless structure.*

**Father (L)**
*A specialized, noncombat Lightless coordinator that floats around directing other organisms. Unable to attack, the Father overrides other creatures' instinctive behavior to serve the colony's immediate needs. Its influence turns individual organisms into a coordinated force and makes Lightless attacks and defenses less predictable.*



### Structures

**Anchor (SC)**
*Driven deep into the planetary crust at tremendous velocity, the Anchor secures an orbital tether through which supplies and personnel descend from the fleet above.*

**Wall (SC)**
*A reinforced defensive barrier designed to withstand sustained attacks from the Lightless. Walls provide durable protection for critical infrastructure, channel enemy movement into defended approaches, and can be further fortified to withstand heavier assaults.*

**Gate (SC)**
*A reinforced access point integrated into defensive walls. Gates can be opened, closed, or locked by the player. When unlocked, they allow friendly units to operate them while pathfinding through the perimeter. Closed Gates block weapon fire, light, and vision.*

**Depot (SC)**
*A logistical storage facility that receives and distributes resources throughout the expedition's supply network. Depots provide convenient collection and delivery points for Operators, reducing transport distances and supporting industrial operations at remote outposts.*

**Cradle (SC)**
*A reinforced orbital receiving platform designed to intercept and secure personnel capsules descending from orbit. Integrated outfitting stations equip newly arrived Operators for immediate deployment.*

**Armory (SC)**
*A fortified military outfitting facility housing weapons, armor, and specialized combat equipment. Automated assembly and provisioning systems prepare expedition personnel for frontline deployment.*

**Factory (SC)**
*A heavily automated manufacturing complex equipped with industrial fabricators and heavy assembly machinery. Produces vehicles, mechanized walkers, and other equipment required for planetary operations.*

**Generator (SC)**
*A compact, high-output power station designed for sustained operation in hostile environments. Supplies the electricity needed to maintain the expedition's lights, defenses, and industrial infrastructure.*

**Reactor (SC)**
*An advanced power station that harnesses the immense energy stored within refined Crystal. Specialized containment systems regulate the reaction, producing enormous quantities of electricity to sustain the expedition's most demanding infrastructure.*

**Relay (SC)**
*A rugged power distribution station that extends the expedition's electrical grid across hostile terrain. High-capacity transmission equipment delivers electricity to remote installations, enabling operations far beyond the main base.*

**Floodlight (SC)**
*Requires Power*
*A high-intensity illumination tower designed to flood large areas with artificial daylight. Its powerful lamps repel the Lightless, establishing safe zones for personnel, infrastructure, and industrial operations.*

**Extractor (SC)**
*Requires Power*
*A heavy-duty extraction platform equipped with deep-bore drilling equipment and adaptable recovery systems. Harvests underground deposits of Ore, Gas, and Nacre to sustain the expedition's industrial operations.*

**Sentry (SC)**
*Requires Power*
*An automated defensive turret equipped with a high-rate-of-fire ballistic weapon and autonomous targeting systems. Designed to intercept approaching hostiles and provide continuous protection for expedition installations.*

**Torch (SC)**
*Requires Power*
*An automated incendiary turret that unleashes torrents of burning fuel against approaching hostiles. Devastating at close range, the Torch excels at incinerating swarms of Lightless before they can overwhelm defensive positions.*

**Lance (SC)**
*Requires Power*
*A heavy defensive emplacement equipped with a single-burst laser weapon. The Lance delivers high-damage shots against individual targets at a low rate of fire, reinforcing the expedition's defenses against durable enemies.*

**Foundry (SC)**
*Requires Power*
*A heavy industrial facility equipped with high-temperature furnaces and automated casting systems. Smelts raw Ore into durable Alloy for construction, vehicle manufacturing, and military production.*

**Refinery (SC)**
*Requires Power*
*An industrial chemical processing facility that converts harvested Gas into high-performance synthetic polymers. Produces Polymer for advanced construction, electrical components, and military equipment.*

**Synthesizer (SC)**
*Requires Power*
*An advanced materials facility that uses precisely focused optical energy to restructure Ore and Gas into exotic crystalline lattices. Produces Crystal for high-output power systems, advanced weaponry, and specialized military equipment.*

**Rampart  (SC)**
*Requires Power*
*A heavy defensive installation housing an advanced resonance projector. Generates tightly conforming energy shields that reinforce all structures within its shield footprint, adding protection on top of their existing armor. The protection ends if the Rampart is destroyed or loses power.*

**Radar (SC)**
*Requires Power*
*A military surveillance installation equipped with advanced ground-penetrating radar and motion detection systems. Detects Lightless concealed beneath the surface or hidden in darkness, revealing approaching threats before they reach the expedition's defensive perimeter. Essential for maintaining awareness beyond the reach of artificial light.*

**Fabricator (SC)**
*Requires Power*
*An advanced manufacturing facility equipped with precision machining and automated assembly systems. Offers specialized upgrades purchased with industrial resources and completed through the work of Engineers. Multiple Engineers can coordinate their efforts to accelerate development.*


**Medusa (L)**
*A colossal living organism at the center of the Lightless tissue network, connected to the surrounding biomass through an extensive web of organic tendrils. The Medusa produces Scavengers, Mothers, and Fathers, along with additional organisms made available by specialized Wombs. Only one Medusa exists per mission, serving as the biological heart of the Lightless presence.*

**Stoma (L)**
*A specialized organ connected to the Lightless tissue network, capable of absorbing and processing Chyme harvested by nearby organisms. Stomas serve as distributed collection points, allowing Lightless to deposit gathered nutrients without returning to the Medusa. The absorbed Chyme is circulated throughout the network to sustain growth and accelerate development.*

**Womb (L)**
*A specialized reproductive organ that passively spawns a particular type of Lightless organism. Each Womb expands its unit type's population capacity, enables Medusa spawning for types that require it, and supports Glands that adapt the corresponding organisms or generate Chyme. Wombs allow the Lightless to build a larger and more specialized population.*

**Gland (L)**
*A specialized upgrade structure spawned on a tile adjacent to a Womb. The Gland induces adaptations in all Lightless of the Womb's corresponding unit type, regardless of where they were spawned. Different Glands provide distinct adaptations, some of which can combine to strengthen the species.*

**Chyme Gland (L)**
*A specialized income-producing structure grown by a Womb. Rather than adapting a unit type, the Chyme Gland passively generates additional Chyme while connected to a functioning Womb. It requires no Mother and has no colony-wide construction-count cap, but occupies one of its Womb's six adjacent Gland slots.*



### Resources

**Ore**
*A mineral-rich deposit found beneath the planet's barren surface. Extracted and refined into durable metals, ore provides the raw materials essential for constructing structures, vehicles, and military equipment.*

**Gas**
*A volatile mixture of hydrocarbons trapped beneath the planet's surface. Extracted from underground reservoirs, gas serves as a vital source of fuel and chemical feedstock for producing plastics and advanced materials.*

**Alloy**
*A high-strength metal composite produced by refining and combining raw ores. Exceptionally durable and resistant to extreme conditions, alloy is essential for constructing reinforced structures, armored vehicles, and advanced military equipment.*

**Polymer**
*A versatile synthetic material produced by processing hydrocarbons extracted from natural gas. Lightweight, durable, and highly adaptable, polymer is essential for manufacturing insulation, protective equipment, electronic components, and advanced military hardware.*

**Crystal**
*An advanced crystalline material synthesized from refined ore and gas through a precision-controlled growth process. Its unique molecular structure enables exceptional energy storage and transmission, making crystal essential for high-powered weapons, advanced electronics, and experimental technologies.*

**Chyme**
*A viscous, nutrient-rich substance produced by the Lightless through the breakdown and assimilation of organic and inorganic matter. Harvested through attacks on creatures and structures alike, chyme fuels the propagation of new organisms, the growth of biological structures, and the development of adaptations.*

**Nacre**
*A rare, iridescent biomaterial harvested from the remains of the Medusa. Its extraordinary structural and biochemical properties make it invaluable for scientific research and advanced technology. Recovering sufficient Nacre and transporting it to the Anchor is the expedition's primary objective and the key to securing extraction from the planet.*

**Power**
*Electricity supplied by Anchors, Gas-fueled Generators, and Crystal-fueled Reactors, then distributed through electrical footprints and the expedition's Relay network. Power sustains artificial lighting, automated defenses, resource processing, and other critical infrastructure. Maintaining a reliable grid is essential to holding territory, as an interrupted supply can leave remote outposts exposed to the Lightless.*

The earlier game remains archived in `../v1/`; this `v3/` project is the current alpha.

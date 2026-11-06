### AtD
The core fantasy of AtD is defending your base against an oppressive and hostile darkness.

This document is the master design reference for the next core rewrite. It collects the intended design and concepts already present in the game. Existing prototype behavior is identified as **Current game**; additions from open ideas are identified as **Proposed**. Unresolved rules are collected at the end. A current-game rule is a reference for the rewrite, not an automatic decision to keep it.

The unit descriptions and values below remain the intended design draft. They do not necessarily match the current game's roster or balance. Implementation details and current tuning remain in [gameplay balance](v1/docs/gameplay-balance.md) and [gameplay.json](v1/config/gameplay.json).

### Narrative
The work-in-progress narrative puts you in control of a company of mercenaries and engineers sent to a hostile alien planet to recover its most valuable resources while the planet fights tooth and nail to keep you from doing so.

### Gameplay
A single session begins with a small force deployed to the planet.

The player establishes a base, scouts the darkness, gathers resources, and expands the infrastructure needed to survive farther from the landing zone. Engineers and supplies need protection while they work and travel. Expanding the illuminated perimeter makes more ground usable, but also creates a larger boundary to defend.

**Rewrite objectives**
Human participants land on the planet, repair the extraction point, destroy the Nest, and mine nacre from its remains. Nacre must be transported to and deposited at the extraction point. Once the extraction point holds the required threshold of nacre, extraction can be triggered. Reaching the threshold enables the player to start an extraction countdown when they choose. The player must defend the extraction point until the countdown completes. They can delay starting it to gather and extract additional nacre, accepting the risk of remaining on the planet longer. The first Human participant to successfully extract wins the match, ending it for all participants.

The Lightless defeat a Human participant by destroying that participant's HQ or extraction point. To win the match, the Lightless must defeat every Human participant, including AI-controlled Humans once AI is implemented. Defeating one Human participant does not end a match while others remain.

The Hive Recovery rules below describe the existing implementation. Its Hive Core, dropped-core loss condition, extraction timer, and repairable destroyed beacon are historical reference points; they are not automatically the rules for the nacre objective.

**Current game: Hive Recovery**
A session starts with HQ, one engineer, one marine, and a small reserve of both resources. Vehicles, production structures, storage, and power infrastructure must be built during play.

1. Explore to locate resources, the ruined Extraction Beacon, and the Lightless Hive. Objective locations are hidden until discovered.
2. Repair the Extraction Beacon with an engineer before taking the Hive Core.
3. Send an infantry unit to retrieve the core from the hive. Destroying the hive is not required for the initial theft.
4. Escort the carrier to the repaired beacon and hold within its extraction radius for the full extraction time. The current baseline is 60 seconds.

Taking the core causes permanent colony-wide pursuit. The carrier can board a vehicle without leaving the core behind. If the carrier dies, the core drops and another infantry unit can recover it. A Lightless reaching the dropped core loses the mission. Losing HQ also loses the mission.

Leaving extraction range resets progress. A destroyed beacon becomes repairable ruins and must be repaired again. Resource delivery supports the expedition; it does not itself win the mission.

**World and pacing**
The current game generates a seeded hex map with cliffs, passages, resource fields, and mission objectives. The landing zone and approaches to resources and objectives remain accessible. The starting area has a preparation grace period, while expeditions outside it can encounter danger earlier. Lightless pressure increases as the session continues.

**Proposed: broader play styles**
Open ideas include more colony management, crafting, and modes that allow play beyond a single recovery mission. Their objectives, progression, and relationship to Hive Recovery remain undecided.

#### Mechanics

**Tiles**
The world consists of an array of hexagonal tiles with various properties.

Terrain affects movement, construction, and the propagation of light. Structures occupy footprints authored as relative axial [q, r] coordinates; rotating a structure rotates those offsets in 60-degree steps. Capsules and cylinders are centered at the footprint centroid, while footprint-shaped meshes fill the occupied hexes. Build footprints reserve placement space; pathfinding uses a separate collision shape. Walls and solid terrain fill their footprint hexes, while round buildings use a circle centered at the rotated footprint centroid with an independently authored radius. Units can move through build-footprint space outside that circle when their own collision radius fits. Mobile units use a separate collision radius for navigation clearance. Elevation and reachable approaches matter when placing structures or assigning work.

Friendly units prefer to avoid overlapping but may pass through each other when necessary. Enemy units are solid movement obstacles. Point movement finishes within one tile of the destination; approaching a unit or structure finishes adjacent, measured from the moving unit's center to the target unit or nearest footprint tile center, with larger collision radii increasing the required range.

Global pathfinding uses terrain and immobile structures. Moving units influence local predictive repulsion and contact checks; their motion does not invalidate the route graph. Friendly repulsion can yield under congestion; hostile contact remains solid.

Unit-producing structures have a settable rally point, defaulting directly south. Units emerge on the available adjacent footprint tile with the shortest navigable route to that point, then move toward it. Selecting the structure displays its rally point.

**Current game: terrain and illumination**
Ground light propagates around blocking terrain rather than passing through cliffs, closed walls, or closed gates. Elevated sources can illuminate equal or lower ground. Player-built ramps and platforms are currently disabled, although the terrain supports elevation.

**Revealed**
A tile is either revealed or not revealed. A revealed tile is visible on the minimap; however, it does not update unless it is perceived or illuminated.

**Perceived**
A tile or unit is perceived by certain units or structures in range. A perceived unit or tile is updated on the minimap when it changes. Perception and illumination are not the same, but they do overlap. Perception propagates using a flood-fill algorithm. A perceived tile does not have the darkness overlaid. A perceived unit is fully visible and targetable, even without illumination. Perception provides the same visibility, discovery, minimap updates, and targeting as illumination, but does not trigger illumination-specific effects or Lightless reactions.

**Illuminated**
A tile or unit is illuminated by certain units or structures in range. Illumination propagates using a flood-fill algorithm. A light-blocking tile can be illuminated, but light does not propagate onward from it; light can take another path around it within the source's range. Walls are currently the only Human structures that block light; HQ does not. An illuminated tile does not show the darkness overlay. Illumination provides the same visibility and targeting as perception, including full visibility and targeting without detection for ordinary units. Its additional effects include light-specific Lightless behavior and damage to the Veil.

**Detected**
A unit is detected by certain units or structures in range. Detection and illumination are not the same, but they do overlap. Detection applies to all units within a radius (or footprint).

**Rewrite: detected-unit targeting**

| Unit state | Eligible attackers |
| --- | --- |
| Illuminated, with or without detection (ordinary units) | All attackers |
| Perceived, with or without detection (ordinary units) | All attackers |
| Detected, neither perceived nor illuminated | Turrets only |

These rules determine target eligibility; attackers must still satisfy their weapon range and other attack requirements. Detection alone does not establish full visual presentation; how detection-only contacts are displayed remains to be specified.

**Current game: discovery and sensor contacts**
Illumination currently drives discovery and enemy visibility. Discovered resource fields and objectives remain recorded after the light moves away. Scouts and Scanner structures provide approximate hostile contacts in darkness, but do not reveal the enemy or nearby resources. Current weapons require vision to attack.

In the rewrite, illumination and perception both provide full visibility and targeting for ordinary units. Perception reveals an area without illuminating it. Detection alone permits turret targeting; combining detection with perception or illumination permits targeting by all attackers. Concealed-unit exceptions remain to be specified.

**Veil (Lightless) — Planned**
The Veil is a membrane passively produced by Lightless structures within a certain radius. It grows outward from the producing structure, randomly choosing an eligible tile within range adjacent to existing Veil. Units do not block growth beneath them, regardless of ownership or movement. Structures, blocking terrain, and illumination prevent expansion; a producing structure can seed Veil beneath itself. Choices use seeded simulation randomness so replay and rollback reproduce the same growth. Veil does not grow on illuminated tiles. Illumination damages existing Veil and notifies Lightless connected to that Veil network. When a Veil-producing structure is destroyed, the Veil it produced decays over time. A surviving source maintains areas of Veil that overlap its own; only areas with no surviving source support decay. Growth radius, growth rate, and decay rate are tunable values.

The Veil acts as a nervous system for the Lightless. Destroying it or stepping onto it with a unit alerts the Lightless. Stepping onto Veil does not itself damage it. Perception can reveal Veil without damaging it or preventing its growth; illumination prevents growth and damages existing Veil. Every tile covered in living Veil also provides perception to its owning Lightless participant, in addition to unit and structure perception. The Veil also provides a communication network between connected Lightless.

**Veil stances**
Both friendly and hostile units can be detected when they enter Veil. Entering Lightless adopt the stance of their participant's global Veil network. When a hostile unit enters, the network's stance determines how its Lightless automatically respond.

- **Neutral:** every unit maintains its default behavior.
- **Defensive:** there is something inside to defend; attack the threat inside the Veil.
- **Offensive:** there is something outside to attack; direct the Lightless toward an outside target.

When the Nest is attacked, it can alert all Lightless connected to its Veil. A Father coordinating an attack can communicate with all Lightless connected to its Veil. All Veil controlled by the same Lightless participant communicates globally, including disconnected patches. A Lightless unit connects while on Veil or up to one tile away from it. Gaps do not interrupt communication, and there are no separate patch networks or network-merge rules.

#### Combat

**Health**
Health represents a unit or structure's capacity for withstanding damage.

**Damage**
Damage is fixed integer value that represents the destructive power of an attack or ability.

**Armor**
Armor applies a flat reduction to incoming damage. Flat reduction, in combination with damage bonuses, makes tuning easier to reason about. Whether or not armor should apply a lower bound on damage (above 0) is an open question (e.g. should armor allow incoming damage to go to zero, or should it be capped at some lower bound?).

**Range**
Range determines how far away an attack target must be in order to perform the action. Broadly speaking attacks fall into two categories - melee (within 1 tile) or ranged (within 2 or more tiles); however, they are both represented using a single value. The designation between melee and ranged is a semantic one. (Explore range bonuses for certain units and structures)

**Bonus Damage**
All attacks have some base damage that is optionally enhanced against specific targets with bonus damage. For example, some units may deal a very low base damage, but deal a hefty bonus to certain units or structures.

**Damage Source**
All attacks include some metadata about which unit generated it.

**Area of Effect**
Some attacks deal area of effect damage which applies to all units and structures within a radius (or footprint) of the target location, unit, or structure.

**Unit Target**
Some attacks deal damage directly to one or more specific unit or structure(s).

**Line of Sight**
Some attacks deal damage to all units and structures that intersect a ray or line segment.

**Attack Interval**
The time between attacks determines how often a unit or structure can apply its damage. Damage and attack interval need to be considered together when comparing weapons.

**Current game: ammunition and reloading**
Machine gun and flame turrets have finite magazines. Reloading spends resources, takes time, and prevents firing. Automatic reload can be toggled; a manual reload can be ordered before the magazine is empty. Reloading waits if resources are unavailable and pauses during power loss. Laser turrets use power without a finite magazine.

**Proposed: weapon roles**
Open ideas include plasma weapons for area damage and rail guns for high damage against heavily armored targets. These would complement single-target weapons. Damage types, armor types, friendly fire, and the interaction between armor and bonus damage are not yet defined.

#### Units

A note on values - Any actual numbers in this document are subject to tuning and should be exposed and configurable via a script or resource.

Speed is a trait that defines how fast a unit can move and it is defined in terms of tiles per second where one tile unit is the length of its inner diameter.

Size, shape radii, movement and ranges use one shared distance unit: a tile's inner diameter (the distance from one edge to the opposite edge). A shape radius of 0.5 fits inside a tile; a radius of 1 gives a shape two tiles wide.

Perception defines the perception radius of a unit in tiles. Perception also reveals tiles within range without illuminating them.

Illumination defines the illumination radius of a unit in tiles. Illumination also reveals tiles within range.

Detection defines the detection radius of a unit in tiles.

Capacity defines how many items a unit can hold at any time.

Vehicles are special units that require a driver/pilot.

**Current game: crew and cargo**
The driver occupies a seat and cannot work as a mining engineer while driving. Passenger seats and cargo capacity are separate limits. The current Jeep has four seats including its driver; the Scout and Drill each have only a driver seat. Materials and gas share a unit's cargo capacity. Mining convoys need at least one working engineer in addition to a driver for each vehicle.

Vehicles carry workers and supplies between outposts and receivers. Movement, headlights, and scouting do not require batteries or charging in the current game. Unpiloted vehicles retain emergency lighting.

**Engineer (Human)**
The engineer is the basic human work unit. They have very limited combat capabilities, but are required to mine minerals, build structures, and operate machinery.

```
15 Hp
Armor 0
Base Damage 1
Melee
Speed 3
Size .5
```

**Sapper / Combat Engineer (Human)**
The combat engineer is a more expensive human work unit that has the same capabilities as a standard engineer, but also specializes in demolishing structures.

```
25 Hp
Armor  2
Base Damage 5
Bonus Damage
  + 15 (Against Structures)
Melee
Speed 3
Size .5
```

**Marine (Human)**
The marine is the basic human all-rounder combat unit.

```
30 Hp
Armor 4
Base Damage 10
Ranged (within 7.5 tiles)
Speed 3.5
Size .5
```

**Scout (Human, Vehicle)**
Requires a driver.

```
75 Hp
Armor 0
Speed 8
Passengers 0
Detection 5
```

**Jeep (Human, Vehicle)**
Requires a driver.

```
100 Hp
Armor 4
Speed 6
```

The Jeep is the workhorse transport for workers and cargo. Open ideas describe four passenger places; the rewrite needs to specify whether that count includes the driver.

**Flamer (Human) — Current game**
An infantry unit with a short-range area attack, produced at the Barracks. Its relationship to the proposed Plasmarine and plasma weapon roster remains undecided.

**Drill (Human, Vehicle) — Current game**
A piloted utility vehicle produced at the Garage. It clears rock or mesa tiles to open routes. Each cleared tile takes time and consumes gas; clearing cannot begin without enough fuel.



**Scavenger (Lightless)**
The scavenger is the most basic Lightless unit. Scavengers specialize in light harassment and act as information gatherers for the Lightless. They will test defensive boundaries often. If a scavenger is attacked it will retreat, if it receives little to no resistance it will signal to the other Lightless to apply pressure. Scavengers spawn passively. They also collect chyme, the Lightless resource formerly called blood, by dealing damage to units or structures. Scavengers can deliver collected chyme to Lightless structures, adding it to the Lightless participant's shared reserve for development.

```
Hp 15
Armor 0
Speed 5
Base Damage 5
```

**Stalker (Lightless)**
Stalkers specialize in picking off individual units in the dark. They will not enter illuminated areas (unless guided by a Darkmind). Stalkers spawn passively. Perception does not deter them: they can hunt unilluminated units even when those units or their surroundings are perceived.

**Ravager (Lightless)**
Ravagers are intended to be the "bunker busters" of the Lightless. Their specialty is dealing damage to structures. The Lightless will build a Ravager Spawner when they decide that you have structures worth destroying (what does this mean, how do you measure this, don't know yet).

```
Hp 150
Armor 10
Base Damage 10
Bonus Damage
  + 45 Against Structures

```

**Shade (Lightless)**
Shades are highly mobile, high damage dealers, with low health/armor. They specialize in lurking along illuminated boundaries and attacking units from a distance. Shades are immune to detection.

**Mother (Lightless)**
Specialize in transforming into Lightless structures. A mother is a slow moving Lightless that walks from the Nest to a particular location before transforming into a Womb, the precursor to a Lightless structure.

**Father (Lightless)**
Specializes in organizing the Lightless to coordinate attacks, often overriding the behavior of Lightless (like Stalkers and their aversion to light, or Scavengers and their tendency to retreat). Killing a Father during a coordinated attack will revert the Lightless to their standard behavior.

**Planned: Veil communication**
A Father uses the Veil to communicate with all Lightless connected to its Veil when coordinating an attack.

**Thresher (Lightless)**
Threshers are mobile defensive units that can bury themselves in the ground to avoid being illuminated. When burrowed they can attack units and structures and can only be attacked when detected by a scanner.

**Proposed: spawning requirement**
The Burrower concept in the open ideas requires a dedicated spawner. That prerequisite is carried here for consideration with the Thresher design; it does not exist in the current game.

**Queen (Lightless) — Proposed**
A very large, heavily armored mobile spawner that emerges for the final extraction. The open idea has it erupt from the destroyed hive after the objective is captured. The rewrite requires destroying the Nest to mine nacre. Whether a Queen encounter is included, and what triggers its emergence, remain undecided.

**Lightless behavior — Current game**
Lightless packs lurk at the fringe of illumination, gather, probe defenses, assault, and retreat. A runner probe withdraws as soon as it takes damage. A probe that threatens a target without resistance can prompt a larger assault. Stalkers flank support infrastructure, while brutes prioritize defenses and breach obstructing walls or gates.

Packs share local sightings and remember last-known positions for a limited time. Outside the core-theft alarm, they do not continuously track unseen units. Darkness makes exposed workers and infrastructure vulnerable; protective light discourages ordinary approaches but does not prevent a committed assault. Personal emergency lamps do not provide the same protection as defensive illumination.

Normal pressure increases over time through larger populations, faster replacements, and more frequent assaults. Damaging the hive alerts nearby packs. Core theft overrides normal probing and retreat with permanent pursuit. See [enemy behavior](v1/docs/enemy-ai.md) for the current pacing rules.

**Naming**
The current implementation uses Runner, Stalker, and Brute. The draft uses Scavenger, Stalker, and Ravager for the corresponding broad roles. Earlier ideas also use Probe, Hunter, Sniper, Tick, Burrower, and Darkmind for concepts now described as Scavenger, Stalker, Shade, Mother, Thresher, and Father. These are design-name correspondences, not evidence that the full roster is implemented. The Stalker description still uses Darkmind; Father is the coordinating unit described here.

#### Resources

**Chyme (Lightless) — Rewrite resource**
Chyme is a Lightless resource, formerly called blood. Scavengers collect it by dealing damage to units or structures and can deliver it to Lightless structures. Delivered chyme enters the Lightless participant's shared reserve and is spent to pay for producing units and constructing structures. It can fund production and construction throughout the Lightless participant's force.

The Lightless also generate chyme naturally over time. Passive generation may come from all Lightless structures or only certain structures; the producing structures remain undecided. Destroying the Nest grants the Lightless a massive additional influx of chyme.

Passive chyme generation and the Nest destruction grant also contribute to this shared reserve. Damage-to-chyme yield, passive generation rates, and the Nest destruction grant are tunable. Carrying and storage limits, individual production/construction costs, and when those costs are paid remain to be defined.

**Nacre — Rewrite resource**
Nacre is a resource mined from the destroyed Nest, replacing the earlier unique Hive Core objective. Destroying the Nest makes its nacre available for mining; nacre must still be gathered and transported.

Nacre can only be deposited at the extraction point. HQ and other resource receivers cannot accept it. The extraction point accumulates delivered nacre and must reach a specified threshold before extraction can be triggered. The player chooses when to start the extraction countdown after reaching the threshold and must defend the extraction point until it completes. Delaying the countdown allows additional nacre to be gathered for extraction at greater risk. Extra extracted nacre increases the player's match score and contributes to progression between matches. The threshold and countdown duration are tunable match values; initial values and mining and transport rules remain to be specified.

**Materials / Ore**
The basic construction and manufacturing resource. Engineers gather it from finite deposits and physically carry it to an appropriate receiver. The current game calls it Materials (MAT); a pending request in [todo.md](todo.md) renames it Ore.

**Methane / Gas**
A second resource used for fuel, some construction and production costs, and flame turret reloads. Generators consume it to meet electrical demand. The current game calls it Methane (CH4); the same pending request renames it Gas.

**Current game: delivery and storage**
Resources in a worker's or vehicle's inventory are cargo, not spendable reserves. They enter shared reserves only after delivery to HQ or a matching receiver. Material Depots accept materials; Methane Tanks accept methane. HQ accepts both. Storage structures increase the reserve capacity for their resource.

A receiver accepts only the amount that fits in available storage. Excess cargo remains with its carrier. Losing storage reduces capacity without deleting already banked resources; new deliveries wait until space is available.

**Current game: mining and extraction**
Engineers can gather by hand from adjacent deposits. A powered Extractor improves gathering from deposits under its footprint but still needs engineers and delivery. It does not directly add resources to reserves. An extractor can cover both resource types and draws from its remaining deposits proportionally. An offline extractor retains its mining assignments and waits for power.

Mining automation uses discovered deposits. A mining expedition continues across patches in its assigned field and returns to deliver cargo when necessary. Selecting a receiver as the expedition target chooses a nearby surveyed field of the matching resource.

**Match score and progression — Rewrite**
The amount of nacre successfully extracted contributes to both match score and progression between matches. Extracting extra nacre improves both rewards, giving the player a reason to delay extraction and accept additional risk. Scoring formulas, persistent progression rewards, and progression for Lightless players remain to be defined.

**Power**
Power is supplied through local networks rather than carried as cargo. HQ supplies a small amount without fuel. Generators provide additional capacity and burn gas according to served demand beyond HQ's auxiliary supply. Repeaters extend network reach without generating power.

A structure can be connected but lack enough available power to operate. Separate networks have separate capacity and demand. Losing a generator or disabling a repeater can interrupt a branch and take lights, defenses, or extractors offline. The current game assigns automatic consumer priorities; the rewrite's priority rules remain to be specified.

#### Structures

Footprint refers to the tiles that a structure occupies.

**Construction rules**
Blueprints require revealed ground, not current illumination. Once ground has been revealed, blueprints can be placed there even if it is no longer perceived or illuminated. Terrain, footprint occupancy, and resource requirements still apply.

A blueprint can be cancelled at any time before completion, including while an engineer is building it. Cancellation returns the full resources spent on the blueprint regardless of construction progress. If an assigned engineer determines that it cannot reach the blueprint to work on it, the blueprint is automatically cancelled with the same full refund.

**Planned: wall-mounted lights and turrets**
Lights and turrets can be mounted on walls. This mechanic will likely require a special commander or researched technology; the exact unlock is not yet decided.

**Current game: construction and maintenance**
Placing a blueprint spends resources immediately. An engineer must reach a work position on or adjacent to the footprint at the same elevation to complete it. A blueprint remains walkable until construction finishes, when occupants must safely clear the footprint. Engineers can continue to nearby unfinished structures or repairs after completing work.

Placement checks terrain, footprint occupancy, resource requirements, and access. The current implementation requires illumination at the site's center or an adjacent tile; the rewrite replaces that requirement with the revealed-ground rule above.

Building, repair and delivery interaction radii are measured from the unit center to the center of the nearest tile in the structure footprint. Larger unit definitions can use larger interaction radii while accounting for their collision radius. Engineers repair damaged structures using materials. Production structures train units over time through queues. Costs, work times, health, footprints, and operating requirements should be defined for each structure rather than inferred from its appearance.

The Human structure descriptions below summarize current roles unless marked Proposed or Planned. Forge remains a design placeholder. Planned Lightless mechanics, including the Veil and Briar defenses, are not implemented in the current game.

**HQ (Human)**

The landing base and primary receiver for both resources. It provides initial storage, emergency power, illumination, and production of engineers and scouts. It passively heals nearby friendly units, including occupants of nearby vehicles. Its destruction loses the current mission.

**Resource Depot (Human)**

Receives delivered materials and increases material storage capacity. It gives remote mining operations a closer delivery point. The current implementation calls it Material Depot; whether Resource Depot should accept multiple resource types is undecided.

**Wall (Human)**

A passive barrier that blocks passage and ground-level light. It shapes approaches and protects vulnerable structures but does not deal damage. Lightless breachers can attack walls obstructing their route.

**Gate (Human)**

A controllable passage through a defensive boundary. A powered, unlocked gate opens for friendly traffic and closes after the passage clears. A closed gate blocks movement and light. Locking, manual control, and power-loss behavior need an explicit final specification.

**Floodlight (Human)**

A powered source of protective illumination used to extend the base perimeter and expose nearby threats. Terrain and closed barriers affect its coverage. The current implementation calls it Spotlight.

**Machine Gun Turret (Human)**

A powered defense that attacks individual visible enemies with rapid fire. It has a finite magazine and reloads using materials. The current implementation calls it Minigun Turret.

**Generator (Human)**

A gas-fueled power source for a local network. It supplements HQ power and supports outposts when connected to consumers directly or through repeaters.

**Extractor (Human)**

A powered mining structure placed over one or more surveyed, nonempty deposits. Engineers operate it from accessible perimeter tiles. Its current footprint is seven hexes. Covered deposits remain available through the extractor until depleted; destroying the extractor exposes remaining deposits again.

**Forge (Human)**

**Proposed.** The draft includes this structure, but its purpose, inputs, outputs, and relationship to production or research have not been defined. It has no current implementation counterpart.



**Gas Tank (Human)**
Receives delivered gas and increases gas storage capacity. The current implementation calls it Methane Tank.

**Repeater (Human)**
Extends a power network's reach. It can be toggled off to disconnect its branch. Coverage and connection previews show whether planned structures will connect to the network.

**Scanner (Human)**
A powered sensor structure that provides approximate hostile contacts in darkness. It currently gives warning without revealing enemies for weapons fire. Its intended role in detecting burrowed units and enabling turret targeting needs to follow the final detection rules.

**Barracks (Human)**
Produces engineers, marines, and flamers in the current game. Its final roster, including whether combat engineers are produced here, remains undecided.

**Garage (Human)**
Produces scouts, jeeps, and drills. Vehicles need separately assigned drivers before they can operate.

**Laser Turret (Human)**
A powered defense with stronger, slower single-target shots and no ammunition reload. Its high power demand competes with other infrastructure.

**Flame Turret (Human)**
A powered defense that deals area damage to visible enemies at shorter range. It has a finite magazine and reloads using gas.

**Extraction Beacon (Mission)**
**Current game:** A ruined mission structure that engineers repair. It becomes the extraction destination for the Hive Core carrier and can be repaired again if destroyed.

**Rewrite:** The extraction point is the only receiver for nacre. It must be repaired, and its deposited nacre must reach the configured threshold before the player can choose to start the extraction countdown. The player must defend it until the countdown completes to win. Destroying a Human participant's extraction point defeats that participant.

**Hive / Nest (Lightless)**
The current Lightless Hive holds the Hive Core and has nearby defenders. It participates in reinforcement pressure and alerts nearby packs when damaged. The relationship between this objective Hive and the Nest from which Mothers depart is not yet defined.

**Rewrite: nacre source**
The Nest must be destroyed before its nacre can be mined. It cannot be rebuilt. Nest destruction opens the resource-gathering stage; it does not by itself give a Human participant victory. The Lightless continue pursuing their objective of destroying Human HQs or extraction points.

**Rewrite: Nest destruction escalation**
Destroying the Nest grants the Lightless a massive influx of chyme. Lightless structures also receive a permanent buff for the rest of the match that increases unit production and structure-building speed. This escalation gives the Lightless resources and faster development while Humans mine and transport nacre. The chyme amount and speed bonuses are tunable; their initial values remain to be defined.

**Planned: Nest alarm**
When attacked, the Nest can reach all Lightless connected to its Veil. This connectivity-based alarm is distinct from the current implementation's distance-based hive alert.

**Womb (Lightless) — Proposed**
The intermediate form a Mother becomes at the selected construction site before developing into a Lightless structure. Construction time, costs, vulnerability, cancellation, and the fate of the Mother need definitions.

**Spawner (Lightless) — Proposed**
A specialized structure that produces a particular Lightless unit. Open ideas also let it increase passive spawning for that species; destroying it reduces that pressure. Advanced species should depend on their required spawners rather than appearing arbitrarily. Whether the Hive permanently unlocks a species after its first spawner is built remains open.

**Upgrade Structure (Lightless) — Proposed**
A structure that improves Lightless damage, armor, or speed. One idea removes its bonus when the structure is destroyed. Whether upgrades belong to separate structures or to spawners is undecided.

**Briar (Lightless) — Planned**
A structure that passively produces smaller defensive structures on nearby Veil. Its defenses include Lightless walls, spikes, and spewers. Placement requires nearby Veil; production rate, placement choices, and limits remain to be defined.

**Wall (Lightless) — Planned**
A defensive barrier produced by a Briar on nearby Veil, themed to match Lightless structures. Its health, footprint, and interactions with movement and illumination remain to be defined.

**Spikes (Lightless) — Planned**
Floor traps produced by a Briar on nearby Veil. Spikes damage units occupying them. Damage, attack interval, and which units can be harmed remain to be defined.

**Spewer (Lightless) — Planned**
A small, one-tile ranged defensive structure produced by a Briar on nearby Veil. A spewer is a smaller version of the Regurgitator. Its damage, range, and attack behavior remain to be defined.

**Regurgitator (Lightless) — Planned**
A large ranged defensive structure, replacing the earlier Worm concept. Its footprint, damage, range, and construction requirements remain to be defined.

#### Orders and logistics

**Current game**
Units support contextual movement, attack, construction, repair, gathering, delivery, boarding, and objective orders. Immediate orders replace current work; queued orders continue after it. Stop clears assigned orders.

Attack-move engages visible enemies encountered along a route. Defend protects a location, unit, or structure and returns after a bounded pursuit. Patrol repeats a route. Escort keeps combat units with a worker or convoy.

Mining and exploration can be assigned to coordinated groups. Transport reserves a driver, boards workers into available seats, and leaves infantry outside as escorts. Without transport, engineers can travel on foot with protection. Mixed groups travel at the pace of their slowest walker. Exploration repeatedly seeks reachable unrevealed ground; mining repeatedly gathers and delivers from surveyed fields.

A direct order detaches a unit from its coordinated mission. Manual unloading cancels vehicle coordination. Scouts can investigate approximate sensor contacts within bounded distance and time before returning to the assigned route; investigation does not itself reveal the hostile.

#### Players, factions, and AI

Each player controls their own units. A player can play as Humans or as the Lightless. The current v2 demo is multiplayer only. Do not implement AI behavior until the player control interface is established for both factions. Local sandbox mode must allow switching between control of Humans, Lightless, or both factions within the running session.

A match has exactly one Lightless participant and at least one Human-faction participant. In the current demo, players must fill both factions; missing factions block multiplayer start. Once AI is added, it may fill either required faction when no player selects it.

Ownership, faction, and controller type are separate properties: ownership determines whose units an actor can command, faction determines its gameplay rules and available content, and controller type determines whether a human or AI issues its orders. Both factions must first be fully controllable by players; AI controllers are a later addition.

The pre-match configurator supports choosing Human or Lightless faction for each player; AI controller selection is deferred. For the time being, every match is a free-for-all with no teams. Each participant opposes every other participant, including those of the same faction. Choosing the same faction does not create an alliance. The configurator must enforce the faction limits above without AI fallbacks in the demo. Information and resource-sharing rules and structure ownership remain to be defined. The rewrite objectives above replace the existing Hive Recovery objective.

#### Networking and rollback for the rewrite

WebRTC multiplayer, using webrtc-coordinator for room coordination and signaling, is required. Rollback networking is required in the first playable multiplayer rewrite; it is not deferred to a later version.

The simulation must support deterministic fixed ticks, tick-stamped player commands with a consistent execution order, complete state capture and restoration, and replay from a restored checkpoint without rendering. Gameplay state includes random state, actor ownership and IDs, orders, resources, construction, visibility, Veil networks, and mission outcomes. Derived caches must be restored or rebuilt consistently.

The session layer retains recent checkpoints and command history, predicts missing remote input, and restores and re-simulates when late commands differ from predictions. Rollback must not duplicate presentation events or permanently commit match results and progression from speculative state.

The coordinator establishes signaling sessions; WebRTC transports game messages. Rollback belongs in a session layer around the headless core. Single-player uses the same gameplay core and content definitions.

Validation must cover checkpoint restoration and replay equality, delayed-command correction, desync detection, matching content and configuration, supported desktop/browser combinations, and recovery performance under representative simulation load. The current implementation's same-runtime replay tests do not establish these guarantees for the rewrite. Initial testing should prove restoration and deterministic execution before layering in the full roster.

#### Content authoring and tuning for the rewrite

The rewrite needs a content pipeline for authoring and tuning gameplay as part of the prototyping workflow. A pre-match configurator should support both single-player and multiplayer sessions, letting players experiment with values and behaviors before starting a match. The current demo supports multiplayer and a local sandbox, with single-player AI deferred until both faction control interfaces are established.

Content definitions should support more than editing the numeric stats of a fixed roster. The intended direction includes authoring entire units in the app through a structured format such as JSON. With the simplified 3D view, a unit definition can also describe its readable primitive shape, color, and label. JSON definitions combine existing capabilities, such as movement, weapons, mining, transport, burrowing, and Veil communication. Authors choose capabilities and configure their values; new capability logic is implemented in game code.

The workflow should let an author create or edit a definition, validate it, choose it in the match configurator, and test it in a session. Reusable presets and import/export should make experiments easy to repeat and share. Invalid definitions should identify the affected field and explain the problem before the match starts.

**Multiplayer and replay requirements**
A session needs one agreed set of content definitions and match settings. Multiplayer peers must verify that they are using matching gameplay content before play begins. Replays need to identify or retain the definitions and settings used for the session so later tuning does not silently change their results.

**Decisions still needed**
Define which content types are editable in the first version, how presets are saved and shared, how multiplayer distributes custom definitions, and whether tuning during a running match is supported. Pre-match configuration is required; live editing is not yet decided.

#### Presentation for the rewrite

The rewrite uses simple 3D mesh primitives with a locked top-down orthographic camera. Detailed art and decorative effects are deferred while gameplay is being prototyped and tested. Visual work should prioritize identifying actors, understanding the world, and explaining what is happening.

Units, structures, terrain, and resources should be distinguishable through shape, color, and concise labels where useful. Structure footprints, selection, facing, and destinations should be clear. Darkness and the Veil should communicate their gameplay state without obscuring information the player is entitled to see.

Useful information is a primary part of the presentation: health, armor, damage and bonuses, range, cargo and capacity, resource costs, power connections and demand, construction progress, current orders, and queued actions. Selection details and optional overlays should expose this information where it helps, while keeping the main view readable. Veil coverage and connectivity, illumination, perception, and detection should be inspectable within the player's visibility rules.

The aim is to make mechanics easy to understand and problems easy to diagnose during playtests. A more elaborate visual style can be revisited after the core mechanics are established.

#### Information and feedback

**Current game**
The minimap supports navigation and commands and retains discovered resource and objective markers. Selection exposes cargo, health, commands, costs, and relevant structure status. Electrical structures report their own network's capacity and demand. Placement previews show footprints and connection problems. Damaged visible actors display health bars.

**Proposed**
Further feedback includes rally points for production structures, visible queued command paths, clearer mining and command acknowledgments, and map markers that remain legible above darkness. Stats should make resource consumption, attack ranges, and damage areas understandable before the player commits to an action.

#### Remaining design decisions

These are unresolved design choices, not additional mechanics already approved for implementation. The settled rules are sufficient to begin the deterministic core, rollback/session layer, capability-based content pipeline, and simple top-down orthographic 3D view. Remaining rules should be resolved before implementing their affected features; numerical balance values can be exposed for tuning.

- **Content authoring:** JSON definitions compose existing capabilities; new capability logic is added in code. Set the initial editable content types, presets, multiplayer content distribution, and live tuning; see Content authoring and tuning above.
- **Players and objectives:** Matches are free-for-all, with exactly one Lightless participant and at least one Human-faction participant; players must fill both factions in the current demo; AI fallbacks are deferred until both faction control interfaces are established. The Lightless must defeat every Human participant to win, with destruction of a participant's HQ or extraction point defeating that participant. The first Human participant to extract with nacre wins and ends the match. Define structure ownership and information/resource sharing.
- **Visibility and targeting:** Perception and illumination provide the same visibility and targeting for ordinary units; only illumination causes light-specific effects. Detection alone permits turrets only. Define detection-only contact display and how Shade detection immunity, Thresher burrowing, and revealing melee attackers interact with these rules.
- **Light and behavior:** Perception does not cause illumination-specific reactions or damage Veil; Stalkers can hunt unilluminated units in perceived areas. Define what illumination counts as protective light, which species can cross it independently, and which need a Father. The current director can launch assaults without a coordinating unit.
- **Damage and armor:** Flat armor reduction is settled for now. Specify minimum damage, damage/armor types, bonus-damage ordering, attack intervals, friendly fire, and ray obstruction.
- **Names and roster:** Confirm Ore/Gas, Floodlight/Spotlight, Machine Gun/Minigun, Father/Darkmind, and Hive/Nest terminology. Confirm how Flamer relates to Plasmarine, and whether the listed Lightless correspondences should become final renames.
- **Vehicles:** Define driver eligibility, seats including or excluding the driver, passenger survival on vehicle destruction, and cargo capacities. The draft Scout has no passengers; open ideas describe one place, and the current implementation permits cargo, so seat and inventory rules need a deliberate choice.
- **Construction:** Revealed-ground placement, full refunds for cancelled blueprints, and automatic cancellation when an engineer determines a blueprint is unreachable are settled. Define repair costs, gate controls and power failure, and the commander or technology unlock for wall-mounted lights and turrets.
- **Economy and production:** Confirm shared reserves versus local inventories, storage-loss behavior, production queues and rally points, network priorities, Forge purpose, and whether research or crafting are part of the next core.
- **Veil:** Define growth rate and radius, terrain blocking and footprint interactions. Units do not block Veil growth; structures, blocking terrain, and illumination do, with a producing structure allowed to seed beneath itself. Define the rate of illumination damage to existing Veil. Lightless units connect from on the Veil or up to one tile away. Veil communicates globally across disconnected patches. Veil decays over time when its producing structure is destroyed. Surviving sources maintain overlapping Veil. Define the decay rate and what information alerts carry. Global communication removes network-merge and gap rules.
- **Briar defenses:** Define production rate, costs or limits, placement choices, and whether defenses survive or operate after losing their Veil or Briar. Specify wall blocking, spike targets and damage interval, and spewer/Regurgitator attack properties.
- **Lightless development:** Define Mother/Womb construction costs, spawner prerequisites, passive species, upgrade persistence, and how human expansion prompts new enemy structures. Scavengers collect chyme by damaging units or structures and deliver it to Lightless structures to add to the Lightless participant's shared reserve. Chyme also generates passively over time; decide which structures generate it. Chyme pays for producing units and constructing structures. Define yield, carrying/storage limits, production/construction costs, and when costs are paid. Whether Wombs receive chyme during construction remains open.
- **Mission and escalation:** Nacre is mined from the destroyed Nest and can only be deposited at the extraction point; reaching its configured threshold enables extraction to be triggered. Extraction uses a player-triggered defense countdown, which can be delayed to gather extra nacre. Define mining and cargo rules, deposit ownership with multiple Humans, threshold and countdown values, and whether deliveries continue during the countdown. Extra extracted nacre improves match score and progression between matches; define scoring and progression rewards, including progression for Lightless players. The Nest cannot be rebuilt; its destruction grants a large chyme influx and buffs Lightless structure unit production and construction speed for the rest of the match. Define the grant and speed bonuses, including whether structures built afterward receive the buff. Decide whether a Queen encounter is included. Define pressure limits and whether AI escalation depends on time, player development, Lightless infrastructure, or a combination.
- **Scope:** Beyond the planned wall-mounted lights and turrets and their likely commander or technology unlock, broader commander bonuses and research systems remain open. Specialized cargo vehicles, competing companies, infiltrators, and colony-sim modes also remain open ideas. These broader systems are not requirements of the rewrite until selected.

#### Source references

- [README](README.md): current playable mission, controls, starting scenario, economy, and power.
- [Gameplay balance](v1/docs/gameplay-balance.md) and [configuration](v1/config/gameplay.json): current rules and tunable values. Existing configuration distances are world metres; this draft's unit values use tiles and need explicit conversion during the rewrite.
- [Enemy behavior](v1/docs/enemy-ai.md): current pack behavior, information limits, escalation, and hive alarms.
- [Open ideas](ideas.md) and [pending requests](todo.md): proposed mechanics, alternate names, and unfinished decisions.
- [Completed feature records](v1/todo.md): links to implemented feature details.
- [Engine architecture](v1/docs/engine.md): current deterministic simulation and presentation boundary; technical reference rather than gameplay design.

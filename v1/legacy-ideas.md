# Open ideas

Concrete requests have moved to [v1/todo.md](v1/todo.md). These remain open questions.

Maybe other competing companies trying to poach the same macguffin

Maybe some creatures could steal bodies and enter your base as a neutral NPC... Or maybe it's a status effect that a unit can have eggs or something where they eventually erupt into a creature.

Maybe some vehicles are specialty carriers like a tanker for lots of gas but only two passengers, or a supply truck for lots of material but only two passengers, or an infantry vehicle that has no room for supplies but lots of room for units. 

Maybe Unit and structure upgrades would be useful (for your units and the lightless). That way the lightless can increase in difficulty as the match progresses.

Maybe the lightless can build their own structures on the map so you have to be aware of and squash their hives that produce units or be careful when assaulting their defensive structures... they have acid spraying worms (like factorio)

Pivot into colony-sim and base-building mechanics. Add more crafting. Maybe include modes that are more rts-like, but the base mechanics should support a more arbitrary play style.

Planned: mount lights and turrets on walls, likely unlocked through a special commander or researched technology. See [atd.md](atd.md) for the design.

Explore adding lights to turrets (maybe as an unlockable technology)

Add a scout unit (maybe a tiny drone). With a restriction tying it close to hq (maybe with an extendable range via antennas or other structures)

Settled construction rules: blueprints require revealed ground rather than illumination. A blueprint can be cancelled at any time before completion, including while building, for a full resource refund. If an engineer determines it cannot reach the blueprint to work on it, automatically cancel it with the same full refund. See [atd.md](atd.md) for the master design. Site suitability still needs to be checked before building.

Think about damage types and armor types. How units interact in combat (rock, paper, scissors). This includes units AND structures.

Better visibility on what resources a structure or unit consumes.

Better visibility on unit and structure stats. Health, damage, armor, power, inventory, movement speed, status, etc

Better visibility on damage areas (range, unit target, area of effect)

Turrets can target enemies detected by a scanner in the darkness.

Armor uses flat damage reduction for now. The armor-level and percentage-reduction proposal has been dropped; see [atd.md](atd.md) for the current design.

Maybe include a laboratory that let's you research upgrades for units. Spend time and resources on unlocking new abilities or passive unit upgrades.

**Engineer**
Basic human unit used for gathering material and building structures

**Marine**
Basic human military unit. Unit target damage

**Plasmarine**
Area of Effect damage, Intended to counter ticks, hunters.

**MG Turret**
Unit target damage. More damage than marines

**Plasma turret**
Area of effect damage

**Laser Turret**

**Rail Gun Turret**
Kinetic Armor Piercing, high damage. Intended to counter brutes, queens

**Rail Gun Unit**
Kinetic Armor Piercing, medium damage, one time. Intended to counter brutes, queens

**Jeep**
4 passenger vehicle, standard speed, standard armor, standard carrying capacity. Workhorse vehicle.

**Scout**
1 passenger vehicle, faster, low armor, zero inventory, built-in scanner.


Enemies should not be able to arbitrarily spawn all unit types.

**Probes**
Probes specialize in light harassment and act as information gatherers for the Lightless. They will test defensive boundaries often. If a Probe is attacked it will retreat, if it receives little to no resistance it will signal to the other Lightless to apply pressure. Probes spawn passively. low damage, low armor, melee

**Hunters**
Hunters specialize in picking off individual units in the dark. They will not enter illuminated areas. Hunters spawn passively. high unit damage, low structure damage, high armor, melee

**Snipers**
Snipers are highly mobile, high damage dealers, with low health/armor. They specialize in lurking along illuminated boundaries and attacking units from a distance. Snipers are immune to detection unless they are illuminated. high unit damage, low structure damage, ranged

**Tick**
Specialize in transforming into enemy structures. A large slow enemy type. Enemies deliver chyme (formerly blood) to ticks. Once a tick has enough chyme it can metamorphose into a structure. low damage, high kinetic armor, melee

**Brutes**
Brutes are intended to be the "bunker busters" of the Lightless. Their specialty is dealing damage to structures. The Lightless will build a Brute Spawner when they decide that you have structures worth destroying (what does this mean, how do you measure this, don't know yet). low unit damage, high structure damage, high armor, melee

**Burrowers**
Burrowers are mobile defensive units that can bury themselves in the ground to avoid being detected by visible light. When burrowed they can attack units and structures and can only be attacked when detected by a scanner. Burrowers require a spawner.

**Darkmind**
Unit that makes enemies "braver" in the light. Units around it will not retreat in the light.

**Queen**
Very large, heavy unit. Acts as a mobile spawner for the final extraction. Erupts from the hive once it is destroyed and the macguffin is captured.

**Regurgitator (replaces Worm)**
A large ranged defensive structure. Briars can passively produce smaller one-tile versions, called spewers, on nearby Veil. The Veil, Briar defenses, and Regurgitator are planned mechanics documented in [atd.md](atd.md).

**Spawner (x)**
A specialized enemy structure that spawns (x) and increases global spawn rate for passively spawning (x). Destroying this structure will reduce the global spawn rate for enemy units.

**Upgrade (x)**
A specialized enemy structure that can upgrade the damage/armor/speed of various enemy units. Destroying this structure will remove the bonus. (Maybe this should just be attached to the spawner structures instead)

**Hive**
Specialized structure. Contains the queen and the macguffin. Can spawn units of any type passively (if one or more of their spawners have been created ever)




Add commanders that provide a buff or special unit at the start of your session (e.g. floodlights on turrets, but they require 1 extra power)

Add map markers that appear above the darkness. Let exploring units automatically add markers to the map when discovering POIs.
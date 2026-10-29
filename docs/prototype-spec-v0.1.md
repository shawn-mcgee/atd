# Against the Darkness
## Prototype Game Specification (v0.1)

### Overview
**Genre:** Sci-fi RTS / Survival Tower Defense\
**Perspective:** Top-down 3D\
**Mode:** Single-player, endless survival\
**Primary inspiration:** Creeper World

Against the Darkness is a real-time strategy game where the player defends a space outpost against an amorphous, living darkness.

The player constructs defenses, manages limited resources, and reroutes power to survive increasingly dangerous waves.

**Core hook:** The player can build more defenses than they can power. Survival depends on anticipating threats and moving limited resources to where they're needed before the darkness overwhelms the base.

### Core Gameplay Loop
1. Observe the darkness and anticipate incoming surges.
2. Construct defenses and expand infrastructure.
3. Allocate limited power to critical systems.
4. Transport resources and reroute power as threats shift.
5. Repel the darkness, recover, and prepare for the next wave.
6. Survive as long as possible.

### The Darkness
The darkness is a continuous, living substance rather than a collection of conventional enemy units.

- Spreads across terrain and surrounds structures.
- Advances in periodic waves, with quieter periods between surges.
- Can split into disconnected regions.
- Disconnected darkness remains alive and dangerous.
- Can be damaged and pushed back by defensive structures.
- Becomes progressively more difficult to contain.

**Prototype implementation:** Represent darkness using a 2D density grid overlaid on the 3D environment. Each cell stores darkness density. Density spreads to neighboring cells, while defenses reduce nearby density.

Disconnected regions do not automatically disappear.

### Base Construction
The player constructs modular buildings on a grid.

Initial structures:

| Structure | Purpose |
|---|---|
| Command Core | Central base structure; destruction ends the run |
| Generator | Produces limited electrical power |
| Turret | Damages nearby darkness |
| Power Relay | Distributes power to connected structures |
| Storage Depot | Stores construction resources |

Buildings require construction resources and may require power to operate.

### Power Management
Power is the primary strategic constraint.

- Total power demand can exceed available generation.
- Only powered defenses operate.
- The player can redirect power between different defensive sectors.
- Reconfiguration takes time; changes are not instantaneous.
- Power connections are visible so players can understand the network.

**Prototype simplification:** Use discrete power sectors connected to the generator through relays. The player activates or deactivates sectors. Switching power allocation introduces a short delay.

### Resource Logistics
Resources are limited, and transporting them consumes time.

- Construction requires materials.
- Materials are stored at depots.
- Resources must be transported to construction sites.
- Distant construction takes longer to complete.

**Prototype simplification:** Use a single material resource and automated transport units. Avoid complex inventories or production chains initially.

### Wave System
The game alternates between buildup and pressure.

- Darkness remains present between waves.
- Each wave increases darkness production or aggression.
- Surges can originate from different directions.
- Players use quieter periods to repair, expand, and reposition resources.

The objective is survival, not elimination of the darkness.

### Controls and Interface
- RTS-style camera with pan and zoom.
- Mouse-based building placement and selection.
- Visible power connections and active/inactive structures.
- Darkness density visualized directly on the terrain.
- HUD showing available materials, power generation, power demand, wave number, and survival time.

### Visual Direction
Stylized, low-poly science fiction.

- Modular industrial structures.
- Clear visual distinction between powered and unpowered buildings.
- Darkness appears as an organic, shifting black mass.
- Lighting emphasizes the contrast between the illuminated base and surrounding darkness.

Use placeholder geometry for the initial prototype. Art polish is not a priority.

### Prototype Milestone
Build one playable map containing:

- A command core and generator.
- Placeable turrets and power relays.
- A spreading darkness simulation.
- Power allocation with switching delays.
- Basic construction resources and transport.
- Increasingly difficult darkness waves.
- A game-over condition and survival timer.

**Success criterion:** The player must regularly make meaningful decisions about which parts of the base to power. Simply building more turrets should not be sufficient to survive indefinitely.

### Out of Scope for v0.1
- Multiplayer
- Campaign or story
- Multiple planets or maps
- Research trees
- Complex resource production chains
- Detailed unit combat
- Advanced procedural terrain generation
- High-fidelity graphics

### Development Priorities
1. Darkness simulation and visualization.
2. Turret interaction with darkness.
3. Power generation, distribution, and rerouting.
4. Wave pacing and difficulty.
5. Construction and resource logistics.
6. User interface and playtesting.

**Design principle:** Prioritize the interaction between darkness, power scarcity, and logistics. Every additional system should strengthen that interaction rather than add complexity for its own sake.

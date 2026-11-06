# Codex Task: Rework Against the Darkness Prototype

## Objective

Refactor the existing *Against the Darkness* prototype into a **top-down 3D sci-fi horror RTS** focused on exploration, military units, illumination, logistics, and intelligent alien predators.

**IMPORTANT:** The previous prototype missed the intended gameplay fantasy. It focused on a spreading darkness simulation, static turrets, power scarcity, and constantly reallocating electricity between defenses. This was stressful and unsatisfying.

The new prototype must feel like commanding a military expedition on a permanently dark, hostile alien planet.

Inspect the existing project before making changes. Reuse working systems, assets, and architecture where practical, but do not preserve mechanics that conflict with the new design.

## 1. Core Fantasy

The planet receives no sunlight. Everything outside artificial illumination is pitch black.

The player commands soldiers, engineers, and vehicles to establish and defend illuminated outposts.

Horrifying alien creatures inhabit the darkness. They generally avoid illuminated areas, but they are intelligent, curious, and capable of coordinated attacks.

Resources exist beyond the safety of the starting base. Players must scan for deposits, organize expeditions, transport construction materials, establish illuminated outposts, and defend supply routes.

**Core loop:**

1. Scan unexplored territory for resources.
2. Assemble an expedition of engineers, marines, and vehicles.
3. Travel into the darkness using vehicle headlights and portable lighting.
4. Establish a defensible, illuminated outpost.
5. Extract resources and transport supplies between outposts.
6. Detect and repel creatures probing the perimeter.
7. Expand farther into the darkness.

## 2. RTS Units and Controls

Implement basic RTS controls:

- Left-click to select a unit.
- Drag-select multiple units.
- Right-click to move or issue contextual orders.
- Units navigate around obstacles.
- Selected units display selection indicators.
- Camera supports panning and zooming.

Implement three unit types:

**Engineer**
- Moves on foot.
- Constructs buildings using delivered materials.
- Repairs damaged structures.
- Cannot effectively defend itself.

**Marine**
- Moves on foot.
- Automatically attacks visible hostile creatures within weapon range.
- Cannot target creatures outside visibility.
- Can escort engineers and vehicles.

**Jeep**
- Moves faster than infantry.
- Carries a limited amount of construction materials.
- Can transport several infantry units.
- Has headlights that illuminate terrain ahead.
- Serves as the primary expedition vehicle.

Use simple placeholder models if suitable assets are unavailable.

## 3. Illumination and Visibility

Light is the central mechanic.

Implement a gameplay illumination system independent of graphical lighting, if necessary for performance and reliability.

Sources include:
- Starting base lights.
- Constructed floodlights.
- Jeep headlights.
- Optional portable lights carried by units.

Rules:
- Terrain outside illumination is obscured by darkness.
- Soldiers cannot detect or shoot creatures they cannot see.
- Creatures become visible when illuminated.
- Overlapping light sources create safer operational areas.
- Destroyed or disabled lights immediately compromise visibility.
- Creatures generally prefer remaining outside illuminated areas.

Avoid making the darkness itself a spreading damage field.

The darkness is an environmental condition that conceals predators.

## 4. Alien Creature AI

Implement one prototype creature type using a readable behavioral state machine.

**Behavior states:**

**Lurking**
- Remain in unlit territory.
- Wander or observe near the player's illuminated perimeter.
- Avoid unnecessary exposure to light.

**Probing**
- Small groups approach different perimeter locations.
- Test defenses and identify vulnerable units or structures.
- Retreat when encountering significant resistance.
- Gather observations about encountered defenses.

**Staging**
- Creatures gather in darkness outside a selected perimeter location.
- Give the player a short opportunity to notice suspicious movement or scanner activity.
- Do not expose the exact attack location through arbitrary UI announcements.

**Assault**
- Creatures commit to an attack.
- Target exposed personnel, lights, and vulnerable infrastructure.
- Attack in groups rather than individually charging the nearest structure.
- Retreat or regroup when appropriate.

Enemy decisions should use information creatures could plausibly have gathered. Avoid omniscient knowledge of player defenses.

For the prototype, use simple heuristics rather than sophisticated machine learning or complex planning.

## 5. Construction and Logistics

Implement the following structures:

| Structure | Function |
|---|---|
| Command Center | Starting headquarters |
| Floodlight | Illuminates a large area |
| Supply Depot | Stores construction materials |
| Resource Extractor | Produces materials at discovered deposits |
| Defensive Turret | Automatically attacks visible creatures |

Construction requirements:

- Engineers must physically reach construction sites.
- Construction consumes materials delivered to the location.
- Jeeps can transport materials from depots.
- Construction takes time.
- Structures can be damaged and repaired.

Keep the resource economy simple. One material resource is sufficient.

**Remove the previous power-reallocation mechanic.** Do not require players to disable existing defenses to activate others.

Power generation may be simplified or treated as automatically available for this prototype.

## 6. Scanning and Expansion

The player starts with a small, established, illuminated base.

Implement a scan command that reveals the approximate location of a nearby resource deposit.

The player must:
1. Send a jeep carrying engineers, marines, and materials.
2. Travel beyond the starting base's illuminated perimeter.
3. Establish a floodlight.
4. Build a resource extractor.
5. Defend the new outpost.
6. Transport extracted resources back to the starting base.

Vehicle headlights should provide enough illumination for a carefully managed expedition to survive.

Unprotected units wandering into darkness should be extremely vulnerable, but entering darkness must not cause instant scripted death.

## 7. Gameplay Pacing

The previous prototype overwhelmed the player too quickly.

Correct this by implementing deliberate pacing:

- Begin with a safe period for learning controls.
- Introduce isolated creatures before coordinated attacks.
- Allow meaningful recovery and preparation between threats.
- Make enemy activity observable before major assaults.
- Avoid constant attacks from every direction.
- Give players time to enjoy building and organizing their base.

The game should generate tension through uncertainty and anticipation, not nonstop emergencies.

The first expedition should be achievable without perfect play.

## 8. Prototype Scenario

Build one playable scenario titled **First Expedition**.

**Starting conditions:**
- One illuminated command center.
- Two engineers.
- Four marines.
- One jeep.
- A supply depot with construction materials.
- A nearby resource deposit hidden in darkness.

**Objective:**
Establish an illuminated mining outpost and deliver one shipment of extracted resources back to headquarters.

**Threats:**
- A few creatures stalking the expedition.
- Small probing attacks against the new outpost.
- One coordinated assault after the outpost becomes operational.

**Victory:** Successfully deliver the resource shipment.

**Defeat:** Lose the command center or all remaining personnel and vehicles needed to complete the mission.

## 9. Visual and Audio Direction

Use a readable, low-poly sci-fi style.

Prioritize:
- Strong contrast between illuminated and unilluminated territory.
- Visible headlights and floodlight cones.
- Distinct silhouettes for military units and monsters.
- Clear feedback for selection, movement, construction, and attacks.
- Unsettling creatures that are most frightening when partially revealed at the edge of illumination.

Use existing assets where possible. Placeholder geometry is acceptable.

Do not spend excessive development time on art polish.

## 10. Technical Priorities

Implement in this order:

1. Inspect and refactor the existing project.
2. RTS unit selection, movement, and orders.
3. Gameplay illumination and visibility.
4. Marine targeting and combat.
5. Jeep headlights, cargo, and transport.
6. Engineer construction and resource delivery.
7. Creature lurking and probing behavior.
8. Staging and coordinated assaults.
9. First Expedition scenario.
10. UI improvements, balance, and bug fixes.

Keep systems modular so new units, buildings, and creature types can be added later.

Avoid unnecessary complexity, large frameworks, or premature optimization.

## 11. Acceptance Criteria

The prototype is successful when:

- I can select and command individual units and groups.
- I can organize and escort an expedition into darkness.
- Jeep headlights visibly reveal the environment.
- Marines engage only creatures they can detect.
- Engineers construct floodlights and buildings using delivered supplies.
- Creatures lurk outside illuminated areas and occasionally probe defenses.
- A coordinated attack provides recognizable warning signs before occurring.
- I can establish a mining outpost and return resources to headquarters.
- Gameplay provides breathing room for planning and base construction.
- The experience feels like an RTS expedition into a hostile alien environment, not a static tower defense game.

## 12. Execution Instructions

Do not stop after producing a design document.

Inspect the project, implement the changes, and run available build and validation checks.

Make reasonable implementation decisions where details are unspecified.

Preserve existing functionality that supports the new direction, but freely remove obsolete spreading-darkness, power-switching, and relentless-wave systems.

If the entire specification cannot be completed in one pass, prioritize a coherent playable vertical slice over a collection of partially implemented systems.

At completion, summarize:
- What was implemented.
- What was removed or replaced.
- How to play the updated prototype.
- What remains incomplete.
- Any build or runtime issues.
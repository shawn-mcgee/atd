# Browser alpha specification

The target is the complete set of confirmed systems, built in dependency order and integrated into one browser-only alpha. Native Windows/Linux exports are deferred. This is a large RTS milestone: multiplayer synchronization and autonomous expeditions are substantial systems in their own right. Staging implementation provides working checkpoints without declaring those systems out of scope.

The repository contains a runnable foundation with a Godot project, configuration loading, early simulation, and a Trystero adapter. This document defines the full target and acceptance criteria. See [implementation status](implementation-status.md) for the systems actually implemented; the complete alpha is not finished.

The engine is **Godot**, using **3D presentation**, GDScript, Compatibility rendering, and a single-threaded web export. Browser builds are deployed to **GitHub Pages and itch.io**. Players host multiplayer through **Trystero/WebRTC**, integrated through Godot's browser JavaScript bridge. The proposed authority model runs the simulation in the host player's browser. See the [engine and distribution plan](engine-and-distribution.md) and [networking plan](networking.md). Native packaging and desktop WebRTC integration are not alpha requirements.

## Included

- A configurable, seeded hexagonal map with cliffs, rich resource fields, a randomly chosen Medusa corner, and up to five separate Commonwealth corner starts. The Medusa must be scouted.
- Continuous unit movement, hex-aligned construction, collision, Walls, controlled Gates, multiple-hex structures, and Excavator clearing.
- Single-player CPU Lightless and player-hosted Trystero/WebRTC multiplayer competition in the browser, with pause/orders during pause and speed changes in single player, and lobby-selected speed in multiplayer.
- Every currently named unit, vehicle, structure, and resource in the README, including Glands and Chyme Glands.
- Physical resource collection, mixed cargo, global storage, configurable Depots, buffered production, recipes, personnel sources, kits, drivers, passengers, and commandeering.
- Individual gathering and the complex mining expedition, including role assignment, convoy travel, lighting, loading, delivery, and interruption recovery.
- Power footprints, connected capacity, whole-number demand, fuel, fixed brownout penalties, blackout recovery, and switching structures off.
- Illumination, vision, fog-of-war memory, detection, Shade targeting, Thresher burrowing, guaranteed-hit weapons, flame areas, armor, repairs, and healing.
- Gloom health, growth, withering, communication, passive and manual spawning, population caps, stances, Fathers, recruitment, and upgrade dependencies.
- Four initial Fabricator armor upgrades: one each for Engineer, Marine, Flamer, and Lancer. The initial Gland upgrade is the already discussed armor effect, alongside Chyme income Glands.
- One optional player-controlled Lightless slot, with structure placement, Womb upgrades, Medusa stance selection, and Father-based unit coordination.
- Nacre harvesting, delivery, extraction defense, multiplayer elimination, and retaining the winner's delivered Nacre as currency.

## Explicitly deferred

Native Windows/Linux exports, desktop release/download publication, and native WebRTC integration are deferred until after the browser alpha. The extraction boss, lobbed grenades and other future attack patterns, unique commander units/abilities, and purchases using between-match Nacre are not designed or included yet. Factions use their current common roster. Do not invent unique commanders or progression benefits to fill those gaps.

Commander selection differences are a later content layer. For the first playable, lobby slots must identify players independently of faction color, so two players selecting the same faction remain distinguishable without giving them new abilities. Unique commander content remains pending.

## Extraction without the boss

`features.extractionBoss` is false. Extraction still requires 500 Nacre, holds up to 1,000 at the Anchor, and requires the Anchor to survive 90 seconds. The last surviving Commonwealth player can also win immediately in multiplayer.

No boss emerges, no emergence destroys nearby structures, and no boss-triggered harvesting cutoff occurs. Nacre therefore remains harvestable during extraction in the first playable, with ordinary logistics and delivery still required. This is the explicit first-playable interpretation of excluding the boss, not an additional currency source.

Ordinary Lightless provide the assault. The provisional CPU policy favors active extracting Anchors, starting with the shortest remaining countdown, then path distance and stable player ID for ties. Fathers can still override their recruited units. If that Anchor is destroyed, its player is eliminated and the CPU chooses another active extraction or resumes ordinary Attack targets. No additional spawn buff is introduced beyond the existing Medusa-death buff.

When the boss is added later, only the first extraction summons it, nearby structures are destroyed, and further Nacre harvesting ends. Its actual combat design remains open. Disabling the feature must disable those linked effects together rather than leaving an invisible boss event.

## Prototype implementation decisions

The following fill coordination and implementation gaps. They use existing mechanics and remain reviewable choices rather than new confirmed content.

### Queues and personnel

Operator orders from the player and automatic personnel requests share the personnel source's Operator queue in arrival order. Engineer kits use the separate kit queue. Production from each queue is displayed at its own side of the structure. A request is paid once, tagged with its destination, and dispatched there when ready.

If a personnel destination disappears, the Operator remains at its source rather than being destroyed. A requester with a destroyed personnel source stops requesting and shows the missing source; it does not silently switch the player's configured choice. The player can assign another existing Operator or choose a new source.

A vehicle or kit can finish before its requested Operator arrives. The vehicle waits unstaffed; the kit waits in its five-slot queue. An Operator waiting for a kit does not block assembly. Completed kits retain their original order for pickup. Five completed kits block additional orders, not collection.

One upgrade is worked at a time per Fabricator. Engineers add work linearly; leaving pauses work without erasing progress. One armor upgrade can be purchased per specialization, preventing concurrent duplicate purchase in another Fabricator. Its cost is paid immediately, cancellation is refundable only before work starts, and destruction does not refund the queue.

Manual Lightless queues work one order at a time alongside passive production. If a required Womb unlock disappears, retain that Medusa order's existing progress but pause it until the unlock is restored or the order is canceled. Cancellation refunds it only if work never began. If multiple structures compete for a cap, ready manual spawns resolve before passive spawns, with structure and order IDs breaking ties.

### Construction and interaction

Only one Anchor may exist per player. The starting Anchor already occupies that allowance; losing it eliminates the player. It cannot be replaced after defeat. The Medusa is also a unique starting structure.

Construction and repair interaction ranges are measured from collision boundaries. Construction work raises health; multiple Engineers add their rates without diminishing returns in this preset. A repair order on an unfinished building uses construction work and does not charge a second repair cost. On a completed vehicle or structure, repair consumes whole Ore cycles and restores only missing health.

Unfinished structures occupy their footprint and can be damaged, but provide no production, power, light, detection, or upgrade effects until completed. Their configured base armor applies while unfinished. Anchor healing affects biological units only. Completed Lightless structures regenerate independently of Gloom; gestating structures receive only their construction health gain.

Whole fuel or repair units pay for finite working intervals; fractional resource inventory is not introduced. A processing batch claims inputs and space before starting, retains progress through power loss, and places output into its buffer only on completion. Recipes currently have one output resource each.

### Gates and terrain

An unlocked Gate opens only for an owning friendly unit whose active route crosses it. Locking preserves its player-selected state. An open Gate can physically be traversed by any unit; enemies do not automatically operate it. Automatic closure waits until no unit occupies its collision area and the close delay has elapsed. A manual close request also waits for occupancy to clear rather than crushing or trapping a unit.

The boundary wall cannot be cleared. Ordinary cliffs can be cleared by an Excavator; partial cargo room accepts as much of the Ore yield as fits and loses the excess. Cleared rubble blocks neither movement nor construction.

### Map generation

The deployment seed is blank by default and chooses a fresh random seed outside the simulation. Entering an explicit seed reproduces the layout. The host distributes its chosen seed to guests; the seed-field tooltip retains the last deployed value for replay.

Use an axial-coordinate hex disk. Inset all six candidate corners by `map.anchorEdgeInsetTiles`. Reserve one corner for the Medusa using the seeded random generator. Among the remaining five, choose the player subset with the greatest minimum pairwise distance, then greatest total pairwise distance, using seeded randomness for equally good layouts. Place the initial Scavengers relative to the Medusa and fill its initial Gloom radius, clipped to map tiles. Its corner starts undiscovered. On death, the Nacre deposit occupies the Medusa's actual cell; snapshots synchronize resource types only for explored cells, without publishing an undiscovered corpse coordinate.

Starting fields must fit within their Anchor's unblocked vision and remain reachable without excavation. They override obstruction placement. Validate a reachable route from every starting area to a work/attack position around the Medusa. Retry or carve only enough cliffs to satisfy that guarantee. Other fields may remain obstructed or unreachable. Use the seed for field-size selection and other random choices so the same settings and seed reproduce a map.

### Lightless behavior

Unrecruited units begin in Probe stance under the provisional CPU. A Scavenger tests a known reachable enemy target; if it deals damage and receives none during the configured resistance window, it signals eligible nearby Lightless to Attack. Taking damage before commitment causes retreat to reachable Gloom. Gather retreats to the nearest reachable Medusa or Stoma after any damage or a full load, deposits, and chooses another known target. If no deposit organ is reachable, retain cargo and wait on reachable Gloom.

Defenders choose a threatened structure and stay within its defensive radius. Structures distribute requests among available non-recruited units rather than stealing Father recruits. Probe and attack signals never override a Father. Mothers continue construction tasks and Fathers continue coordination tasks regardless of their global stance label.

Completed Glands connect to one adjacent Womb of the corresponding type. If several qualify, retain a valid current connection, otherwise select the nearest stable Womb ID. A surviving disabled Gland can reconnect to a replacement of the same type. No Womb supports more than six Glands, and no Gland is counted twice. Disabled upgrade Glands still count against their colony-wide construction cap until destroyed.

Recruit transfer is atomic: verify the new Father's range/network eligibility and roster capacity, then release the old assignment and apply the new Father's stance. A failed transfer leaves the original assignment intact. Fathers cannot recruit other Fathers.

### Provisional CPU development policy

Every decision interval, the CPU considers only discovered targets plus its special knowledge of Anchor locations. Gloom reveals tiles; Anchor coordinates do not reveal hidden armies or deposits.

Maintain a small Chyme reserve and the configured desired Mothers/Fathers through paid production when population permits. At the expansion interval, send an available Mother to a known unoccupied site near the existing Gloom frontier. Build Wombs using the configured type priority, skipping unavailable sites and capped/duplicate goals. Prefer one armor Gland for a supported type and one income Gland per Womb before repeating expansion. All costs, gestation, slots, type caps, and physical placement rules still apply.

Use existing structures' defense calls, Scavenger probes, and Father recruitment to organize responses. Do not transfer another Father's recruits automatically in the initial CPU policy. The testing player can experiment with that capability manually. After Medusa death, the global Attack response and permanent Womb buff replace ordinary global Probe behavior, while Fathers retain the specified recruited-unit override.

This policy is a functional baseline for testing, not a settled strategic AI. Difficulty variants and learned strategies remain future design work. Decision intervals, type priority, reserve, desired counts, and expansion intervals are data in `lightless`.

### Combat and visibility details

Idle acquisition prioritizes an explicit target, then an eligible attacker, then the closest eligible hostile, with stable IDs for ties. Defensive units obey their intended-position leash, including concealment pursuit. Preserve player stances in expeditions and after elimination; do not silently replace them.

Current unit-target attacks require an unobstructed shot at launch. A launched hit is not canceled by later concealment or a Gate closing. Flame geometry is a heading-facing cone with per-tick damage; it damages only what the obstruction test reaches, and never damages buried units. A Thresher remains unburied during its burrow transition and buried until its emerge transition completes. Transitions cannot be interrupted except by death.

Detection is passive within the Scout/Radar ranges in the preset. It is a tile occupancy indication rather than unit identification, and never reveals Shades. Personal vision and vehicle vision belong to the owning player. Global friendly vision can make a distant friendly-observed target eligible, but never bypasses weapon range, obstructions, buried detection, or Shade illumination requirements.

Damage available for Chyme generation is actual health removed after all armor, clamped to remaining health. Overkill, minimum-damage calculation artifacts, and damage prevented by armor do not create Chyme. A unit already full loses the excess. The initial minimum-damage mode clamps at zero but remains configurable for later tuning.

### Elimination and rewards

Losing the sole Anchor removes player control. Assets retain orders, stances, inventories, ownership, and normal resource use; vehicles unload everyone immediately. Subsequent standing complex-command logic may board again where that is part of its existing order. This one-time unload does not silently cancel the expedition.

An eliminated player cannot issue new commands or win an extraction. Their assets remain hostile according to their original ownership; neutral stance is not forced. An elimination winner receives only Nacre already in their Anchor, not cargo or enemy inventory. Between-match spending remains undesigned; record the earned currency without inventing purchases.

## Delivery sequence and acceptance

1. **Simulation and transport foundation:** Seeded map, continuous movement, collision, placement, commands, and resolved settings. In parallel, prove Godot-to-Trystero packet exchange and host-confirmed state between browser clients, including Pages-to-itch.io rooms. Prove the same inputs and seed produce consistent host state before adding many interacting systems.
2. **Economy and personnel:** Direct mining through advanced recipes, storage overflow, production queues, kits, and drivers. Starting stockpiles must reach every material tier without requiring an unavailable advanced material.
3. **Visibility, power, and combat:** Show personal vision without light, working vehicle lights, Gloom suppression, detection restrictions, damage, healing, repairs, brownout, and latched blackout recovery.
4. **Expeditions and Lightless:** Repeated group hauling with losses and interruptions; free/manual spawning at shared caps; Glands; recruitment and stance overrides; testing controls; baseline CPU development.
5. **Complete single-player match:** Kill Medusa, harvest/deliver Nacre, survive 90 seconds, and record reward. Boss-linked effects remain disabled. Elimination and resource loss behave as documented.
6. **Browser multiplayer release gate:** Two-to-five-player Trystero matches with host-authoritative inventory, orders, settings, population, damage, and victory results. Test contested harvesting, simultaneous extractions, defeated assets, last-player victory, cross-site browser rooms, host/client disconnection policy, and configuration mismatch rejection. Desktop executables are not a release gate. Networking work begins alongside the foundation rather than being retrofitted after stage five.

Each stage is an integration checkpoint, not a different promised scope. The first playable is complete only when the included systems work together in the full match and multiplayer checks pass. Proposed data can be validated now; runtime behavior, balance, networking, and AI cannot be verified until the game exists.

## Still requiring product or implementation decisions

- Exact Godot and Trystero versions, signaling strategy, TURN configuration if needed, browser minimum requirements, persistence location, and the 3D asset pipeline. Godot, 3D presentation, the StarCraft II-style camera, browser-only alpha, player hosting, and Trystero/WebRTC are decided. Native Windows/Linux targets are deferred.
- Unique commander roster and abilities, additional Fabricator/Gland effects, and between-match purchases.
- Boss combat and final balance, explicitly deferred.
- Simultaneous-victory tie handling and final user interface layout remain open. Host loss ends the match without recovery. Non-host departure eliminates the player while assets retain their orders and vehicles unload; reconnecting does not restore control.

The settings and algorithms above reduce open mechanical details; they do not replace those remaining decisions or playtesting.

# Against the Darkness: 2D asset generation brief

This is a handoff for generating art, not a gameplay change. It covers the current roster in `engine/expedition_rules.gd` and footprints in `engine/structure_footprints.gd`. The proposed seven-cell extractor in root `todo.md` is not implemented: generate the current single-cell extractor first.

## Art direction

**Look:** painted sprites for a classic science-fiction RTS, viewed directly overhead. A stranded industrial expedition survives on a sunless alien planet. Human equipment is practical, battered, modular, and easy to distinguish at small sizes. Alien creatures are unsettling animals with readable anatomy, not clouds of black smoke. Favor strong silhouettes and a few broad material regions over intricate surface noise.

**Projection:** true orthographic top-down, looking vertically at the ground. Show roofs, helmet tops, shoulders, vehicle decks, and creature backs. No horizon, perspective convergence, visible front facades, or isometric side faces. This pack fits the current overhead renderer and rotating camera. An eventual isometric view would need a separate projection pass; do not mix isometric and overhead sprites in this pack.

**Rendering:** restrained hand-painted shading, crisp silhouettes, modest edge highlights, slightly exaggerated functional details. Smooth raster art, not pixel art, vector clip art, toy-like low-poly rendering, or photorealism. Details must read when an infantry sprite is displayed roughly 12–24 pixels across. Avoid tiny bolts as the primary distinguishing feature.

**Human palette:** blue-gray steel `#526573`, charcoal rubber `#222C35`, pale worn panels `#AAB8B9`. Small teal identification strips `#70C8BD`; amber safety paint `#D5A45C`. Engineers carry more amber; marines more desaturated blue; flamers rust-orange. Vehicles share the same chassis materials.

**Alien palette:** dark plum shells `#45394D`, muted violet-gray flesh `#76677A`, burgundy joints `#694052`, limited pale bone `#B2A59B`. Small warm pink sensory organs `#D18091`. Give shells enough value separation to remain visible against dark ground. No large emissive alien outlines.

**Ground/resources:** cool gray-brown basalt, sparse dusty scratches, occasional muted violet mineral staining. Materials are angular pale teal mineral clusters; methane appears as olive-green vent deposits with pressure fissures. Color is a secondary cue: crystal facets and gas vents must have different shapes.

**Lighting:** neutral, soft ambient illumination baked into surfaces, with restrained bevel shading. No cast ground shadows, light cones, broad glows, dramatic directional sun, or darkness painted over sprites. Game lighting controls visibility. Deliver emissive hardware separately if possible: lamps, headlights, warning lights, scanner indicators. An unpowered structure must remain legible without these layers.

**Never include:** names, letters, numbers, logos, health bars, selection rings, grid lines, placement outlines, terrain backgrounds behind objects, decorative framing, or watermarks.

## Shared technical contract

- Final deliverables: individual transparent RGBA PNGs, sRGB, straight alpha, plus the original layered file when available. Keep external backgrounds fully transparent; no checkerboard painted into the image. Terrain tile images have opaque interiors and transparent exteriors.
- Canonical scale: **64 source pixels per world unit**. One pointy-top hex has circumradius **64 px**, width **110.851 px**, height **128 px**. Neighbor centers are `(110.851, 0)` and `(55.426, 96)` pixels apart. These are source-art dimensions, not fixed display sizes.
- One-cell structure bodies fit inside a hex of radius **51.2 px**, or 80% of tile radius. Small antennas/barrels may overhang visually; do not imply extra occupied cells. Collision and placement remain simulation data.
- North/front is image up: world `-Z`. All mobile units use that heading in the initial pack. Runtime rotation provides arbitrary headings, so do not generate eight or sixteen facings initially.
- The pivot is the entity's simulation position projected onto the ground. For every sheet below, use the exact cell center as pivot, even when the visible image is asymmetric. Never recenter the object by its visible bounding box. Include pivot coordinates in a small manifest.
- Common layers, when supplied: `body`, `emission`, and optional moving `head`/`rotor`. All layers retain identical canvas dimensions and pivots. Prefer clean layered source files over asking an image model for a second perfectly registered mask image. Masks can be extracted during asset preparation.
- Keep at least 8 transparent pixels clear around the cell boundary. Preserve intentional internal openings, such as a gate passage. No automatic tight trimming or scaling each sprite to fill its cell.
- Provide each animation as equal-size frames with unchanged pivots and scale. Do not invent extra machinery between frames. Animated effects end with transparent pixels rather than an opaque smoke rectangle.
- Filenames use the internal keys below, lowercase snake_case: e.g. `engineer_idle_00.png`, `generator_body.png`, `turret_head.png`. Runtime destination: `project/assets/sprites/<category>/`; editable sources: `project/art_source/sprites/`. These directories are proposed for the later integration pass.
- Per-asset metadata: `id`, `file`, `canvas_px`, `pivot_px`, `heading` (`north`), `layer`, and optional `state`, `frame`, `fps`, `attachment_px`. Turret heads additionally identify their barrel muzzle position; lamps identify emitter positions.

## Eight initial image batches

Standalone ready-to-send prompts: [Batch 1](asset-generation-batch-1.md), [Batch 2](asset-generation-batch-2.md), [Batch 3](asset-generation-batch-3.md), [Batch 4](asset-generation-batch-4.md), [Batch 5](asset-generation-batch-5.md), [Batch 6](asset-generation-batch-6.md), [Batch 7](asset-generation-batch-7.md), [Batch 8](asset-generation-batch-8.md). Attach your approved Batch 1 sheet as the style reference for each later batch.

Generate **one contact sheet per row** below. Supply the shared art direction and technical contract with every request, followed by that sheet's asset descriptions. Cells are in the listed order, left to right, then top to bottom. Do not add a visible grid or captions.

| Batch | Grid × cell size | Final sheet size | Contents |
| --- | --- | --- | --- |
| 1. Characters | 3 × 2, 128 px | 384 × 256 | Engineer, Marine, Flamer, Runner, Stalker, Brute |
| 2. Vehicles | 3 × 2, 256 px | 768 × 512 | Scout, Jeep, Drill; matching three wrecks |
| 3. Large buildings | 2 × 2, 512 px | 1024 × 1024 | Command Center, Generator, Barracks, Garage |
| 4. Utility buildings | 3 × 2, 256 px | 768 × 512 | Depot, Methane Tank, Repeater, Spotlight, Scanner, Extractor |
| 5. Weapons | 3 × 2, 256 px | 768 × 512 | Three turret bases; matching minigun, laser, flame heads |
| 6. Objectives and ramps | 3 × 2, 512 px | 1536 × 1024 | Beacon ruined/working, Hive intact/breached, built/natural ramp |
| 7. Terrain and connections | 4 × 4, 256 px | 1024 × 1024 | Sixteen cells listed below |
| 8. Items and effects | 4 × 4, 128 px | 512 × 512 | Sixteen cells listed below |

These are **delivery layouts**, not a promise that an image model will obey exact dimensions. Generate at a supported resolution, preserve proportions, then crop, align, and pack mechanically. If exact geometry is unreliable, provide guide silhouettes from the footprint formulas below. Do not spend repeated image requests correcting one-pixel placement. Review each sheet before producing animations. Keep all sheets at the same world scale after preparation; larger canvases provide padding, not larger equipment.

For low-cost iteration, generate batches **1, 2, 3, and 7 first**. Approve scale and style in-game, then generate 4–6 and 8. Eight sheets are the initial target; a bad individual cell should be regenerated alone, not by replacing an approved sheet.

## Batch 1: characters

128 × 128 cells; pivot `(64, 64)`. Neutral standing pose facing up. Keep the projected body near the pivot; carried equipment may extend forward. Boots must not be drawn like a front-facing portrait.

| ID | Detailed description and functional silhouette |
| --- | --- |
| `engineer` | Compact expedition technician in a sealed charcoal work suit with amber shoulder armor. Rounded helmet, one bulky utility backpack, and a short welder held forward-right. Visible tool pouch on the opposite hip. Body approximately 32 × 40 px, excluding optional sparks. Distinguish through backpack and tool rather than a rifle silhouette. |
| `marine` | Disciplined infantry in desaturated blue armor, broad shoulder plates, compact helmet, narrow rear pack. A clearly readable rifle projects forward. Approximately 34 × 42 px including weapon. Keep armor less bulky than the flamer, with a narrow waist and clean shoulder-to-rifle silhouette. |
| `flamer` | Heavy infantry in charcoal armor with rust-orange heat shielding, two rear cylindrical fuel bottles, thick hose, and a short wide flamethrower nozzle. Approximately 40 × 46 px. Wider and more back-heavy than the marine; no flame baked into the idle art. Fuel hardware should read from above. |
| `runner` | Fast, low alien predator: narrow teardrop carapace, four long splayed limbs, thin rear abdomen, and two small forward sensory pits. Approximately 32 × 42 px. Emphasize stretched limbs and a light body, with pale shell-edge accents. Its north-facing head is unmistakable. |
| `stalker` | Medium ambush predator with six articulated legs, layered plum dorsal plates, pointed shoulders, and a broad low head. Approximately 42 × 48 px. A symmetrical segmented spine and hooked front limbs give it a deliberate, searching appearance distinct from the runner. |
| `brute` | Heavy predator with eight short, thick supporting limbs and a shield-like armored back. Approximately 52 × 56 px. Broad front armor, large mandibles, thick burgundy joints, and a small rear abdomen. Read as a heavy quadruped-like mass from far away despite the additional limbs; avoid a visually flat round blob. |

Initial pack: one idle image each. Later animation requests: infantry walk 6 frames, work/attack 4; predators walk 6 and attack 4. Run/walk loops should move limbs without translating the pivot. Death can initially use a tinted, flattened body plus a shared effect; bespoke death sequences are optional polish.

## Batch 2: vehicles

256 × 256 cells; pivot `(128, 128)`, vehicle front up. Shared rugged expedition design. Rough body sizes below exclude tiny antennas; scale within the current vehicle footprint rather than scaling to the full canvas.

| ID | Detailed description and technical states |
| --- | --- |
| `scout` | One-seat four-wheel quad bike, approximately 44 × 66 px. Exposed four tires, slim central chassis, open rider saddle, small rear sensor module, and two compact forward headlamps. Keep the seat readable as empty. Supply a removable seated-pilot overlay in the layered source if possible. Motion can use wheel vibration and a subtle body bounce; no multi-facing sheet required. |
| `jeep` | Four-seat expedition utility jeep, approximately 56 × 88 px. Broad hood, square reinforced bumper, open roll cage, four distinguishable seating positions, and a rear cargo rack. Two forward headlights plus a separate small amber roof/rear emergency lamp. Keep pilot/passenger silhouettes removable so occupancy can be represented without replacing the whole jeep. No permanently painted crew. |
| `drill` | Compact heavy tracked drilling vehicle, approximately 72 × 88 px. Parallel chunky tracks flank an industrial chassis; one forward operator station and a large tapered rotary drill project toward the top of the frame. Amber hazard panels and hydraulic lines distinguish it from a combat tank. Keep the drill bit on a separate layer if possible; a short loop can be made later. |
| `scout_wreck` | The same scout at exactly the same scale and pivot, with a bent wheel, fractured front chassis, darkened engine, and empty seat. No large fire or smoke baked in. Retain enough silhouette to recognize the vehicle. |
| `jeep_wreck` | Matching jeep with collapsed roll cage, dented hood, torn rear rack, and disabled wheels. Retain the emergency-lamp fixture as a separate element so the game can fade it. No bodies, passengers, or active headlight beams. |
| `drill_wreck` | Matching drill with a broken drill tip, detached tread segment, and ruptured top panel. Its silhouette remains obstructive-looking without implying new collision geometry. Keep debris within the original vehicle's immediate area. |

Headlights are separate from emergency lamps. The game must be able to turn forward lights off while leaving an unpiloted vehicle identifiable. Do not bake cones or surrounding illuminated terrain into these sprites.

## Building footprint guides

Large-building cells use pivot `(256, 256)`; utility/weapon cells use `(128, 128)`. For axial offset `(q, r)`, the pixel center relative to the pivot is:

`x = 64 × sqrt(3) × (q + r / 2)`; `y = 96 × r`.

The visible main body follows the convex hull of the listed centers. This is intentionally smaller than the union of all occupied hex tiles. Keep the simulation anchor fixed: for a generator it is a triangle vertex, not its visual center. Do not move that vertex to the middle of the canvas.

| Shape | Offsets / body outline |
| --- | --- |
| Command Center | Center plus six hex neighbors. Outer-center hull approximately 221.7 × 192 px, centered on the pivot. |
| Generator, Barracks | `(0,0), (1,0), (0,1)`: triangle vertices relative to pivot `(0,0), (110.851,0), (55.426,96)`. |
| Garage | Above triangle plus `(1,1)`: quadrilateral includes `(166.277,96)`. The anchor is one corner. |
| Ordinary single-cell building | Pointy-top hex, radius 51.2 px, centered on pivot. |
| Ramp | Two tile centers: anchor and one neighbor. Default second center is `(-110.851,0)`. Narrow deck/ribbon joins the centers; total footprint is at most two tiles. |

Generate only default orientation initially. Rotate these true-overhead images in-engine in 60-degree increments. Turret heads rotate freely independently of their bases. Guide geometry should be composited or supplied as a reference rather than trusted to prose alone.

Runtime keys with state/component filenames: `wall` uses `wall_hub` plus arms; `gate` uses its frame and leaf; `beacon` uses ruined/working images; `hive` uses intact/breached images. These remain four gameplay structure types, not new entities.

## Batch 3: large buildings

512 × 512 cells, pivot `(256,256)`. Large padding is necessary because asymmetric footprints rotate about their anchor.

| ID | Detailed description |
| --- | --- |
| `core` | Command Center: a large hexagonal armored landing module matching the six-vertex hull above. Central circular command roof, six broad radial equipment bays, several small ventilation panels, and a prominent rectangular personnel hatch. Pale steel roof with teal identification strips. Include a distinct amber emergency-lamp fixture on the central roof, separate from powered working lamps. It should feel like a landed command shelter, not a castle or skyscraper. |
| `generator` | Triangular industrial generator following the exact three-point footprint. Three rugged corner housings surround a central turbine/flywheel assembly, exposed cooling fins, and an inset fuel manifold. Amber service panels, dark heat vents, tiny teal status lights. All main machinery stays inside the triangle; do not substitute a rectangular building on a triangular foundation. Optional central fan layer can rotate later. |
| `barracks` | Triangular personnel shelter with three connected armored roof wedges, one compact central airlock/service hub, and military blue identification panels. Small roof bunks/air-conditioning housings suggest occupied living space without interior cutaways. Visually quieter than the generator; no giant exhaust or vehicle-sized bay door. Match the same triangular footprint, but make the roof silhouette unmistakably architectural. |
| `garage` | Asymmetric four-corner vehicle workshop following the quadrilateral guide. Broad segmented roof, an inset service-bay opening at the front-facing edge, two side tool lockers, and a small roof crane rail. Steel, teal strips, and amber bay markings without text. Make its large vehicle-access opening the primary cue. The canopy follows the footprint instead of drawing a conventional rectangular warehouse. |

## Batch 4: utility buildings

256 × 256 cells, pivot `(128,128)`; single-cell hexagonal bodies. Unpowered/disabled states should be obtainable by switching off emission. Damage and construction initially use shared overlays rather than separate AI requests.

| ID | Detailed description |
| --- | --- |
| `depot` | Low hexagonal material receiving platform: three compact angular cargo stacks, a small loading cradle, and a recessed central sorting mechanism. Teal mineral-colored contents remain visible from above. Give it open storage geometry rather than an enclosed habitation roof. Leave the perimeter visually accessible for deliveries. |
| `gas_tank` | Three rounded pressure vessels on a hexagonal steel skid, joined by thick pipes and one prominent valve assembly. Muted olive vessels, charcoal supports, amber pipe guards. The circular tank ends distinguish methane storage from angular material crates. No floating gas cloud or hazardous-looking unexplained fire. |
| `repeater` | Small hexagonal relay pedestal with a central antenna mast represented from above by a circular cap and six short radial conductor arms. Teal insulators and a few broad metal braces. The silhouette should imply a network junction, without drawing actual network lines. Avoid a tall sideways radio tower that contradicts the overhead camera. |
| `floodlight` | Spotlight assembly: compact hexagonal service base, small central support, and a ring of four broad rectangular lamp housings aimed outward. Pale reflective lamp faces distinguish it from the scanner. Supply lamp-face emission separately; the illumination radius and light falloff belong to the game. |
| `scanner` | Compact sensor station on a hexagonal base: one large offset circular radar/radome element, an adjacent processing box, and two small sensor prongs. Desaturated blue housing, narrow amber status indicator. No painted radar sweep or visible enemy markers. Keep a rotor/dish layer separate if an animated scan is desired later. |
| `extractor` | Single-cell automated collection rig surrounding a visible central resource opening. Three radial stabilizer feet, a compact mechanical cutter/intake ring, and a small transfer pipe. Amber tools and teal status hardware. Leave a transparent center so underlying crystals or vents can show through. Do not generate the proposed seven-cell installation until that gameplay change is implemented. |

## Batch 5: turret components

256 × 256 cells, common pivot `(128,128)`. Row 1 contains bases in minigun/laser/flame order; row 2 contains their corresponding heads. Base body fits the 51.2 px hex radius. Heads point up and rotate around the same pivot; no separate shadow beneath each component.

| ID | Detailed description |
| --- | --- |
| `turret_base` / `turret_head` | Minigun base: squat armored hexagonal socket, broad ammunition feed housing, and a circular central turntable. Head: compact cluster of parallel rotary barrels, a thick rear ammunition box, and sturdy side braces. Gun assembly approximately 38 × 64 px, muzzle near `(128,80)`. No muzzle flash baked in. A simple barrel/recoil transform is sufficient initially. |
| `laser_turret_base` / `laser_turret_head` | Laser base: reinforced hexagonal socket with large capacitor panels and cooling ribs. Head: a single long emitter barrel, two obvious side capacitor blocks, and a small pale teal lens. Approximately 42 × 72 px, muzzle near `(128,74)`. A subtle separate lens glow distinguishes it from a conventional cannon; no beam baked into the sprite. |
| `flame_turret_base` / `flame_turret_head` | Flame base: squat heavy socket with rounded fuel bottles and guarded hoses. Head: short broad heat-shielded nozzle with a thick rear manifold and rust-orange panels. Approximately 46 × 58 px, muzzle near `(128,86)`. Keep nozzle clearly shorter than the laser and wider than the minigun. Fuel tanks remain visible outside the rotating head. |

Record the actual muzzle attachment pixel after cropping; these suggested coordinates are layout targets. Reload state can initially use an indicator and simple moving parts. Do not generate a complete directional firing animation set.

## Batch 6: objectives and ramps

512 × 512 cells, pivot `(256,256)`. Beacon and hive currently each occupy one simulation cell: their main ground-contact body must respect the single-cell hex, even though their narrative importance is large.

| ID | Detailed description |
| --- | --- |
| `beacon_ruined` | Broken extraction transmitter on a hexagonal landing pedestal. Fractured radial aerials, a dark central lens, exposed cabling, and a few small damaged panel sections. Keep the silhouette and base identical to the working version; the engineer repairs this object, rather than replacing it with a different building. No huge debris field. |
| `beacon_working` | The repaired transmitter with straightened radial aerials and a prominent pale amber central lens. Cool steel surfaces and amber emergency fittings tie it to expedition hardware. A separate concentric-ring/lens layer can pulse during extraction. No beam extending outside the image or terrain illumination baked in. |
| `hive_intact` | Dense organic nest with a roughly hexagonal ground-contact mass, overlapping plum carapace plates, burgundy ribbed channels, and a central protected core cavity. Bone-colored shell edges provide readability. Scale the main nest to the current one-cell footprint; suggest depth through internal shading, not an oversized many-tile ground mass. |
| `hive_breached` | Same nest, same footprint and registration, with the central shell split open and the core cavity visibly exposed. Use broken shell plates and dark internal membranes. Do not include the collectible Hive Core in this image; it is a separate item. |
| `ramp` | Fabricated steel access ramp between two adjacent hex centers. Wide longitudinal deck, two reinforced edge rails, and subtle transverse grip strips. The uphill end is the anchor side; the second occupied cell extends left in default orientation. Surface shading and rail segmentation suggest slope without drawing an isometric side face. No third-tile landing pad. |
| `natural_ramp` | Basalt counterpart with the same two-cell orientation and registration: a worn sloped strip, shallow transverse rock ribs, and rough stone shoulders. Its texture matches the terrain/cliff sheet. Indicate uphill direction with rock bands and restrained shading; no arrows, steps, or impassable-looking vertical ledge across the walking path. |

## Batch 7: terrain, resources, and connections

256 × 256 cells, pivot `(128,128)`. List below is the exact 4 × 4 order. Terrain tile silhouettes use radius 64 px; platforms and building hubs use radius 51.2 px. Keep terrain edge colors compatible so neighboring tiles do not form obvious seams.

| Cell / ID | Detailed description and technical notes |
| --- | --- |
| 1 `ground_a` | Opaque pointy-top basalt hex, dusty cool gray-brown, two or three broad cracks, sparse restrained speckles. No centered landmark. Edges remain quiet and approximately uniform in value. |
| 2 `ground_b` | Matching alternate ground tile with different low-contrast fractures and a small violet-gray stain. Same edge values and scale. Runtime rotation provides additional variation without new images. |
| 3 `cliff_top` | Full-cell basalt cap with coarse fractured plates, broad edge chips, and a slightly lighter perimeter bevel. No floor surrounding it and no fixed isometric vertical wall. Depth edges/height indicators are composited by the view so adjacency remains correct. |
| 4 `platform` | Raised manufactured hex tile: inset steel deck, six reinforced perimeter segments, subtle grip pattern, and amber edge catches. Single tile, no rectangular slab, railings, or fixed cast shadow. Adjacent platforms should look like a continuous surface. |
| 5 `materials_full` | Angular pale teal crystal cluster, three to five large facets, ground-contact diameter approximately 70 px. Transparent exterior. Strong irregular crystalline silhouette, with broad highlights rather than glitter. |
| 6 `materials_medium` | Same cluster's depleted state, reduced to roughly half its major facets. Preserve the main anchor rocks and registration; do not translate or replace the cluster with a different formation. |
| 7 `materials_low` | Mostly exposed dark substrate, one or two short teal crystal stubs. Same deposit identity and pivot; depletion must remain apparent at small scale. |
| 8 `methane_full` | Low fractured vent deposit with several round olive mineral collars and dark pressure apertures. Diameter approximately 70 px. Small pale deposits around the vents imply condensed methane without a permanent fog cloud. |
| 9 `methane_medium` | Same vent formation with reduced olive crust, smaller pale deposits, and fewer active-looking apertures. Keep dark vents and the same registration. |
| 10 `methane_low` | Mostly exhausted dark fissures with a little residual olive crust. Clearly a vent resource rather than a green crystal cluster. Any gas vapor is a separate optional effect. |
| 11 `wall_hub` | Single-cell armored fortification junction: compact steel hexagonal body, broad plate seams, amber corner catches. Support connections in all six neighbor directions; do not paint permanent arms onto the hub. |
| 12 `wall_arm` | One straight modular armored connector pointing right from the central pivot toward a neighbor halfway point, length approximately 55.426 px. Width around 20 px, armored steel top and a matching end joint. Runtime rotation repeats this arm in six directions, replacing 64 separately generated adjacency combinations. |
| 13 `gate_frame` | Hexagonal gate foundation with two opposing armored posts and an empty central passage. Default passage axis runs left–right; can be rotated by the view. Include small separate motor/power indicator fixtures. Wall arms can connect independently. |
| 14 `gate_closed` | Heavy sliding gate leaf across that passage, centered on the pivot, with a bold central seam and amber mechanical locking brackets. Transparent everywhere except the moving leaf. Use exactly the same frame registration; do not paint a second gate frame. |
| 15 `gate_open` | The same leaf mechanically retracted toward its posts, leaving a clear through-passage. Same canvas and pivot. Lock/power states should use small overlay indicators, not regenerate the whole gate. A later open/close loop can interpolate between these states. |
| 16 `rubble` | Small restrained pile of angular steel and basalt fragments, transparent exterior, roughly one-cell diameter. Neutral dark grays with occasional amber scraps. Shared construction/destruction decoration; do not imply resource yield or block new terrain. |

Resource depletion states are visual support, not a request to change yields or depletion rules. No new terrain type or obstacle behavior is implied by the textures.

## Batch 8: items and effects

128 × 128 cells, pivot `(64,64)`. Exact order below. Use transparent backgrounds and tight, readable internal silhouettes. Effects may have soft alpha edges; objects retain crisp edges. All beams, range circles, fog, selection outlines, command lines, scanner blips, and health/battery bars should be drawn in code rather than requested as art.

| Cells / IDs | Detailed description |
| --- | --- |
| 1 `hive_core` | Collectible organic core: faceted bone/plum casing around a pale amber-pink center, approximately 26 × 32 px. Distinctive three-lobed silhouette, no pedestal, hand, or baked halo. It must work on the ground and as a small attachment to a carrier. |
| 2 `material_crate` | Compact industrial crate approximately 28 × 28 px, with a partially open top revealing a few pale teal mineral facets. Broad charcoal corners and teal latches; no printed symbols or numbers. |
| 3 `methane_canister` | Short pressure cylinder viewed from above, approximately 22 × 30 px, olive casing and a large protective valve collar. Distinguishable from the square material crate even in grayscale. |
| 4–5 `muzzle_00..01` | Two compact ballistic muzzle flashes, north-facing, amber-white core and short orange tips. Bright footprint approximately 24 × 32 px. Pivot is the muzzle origin, not the visible flash center: leave the flash extending upward from `(64,64)`. |
| 6 `impact_kinetic` | Small asymmetric burst of amber sparks and gray chips around the central impact point; no bullet, weapon, or target baked in. Approximately 30 px diameter. Runtime scale/fade supplies the initial animation. |
| 7 `impact_laser` | Sharp pale teal-white energy impact with a few short radial streaks, approximately 30 px diameter. Keep the center bright but the edge transparent; no long beam attached. |
| 8–10 `flame_00..02` | Three compatible north-facing flame tongues from a fixed nozzle pivot `(64,64)`, extending upward about 54 px. White-yellow base transitions to orange-red tips, with differing licks across frames. No weapon, dark opaque outline, or rectangular smoke backing. Composite/scale in runtime for infantry and turret fire. |
| 11–12 `repair_sparks_00..01` | Two small cool-white welding spark clusters with a little warm amber scatter, centered on the work contact. Approximately 24 px diameter; never include a welder, hand, building, or blue-lit background patch. |
| 13–14 `smoke_00..01` | Two soft gray-brown overhead puffs, approximately 54 px diameter, with irregular transparent borders and faint internal breakup. Neutral lighting, no fixed wind direction. Runtime rotation, expansion, and fading provide variation. |
| 15–16 `alien_hit_00..01` | Two small muted burgundy/plum chitin bursts with pale shell flecks, approximately 34 px diameter. Readable damage feedback without an opaque blood decal, detached body, or surrounding terrain. |

Cargo visuals are optional presentation assets; the first pass can leave them unused. Existing Materials/Methane/Power SVG HUD icons should stay consistent and do not need AI regeneration. Build/production buttons can initially use cropped asset thumbnails instead of a separate portrait pack.

## Reusable generation request

> Create Batch [NUMBER / NAME] for Against the Darkness using the attached shared art direction and technical contract. This is a true orthographic overhead RTS sprite contact sheet, not an isometric scene. Use [GRID] cells in the stated row-major order, with identical world scale, transparent backgrounds, and the specified pivots. Follow each asset description and footprint guide. Produce isolated game assets only: no scene composition, captions, grid lines, UI, logos, or cast ground shadows. Preserve the listed negative space and do not resize every object to fill its cell. Keep the same painted industrial/organic style and palette across all cells. When references are supplied, match their material treatment, edge sharpness, and detail density.

Attach an approved batch as a style reference for subsequent requests. For precise multi-tile shapes, attach a clean guide silhouette for each relevant cell. If the image service cannot honor the requested sheet dimensions, preserve the grid proportions and allow mechanical repacking afterward.

## Acceptance and handoff

1. Check style, overhead projection, and silhouette at the actual small in-game display size before generating more sheets.
2. Verify transparent edges, no background/checkerboard, unchanged scale, and correct pivots. Crop/pack with image tools, not additional generation calls.
3. Overlay each building's art on its footprint guide. In particular, confirm asymmetric generator/garage anchors and the two-cell ramp length. Review all six rotated placements.
4. Check unit silhouettes in grayscale; engineer/marine/flamer and runner/stalker/brute must remain distinguishable. Check dark shells against dark ground.
5. Confirm lights, turret heads, gate parts, and optional occupants can be controlled independently. Emission must not reveal unseen enemies or change gameplay illumination.
6. Deliver sheets, cropped PNGs, source layers when available, and the attachment/pivot manifest. Keep the original approved sheets for cheap future edits.

No new directional animation packs, full construction sequences, destroyed variants for every building, portraits, or decorative biome packs are required for the first playable art pass. Those should follow an in-game review of this smaller set.

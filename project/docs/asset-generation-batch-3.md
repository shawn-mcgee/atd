# Batch 3 generation request: large buildings

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 3 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **2 columns × 2 rows**.
- Target cell size: **512 × 512 px**; target sheet size: **1024 × 1024 px**.
- Row 1, left to right: **Command Center, Generator**.
- Row 2, left to right: **Barracks, Garage**.
- Every cell uses pivot **(256,256)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **2:2** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_03_large_buildings.png**.

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

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_03_large_buildings.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

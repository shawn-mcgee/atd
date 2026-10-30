# Batch 4 generation request: utility buildings

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 4 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **3 columns × 2 rows**.
- Target cell size: **256 × 256 px**; target sheet size: **768 × 512 px**.
- Row 1, left to right: **Material Depot, Methane Tank, Repeater**.
- Row 2, left to right: **Spotlight, Scanner, Extractor**.
- Every cell uses pivot **(128,128)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **3:2** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_04_utility_buildings.png**.

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

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_04_utility_buildings.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

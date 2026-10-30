# Batch 5 generation request: turret components

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 5 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **3 columns × 2 rows**.
- Target cell size: **256 × 256 px**; target sheet size: **768 × 512 px**.
- Row 1, left to right: **Minigun base, Laser base, Flame base**.
- Row 2, left to right: **Minigun head, Laser head, Flame head**.
- Every cell uses pivot **(128,128)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **3:2** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_05_turret_components.png**.

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

## Batch 5: turret components

256 × 256 cells, common pivot `(128,128)`. Row 1 contains bases in minigun/laser/flame order; row 2 contains their corresponding heads. Base body fits the 51.2 px hex radius. Heads point up and rotate around the same pivot; no separate shadow beneath each component.

| ID | Detailed description |
| --- | --- |
| `turret_base` / `turret_head` | Minigun base: squat armored hexagonal socket, broad ammunition feed housing, and a circular central turntable. Head: compact cluster of parallel rotary barrels, a thick rear ammunition box, and sturdy side braces. Gun assembly approximately 38 × 64 px, muzzle near `(128,80)`. No muzzle flash baked in. A simple barrel/recoil transform is sufficient initially. |
| `laser_turret_base` / `laser_turret_head` | Laser base: reinforced hexagonal socket with large capacitor panels and cooling ribs. Head: a single long emitter barrel, two obvious side capacitor blocks, and a small pale teal lens. Approximately 42 × 72 px, muzzle near `(128,74)`. A subtle separate lens glow distinguishes it from a conventional cannon; no beam baked into the sprite. |
| `flame_turret_base` / `flame_turret_head` | Flame base: squat heavy socket with rounded fuel bottles and guarded hoses. Head: short broad heat-shielded nozzle with a thick rear manifold and rust-orange panels. Approximately 46 × 58 px, muzzle near `(128,86)`. Keep nozzle clearly shorter than the laser and wider than the minigun. Fuel tanks remain visible outside the rotating head. |

Record the actual muzzle attachment pixel after cropping; these suggested coordinates are layout targets. Reload state can initially use an indicator and simple moving parts. Do not generate a complete directional firing animation set.

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_05_turret_components.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

# Batch 7 generation request: terrain and connections

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 7 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **4 columns × 4 rows**.
- Target cell size: **256 × 256 px**; target sheet size: **1024 × 1024 px**.
- Row 1, left to right: **Ground A, Ground B, Cliff top, Platform**.
- Row 2, left to right: **Materials full, Materials medium, Materials low, Methane full**.
- Row 3, left to right: **Methane medium, Methane low, Wall hub, Wall arm**.
- Row 4, left to right: **Gate frame, Gate closed leaf, Gate open leaf, Rubble**.
- Every cell uses pivot **(128,128)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **4:4** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_07_terrain_and_connections.png**.

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

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_07_terrain_and_connections.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

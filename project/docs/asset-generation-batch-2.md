# Batch 2 generation request: vehicles

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 2 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **3 columns × 2 rows**.
- Target cell size: **256 × 256 px**; target sheet size: **768 × 512 px**.
- Row 1, left to right: **Scout, Jeep, Drill**.
- Row 2, left to right: **Scout wreck, Jeep wreck, Drill wreck**.
- Every cell uses pivot **(128,128)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **3:2** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_02_vehicles.png**.

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

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_02_vehicles.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

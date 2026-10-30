# Batch 8 generation request: items and effects

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and Batch 8 asset descriptions below.

Use the approved Batch 1 character sheet as the attached style reference. Match its palette, painted material treatment, edge sharpness, and detail density while preserving the object scales specified here.

- Grid: **4 columns × 4 rows**.
- Target cell size: **128 × 128 px**; target sheet size: **512 × 512 px**.
- Row 1, left to right: **Hive Core, Material crate, Methane canister, Muzzle 00**.
- Row 2, left to right: **Muzzle 01, Kinetic impact, Laser impact, Flame 00**.
- Row 3, left to right: **Flame 01, Flame 02, Repair sparks 00, Repair sparks 01**.
- Row 4, left to right: **Smoke 00, Smoke 01, Alien hit 00, Alien hit 01**.
- Every cell uses pivot **(64,64)**. North/front is image up except the explicitly described default ramp, gate, and connector orientations. Keep asymmetric footprint anchors fixed; do not recenter visible bounds.
- Maintain **64 source pixels per world unit**. Larger canvases are padding, not larger objects. Do not scale each asset to fill its cell.
- Generate only the listed cells. Do not add directional variants or animation frames beyond any effect frames explicitly listed.
- True orthographic overhead projection; transparent backgrounds; no captions, grid lines, UI, logos, cast ground shadows, or scene backgrounds.
- If the service cannot produce these dimensions, preserve the **4:4** sheet proportions at a supported resolution. Keep relative sizes and cell placement; exact downsampling, cropping, and pivot alignment can happen afterward.
- Suggested output filename: **batch_08_items_and_effects.png**.

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

## Review and save

Check projection, transparency, small-scale readability, world scale, pivots, and the exact cell order. Preserve the original full-resolution sheet as `project/art_source/sprites/batch_08_items_and_effects.png`. Independent components and emission should use registered source layers when supported; the primary requested output remains the single contact sheet. Keep approved cells when correcting an individual asset.

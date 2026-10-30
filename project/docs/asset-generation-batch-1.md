# Batch 1 generation request: characters

Create one transparent sprite contact sheet for Against the Darkness using the art direction, technical contract, and six character descriptions below.

- Grid: **3 columns × 2 rows**.
- Target cell size: **128 × 128 px**; target sheet size: **384 × 256 px**.
- Row 1, left to right: **Engineer, Marine, Flamer**.
- Row 2, left to right: **Runner, Stalker, Brute**.
- Every cell uses pivot **(64,64)** and faces **north/image up**. Preserve the different body sizes specified below; do not scale every character to fill its cell.
- Generate **one idle pose per character**, without animation frames or alternate headings.
- Use true orthographic overhead projection, transparent backgrounds, and a consistent painted RTS style. No isometric perspective, captions, grid lines, UI, cast ground shadows, logos, or scene backgrounds.
- If the service cannot produce the target dimensions, use the same 3:2 sheet proportions at a supported resolution. Preserve relative sizes and cell placement; cropping, downsampling, and pivot alignment can happen afterward.

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

## Review before generating further batches

Check all six silhouettes at small display sizes, consistent overhead projection, palette, transparent background, and north-facing orientation. Keep the original sheet. Once approved, use it as the style reference for later batches. Exact cropping and packing can be corrected mechanically without another image request.

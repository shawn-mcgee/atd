# Sprite integration: quick maintenance guide

## Where to work

- Approved original sheets: `art_source/sprites/batch_*.png` (kept unchanged).
- Runtime copies and metadata: `assets/sprites/`; `atlas.json` maps 63 regions from eight sheets. The three unusable generated gate cells are excluded.
- Rebuild: from repository root, `python tools/prepare-sprites.py` (Pillow required). This copies the PNG bytes and analyzes alpha bounds; it does not repaint, rotate, resize, or remove backgrounds. Reimport in Godot afterward. Mipmaps are enabled in the tracked PNG import settings.
- Rendering, pivots, orientation, alpha picking, turret heads, gate animation, and combat effects: `view/sprite_library.gd`.
- Drawing order, terrain, resource depletion, previews, and selection overlays: `view/primitives.gd`. HUD thumbnails: `view/game_hud.gd`.
- Validation: `python tools/test-game.py --name sprites --name top-down --name engine --name gameplay-baseline --godot <executable>`. Render all families with `Godot --path project --script res://tools/preview-prototype.gd -- --gallery --seed=42`. Preview PNGs/logs stay in `art_source/.build/`.

All paths above are relative to `project/`, except the root preparation/test scripts.

## Corrections and layout

The source images differ from the ideal generation brief. Metadata uses their actual dimensions, alpha bounds, relative sizes, and body pivots. Change a crop/pivot/size in the preparation script and regenerate rather than hand-maintaining generated metadata. `world_size` is in simulation world units; `pivot` is a normalized point inside its cropped atlas region. Character weapon extensions do not move the torso pivot.

Aliens **and vehicles** face south in the supplied sheets. Their 180-degree correction is applied only while drawing/picking. Unit headings and the deterministic core are unchanged. Predators infer their visual heading from movement; their remembered direction lives in the view.

Batch 7 was replaced with corrected pointy-top art and no longer receives a 30-degree correction. Only the original Batch 5 turret bases retain that correction. Elevated platforms use a fixed 1.82-world-unit width, original image aspect ratio, and a surface-centered pivot. Their untrimmed sides overlap adjacent tiles; back-to-front screen ordering provides depth. Gameplay footprints remain unchanged.

Buildings draw transparent art without filled polygon foundations. Their existing footprint defines sprite bounds and the optional selection outline. Because the generated roofs do not precisely match the requested triangles/quadrilaterals, the full roof illustration is fitted to those bounds rather than cut into pieces by the footprint mask. Actual opaque overhangs are selectable; footprint interiors retain a forgiving fallback. This affects presentation/picking only, never placement or collision.

Turret bases and heads are separate. Heads and firing infantry aim using shot events tagged with stable shooter IDs; no new target acquisition enters the simulation. Infantry hold the firing direction between shots, including automatic fire while moving. `muzzle_uv` in the preparation script defines each rifle/nozzle/barrel tip relative to its cropped sprite; turret head pivots and sizes are stored in the same manifest. Tracers, flashes, and flames use those attachments with the same rotation and interpolated origin as the drawn weapon. Enemy melee attacks use hit effects rather than gun flashes. Vehicle emergency indicators remain visible, while the forward operating indicator depends on driver/battery state. The supplied art has baked lens colors rather than separate emission layers: a painted bright lens does not emit gameplay light.

Gates use procedural steel posts and sliding leaves, with amber/teal/red state indicators. No generated gate component is displayed. Opening animation lives in a view dictionary and reads `gate_open`; it never changes pathfinding, power, locking, or auto-close rules.

Resources choose full/medium/low art using the remaining fraction relative to a view-owned starting quantity. Wrecks, the Hive Core, repair sparks, and weapon effects use their corresponding regions. Existing SVG resource icons remain. Optional cargo/smoke/alien-hit regions are available in the catalog without introducing new gameplay or cosmetic clutter.

The simulation never loads textures. Sprite cache state, alpha images, visual headings, gate interpolation, and effect lifetimes stay in the view. Tests verify that these operations leave the authoritative state hash unchanged.

## Wispy darkness overlay

`view/darkness.gd` places an input-transparent world overlay below the HUD. Its 768-square SubViewport renders the core’s aggregated hex flood-fill field as a single MultiMesh draw. Radial/conical falloff is calculated by the core and constrained by cliffs, walls and elevation. The mask only rerenders when source or navigation revisions change; the fragment shader does not loop over lights. It supports the full current map within world bounds -168..168.

`view/shaders/darkness.gdshader` adds world-anchored dark smoke using two soft, isotropic noise layers and restrained domain warping. Low-contrast charcoal billows replace bright ridged ribbons to avoid a satin appearance. Camera pan, rotation, resize, and zoom share the view projection; fog does not slide with the screen. Drifting filaments vary an outward-only dilation of the light field. The original illuminated area stays clear, including dim one-tile sources; smoke wisps occupy an extra visual halo rather than shrinking the light. `edge_padding` controls the world-unit halo (default 0.28), and `edge_wisp_strength` controls its variation. The clearing is also bounded by a cached terrain-coverage mask, preventing gaps where undiscovered tiles are not rendered. Coverage reuses terrain instances and updates only with terrain changes. This uses eight neighboring GPU light-mask samples without modifying discovery, targeting, or terrain lighting. Tune `wisp_scale`, `drift_speed`, `opacity`, `darkness_color`, and `wisp_color` in the shader. Visual time pauses with gameplay. The light mask is presentation data, never a visibility or targeting authority. Existing explored terrain, enemy visibility, and illumination rules are unchanged. Validate with `--name darkness --name top-down` and a rendered preview.

Synthetic beep generation and sound-cue events were removed. Mining reach is shared by manual orders and both expedition paths in `engine/resource_fields.gd`: same/neighbor hex only, within about 1.93 world units horizontally, and no more than 0.6 elevation difference. The harvest API enforces this for hand gathering; a powered seven-cell extractor can instead be operated from any adjacent perimeter tile and balances output across all covered deposits. Validate these fixes with `--name combat-and-mining` and the logistics suites.

## Selection silhouettes

`view/selection_highlight.gd` redraws selected visible actors into a transparent, screen-sized GPU mask using the **same** atlas crops, pivots, camera transforms, interpolation, aiming, turret components, wall connectors, and procedural gate panels as the world. `selection_mask.gdshader` reduces these parts to their alpha silhouette. `selection_outline.gdshader` draws a mint exterior stroke around the combined mask, at a fixed screen-pixel width. This replaces unit circles and structure footprint outlines; placement previews still show footprint geometry.

The overlay ignores mouse input and sits below darkness/HUD. It resizes with the window and disables the mask viewport when selection is empty. No labels, bars, effects, or invisible/boarded actors enter the mask. For visual review use `--combat --selection` with the preview script. Tune stroke width/color in `view/shaders/selection_outline.gdshader`.

## Retro RTS console HUD

`view/rts_theme.gd` owns charcoal steel, ivory text, amber accents, square borders, button states, tooltips, scrollbars, and health bars. `rts_panel.gd` draws bevels and screw heads. `rts_icons.gd` supplies cached, code-authored SVG command pictograms; no generated UI artwork or external font dependency is required.

`game_hud.gd` arranges the resource readouts, framed sprite portrait, scrollable selection details, health/grid status, order cards, construction cards, and hotkey badges. Command/build grids adapt to available width. Contextual visibility, production, targeting, and shortcuts are unchanged. The minimap uses a matching inset tactical display; click-to-pan uses the content area's corrected origin and scale.

Validate with `--name top-down --name sprites`. Review `--engineer` (construction), `--outpost` (orders), and `--engineer --small` (1100×720) using the preview script. Existing sprite thumbnails serve as portraits. Optional dedicated character portraits or a painted console skin can be added later, but are not needed for this UI.

Latest art refresh: Batches 1/7/9 are imported unchanged. Every Batch 1 character faces south in source and receives a 180-degree correction; updated torso pivots and muzzle points match the new weapons. Batch 9 replaces command and resource icons. Terrain, resource, and building art preserves its source aspect ratio instead of being stretched into hex bounds; overhangs are permitted. Resource selections use the same alpha silhouette pass as actors, including depletion variants, and can be selected through visible sprite overhangs.

### Terrain extraction correction

Batch 7 must not be split at fixed grid boundaries: silhouettes cross row boundaries. `tools/prepare-sprites.py` labels connected alpha islands over the entire source sheet, matches the 16 dominant islands to expected slots, assigns feather pixels to the nearest island, and repacks complete cutouts into 512-pixel slots with at least 32 pixels of transparent gutter. Assertions verify that no opaque island pixels are lost or borrowed. No sprite is resized; original artwork remains untouched. Runtime/source SHA-256 values are recorded separately. The preparation tool additionally requires NumPy and SciPy. Other sheets still use their existing crop mapping.

Ground is the intentional aspect-ratio exception: fit the complete ground sprite, including its authored border, to tile dimensions with 2.5% overlap. A solid hex underlay prevents transparent gaps; no center-only UV crop or polygon clipping removes the artwork edges. Cliffs, platforms, resource deposits, and structures keep their natural sprite proportions and overhangs.

Cliff caps are the second deliberate fitting exception: 2.0×2.5 world units, pivot (0.5,0.62). The cliff art is lifted relative to its ground cell: the top sits above the hex and the bottom of the side faces remains near the ground footprint. Cliff sprites draw back-to-front with no flat footprint outline.

Ground/cliff fitting now uses alpha-boundary radial morphing, not rectangular scaling. Three generated *_fit textures preserve the entire source silhouette mapped onto an exact pointy-top hex. Opaque edge-extended pixels prevent transparent seams. Ground uses a 2-unit-high mesh; cliffs use a 2.5-unit-high mesh with the bottom anchored at the ground hex bottom (top raised 0.5). Originals stay intact. Rebuild with tools/prepare-sprites.py.

Map expansion: radius 84 (50% wider), 72 ridges of 14–32 steps, occasional three-cell thickness. Objectives and distant fields use the expanded outer area; HQ and nearby starter resources retain their protected layout. Darkness mask bounds follow map radius, at 768² resolution. Legacy gameplay checkpoints use a frozen original generator fixture.

Material deposit sprites use a 0.22-world-unit upward pivot offset across all depletion states. Their logical tile/mining position stays unchanged; alpha picking and silhouette highlighting automatically share this offset.

Terrain rendering uses four retained MultiMesh batches in `view/terrain_renderer.gd` (two ground textures, ramps, cliffs). Camera changes update their parent transform; illumination samples the existing GPU light field in `view/shaders/terrain.gdshader`. Only exploration or navigation edits update instance buffers. Cliff instances sort by world Z before camera rotation, keeping bottom-aligned overhangs. Resources remain between the ground and cliff passes. The minimap caches surveyed terrain into one texture and refreshes live markers at 10 Hz. See [performance.md](performance.md) for profiling.

Spotlight (`floodlight`) art uses pivot `(0.5, 0.62)` to sit slightly higher within its tile. Drawing, picking, and selection silhouettes share this pivot; its footprint and light source stay unchanged.

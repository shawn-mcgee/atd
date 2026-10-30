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

`view/darkness.gd` places an input-transparent world overlay below the HUD. Its 512-square SubViewport renders additive radial/conical stamps from **all** existing illumination sources, matching the core falloff and cone parameters. The mask only rerenders when the light field changes; the fragment shader does not loop over lights. It supports the full current map within world bounds -112..112.

`view/shaders/darkness.gdshader` adds world-anchored dark smoke using two soft, isotropic noise layers and restrained domain warping. Low-contrast charcoal billows replace bright ridged ribbons to avoid a satin appearance. Camera pan, rotation, resize, and zoom share the view projection; fog does not slide with the screen. Tune `wisp_scale`, `drift_speed`, `opacity`, `darkness_color`, and `wisp_color` in the shader. Visual time pauses with gameplay. The light mask is presentation data, never a visibility or targeting authority. Existing explored terrain, enemy visibility, and illumination rules are unchanged. Validate with `--name darkness --name top-down` and a rendered preview.

Synthetic beep generation and sound-cue events were removed. Mining reach is shared by manual orders and both expedition paths in `engine/resource_fields.gd`: same/neighbor hex only, within about 1.93 world units horizontally, and no more than 0.6 elevation difference. The harvest API enforces this too. Validate these fixes with `--name combat-and-mining` and the logistics suites.

## Selection silhouettes

`view/selection_highlight.gd` redraws selected visible actors into a transparent, screen-sized GPU mask using the **same** atlas crops, pivots, camera transforms, interpolation, aiming, turret components, wall connectors, and procedural gate panels as the world. `selection_mask.gdshader` reduces these parts to their alpha silhouette. `selection_outline.gdshader` draws a mint exterior stroke around the combined mask, at a fixed screen-pixel width. This replaces unit circles and structure footprint outlines; placement previews still show footprint geometry.

The overlay ignores mouse input and sits below darkness/HUD. It resizes with the window and disables the mask viewport when selection is empty. No labels, bars, effects, or invisible/boarded actors enter the mask. For visual review use `--combat --selection` with the preview script. Tune stroke width/color in `view/shaders/selection_outline.gdshader`.

## Retro RTS console HUD

`view/rts_theme.gd` owns charcoal steel, ivory text, amber accents, square borders, button states, tooltips, scrollbars, and health bars. `rts_panel.gd` draws bevels and screw heads. `rts_icons.gd` supplies cached, code-authored SVG command pictograms; no generated UI artwork or external font dependency is required.

`game_hud.gd` arranges the resource readouts, framed sprite portrait, scrollable selection details, health/grid status, order cards, construction cards, and hotkey badges. Command/build grids adapt to available width. Contextual visibility, production, targeting, and shortcuts are unchanged. The minimap uses a matching inset tactical display; click-to-pan uses the content area's corrected origin and scale.

Validate with `--name top-down --name sprites`. Review `--engineer` (construction), `--outpost` (orders), and `--engineer --small` (1100×720) using the preview script. Existing sprite thumbnails serve as portraits. Optional dedicated character portraits or a painted console skin can be added later, but are not needed for this UI.

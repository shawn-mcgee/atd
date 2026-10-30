# Against the Darkness — HUD icon sheet

Create **one 5-column × 5-row sheet of 25 sci-fi RTS interface icons**. Attach an approved game sprite sheet and HUD screenshot as style references.

**Style:** classic military sci-fi RTS, worn gunmetal hardware, pale ivory pictograms, restrained amber highlights, occasional muted teal. Bold, instantly recognizable silhouettes with subtle painted bevels. Each icon should feel like a physical control engraved into an expedition console. Prioritize clarity over tiny mechanical detail; avoid glossy app icons, neon holograms, cartoon styling, and excessive grunge.

**Technical:** transparent RGBA PNG, 128 × 128 cells, 640 × 640 sheet. Keep each symbol centered within a 96 × 96 safe area. All icons must remain readable at **20–32 px**. Consistent scale, contrast, and stroke weight. No button backgrounds, frames, lettering, hotkeys, numbers, shadows outside the symbol, or baked glow. The game supplies the button chrome and state colors. A higher-resolution sheet with the same proportions is acceptable.

Generate in this exact order, left to right, then top to bottom:

| Row | Icons and visual concepts |
| --- | --- |
| 1 | **Board:** arrow entering a vehicle hatch. **Unload:** arrow leaving a hatch. **Explore:** rugged compass with a forward pointer. **Mine:** industrial pick striking a crystal. **Attack:** targeting reticle over a small impact point. |
| 2 | **Defend:** armored shield with a central brace. **Patrol:** two opposing arrows following a circuit. **Drill:** tapered mechanical drill bit. **Repair:** heavy spanner with a small welding spark. **Collect cargo:** supply crate with an inward/down arrow. |
| 3 | **Deposit:** supply crate with an outward/up arrow. **Return HQ:** compact command bunker with a homeward arrow. **Escort:** small protected figure beside a larger guard. **Recharge:** battery with a lightning bolt. **Reload:** ammunition magazine with a circular arrow. |
| 4 | **Auto reload:** ammunition magazine with two cycling arrows and a small gear. **Relay power:** central electrical junction linked to three nodes. **Gate:** paired sliding armored panels with a clear center seam. **Lock gate:** chunky mechanical padlock. **Stop:** solid octagonal stop symbol without lettering. |
| 5 | **Destroy:** broken armor plate crossed by a demolition mark. **Cancel production:** unfinished assembly with a bold cancellation cross. **Materials:** three angular teal mineral crystals. **Methane:** olive pressure canister with a protective valve. **Power:** amber electrical bolt between two terminals. |

Make related pairs clearly different: board/unload, collect/deposit, reload/auto reload, stop/cancel/destroy. Use the same icon treatment for all 25 cells. Do not draw scenery or include extra icons.

Save the original as `project/art_source/sprites/batch_09_ui_icons.png`. We will crop the cells and map them to the existing commands. Unit/building production thumbnails stay as they are; this sheet replaces the generic command and resource symbols.

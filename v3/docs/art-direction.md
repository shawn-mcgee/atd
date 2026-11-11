# Art direction and presentation assets

Walls use one flat-sided hexagonal prism per cell, with corners aligned to the navigation hexagon and a one-tile height. Contiguous segments meet across full edges. The drag preview reuses that shared mesh. Run the native fixture with `--script tools/preview-vehicles.gd -- --walls` to check pointer capture and save `build/visual-review/wall-line.png`.

The visual target is a small industrial expedition holding a warm island of light against a cold, organic frontier. Gameplay readability takes priority over decorative detail.

## Palette and shapes

Use graphite steel and dusty ivory for Commonwealth equipment, with faction color confined to armor markings. Work lamps, warnings, and tool sparks use restrained amber. Lightless use bone, shale, and muted flesh tones; Gloom provides the darker organic color field. Avoid large saturated faction-colored surfaces.

Human structures use broad, grounded silhouettes, beveled armor plates, exposed supports, and small status lights. Scavengers use low bodies, pointed heads, and asymmetric walking phases. The Anchor should read as a lander, the Extractor as a working drill, and the Floodlight as a tall mast at the normal camera distance.

The terrain shader uses world-space texture coordinates across hexes. The placement grid remains a gameplay rule; it should become prominent during construction rather than make the whole landscape look like a board. A filtered visibility texture softens the fog edge. The ground shader masks local lamp contribution with the actual illumination field.

Fog of war now adds a low black smoke sheet with slowly advected, domain-warped billows and curling tendrils at the visibility fringe. Deep unexplored space stays opaque black. Remembered terrain receives a translucent smoke veil, while the interior of current vision remains clear. The effect samples the same explored/visible mask as terrain; overlapping tile splats combine channels rather than letting a remembered neighbor overwrite current vision. It changes no simulation visibility, targeting, enemy concealment, or structure-memory rules. Its mesh has no collision and does not intercept input.

`presentation.fog` exposes the enable switch, remembered-ground opacity, edge opacity/reach, drift speed, noise scale and sheet height. Its clock follows the renderer and freezes while paused. The effect uses one shader-driven sheet, not particles or volumetric fog, for the browser Compatibility renderer. Run the review fixture with `-- --fog` for two fixed animation phases in `build/visual-review/black-fog-0.png` and `black-fog-12.png`.

## Motion and feedback

### Terrain and grounding pass

Cliffs now use three irregular, differently rotated fragments per tile with folded basalt strata rather than identical upright hex columns. Loose low-poly scree is scattered in deterministic cell-local patterns, leaving clear space between patches. Ground shading combines two texture scales and texture-derived surface normals, so work lights pick out gravel relief without changing the simulation ground plane.

Gas deposits use eroded vent mouths and a faint animated seep instead of flattened resource rocks; Ore retains solid angular mineral fragments. Vapor exists only on currently visible, non-obstructed gas patches with remaining supply. It stops with the presentation clock when paused. Completed terrain clearing still produces non-blocking rubble using the same simulation rules.

Soft contact shadows ground units, vehicles and facilities. Operating Commonwealth facilities cast a restrained amber service-light wash onto their loading edge; this extinguishes with their operating lamps and is hidden for remembered enemy facilities. These are shadow-free presentation meshes, not additional simulation illumination sources. Terrain detail and vapor remain GPU-instanced rather than adding a node or particle emitter per tile.

`presentation.terrain` controls scatter density, contact-shadow opacity, strata strength, gas-vapor opacity and ground-normal strength. `presentation.lighting.serviceLightWashOpacity` controls the warm floor spill. All are presentation-only settings. The regular `-- --fog` review captures also show the terrain and lighting changes at the starting base.

### Industrial facility pass

Commonwealth facilities now have individual silhouettes: an open assembly bay and gantry for the Factory, receiving ring for the Cradle, bunker and equipment racks for the Armory, furnace/stack for the Foundry, horizontal tanks and distillation column for the Refinery, a three-column Synthesizer, open Fabricator press, lattice Relay, and shielded Reactor column. Sentry barrels, Torch fuel tanks/nozzle, and Lance rails distinguish the defenses. Recessed vents, roof grilles, loading-edge hazard paint, and subtle world-space metal wear tie the facilities together.

Warm service lamps and a loading-edge light strip indicate operation. Switched-off or unpowered facilities extinguish these lights and stop their work indicators. Powered facilities with stalled or empty queues retain service lighting without a production signal. Amber production indicators, furnace/process windows, the gantry, press and partially assembled vehicle communicate work; brownout/blackout or fuel failure adds a warning blink. Pausing freezes machinery without making it appear switched off.

Owner-visible kit racks display up to five actual queued cases: unfinished cases build up, finished cases have role-colored bodies and illuminated latches while powered. Personnel queues display up to ten capsule berths, with illuminated windows on progressing arrivals. Queue removal removes the corresponding prop. These are presentation meshes, not additional units, inventory, or collision bodies. Enemy queues are hidden; remembered facilities do not reveal current queue state or continue work animation.

Cold ambient/key lighting and restrained warm ground tint preserve an island of industrial light around the expedition. The readability pass raises ambient energy to 0.58 and key energy to 0.65, lightens remembered terrain and resource silhouettes, and reduces structure-memory tint to 0.42. Remembered fog opacity is 0.28, with fringe opacity 0.48 and reach 1.1 tiles. Unexplored terrain remains opaque; hidden enemies remain hidden. `presentation.lighting` configures `ambientEnergy`, `keyLightEnergy`, `workLightEnergy`, and `groundBrightness`; these values do not affect simulation vision, illumination, or the multiplayer gameplay hash. The shader uses low-contrast wear rather than high-frequency grain to avoid shimmer at RTS distance.

Run the existing review fixture with `-- --buildings` to capture `industrial-expedition.png`, `industrial-roster.png`, `industrial-offline.png`, and `industrial-queues.png` under `build/visual-review/`. The roster and offline images use the same camera for a direct state comparison. This is a native rendering fixture; it does not validate browser performance.

Presentation interpolation smooths the authoritative unit positions without changing collision or targeting. Walking legs, aiming, recoil, Scavenger gait and breathing, drill motion, tool sparks, and short death effects add motion at the normal RTS viewing distance. No camera shake is added.

Command confirmation uses inward reticle marks and quiet audio. Selection and movement use separate cues. Rifle, laser, impact, mining, and completion sounds use original synthesized waveforms. A low ambient drone begins after deployment. SOUND ON/OFF controls all game audio. This is an initial sound pass; automated waveform checks establish headroom, not a finished listening mix.

Damage numbers are off by default, with impacts and health bars carrying the combat feedback. They remain available through `presentation.damageNumbers`. The presentation settings also expose audio levels, interpolation time, and particle limits. Presentation settings are excluded from the gameplay compatibility hash.

## Assets and provenance

- `assets/textures/regolith-albedo.png`: generated with the built-in image-generation tool for this project. Mipmaps are enabled in its import settings.
- `assets/textures/expedition-backdrop.png`: generated with the built-in image-generation tool for the title screen; concept art rather than an in-game screenshot.
- `assets/fonts/BarlowSemiCondensed-Medium.ttf` and `BarlowSemiCondensed-SemiBold.ttf`: Barlow Semi Condensed from the [Google Fonts source repository](https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed), under the bundled `OFL.txt`. The build includes this license in the distribution notices.
- `assets/audio/*.wav`: original synthesized effects and ambience created for this project.
- `scripts/scene_art.gd`: procedural game models and shared material palette.
- `scripts/unit_portrait.gd`: technical portrait glyphs drawn in code.

## Image prompts

The command deck also uses `assets/textures/command-metal.png`, generated with the built-in image tool for this interface pass. `assets/icons/*.svg` are original code-authored vector glyphs for commands, structures, and unit roles. Command cards reuse the resource glyph shapes and colors from the resource strip; queue chips show progress/readiness and explicit cancellation marks.

### Command panel material

Use case: stylized-concept. Asset type: seamless tiling background material for the command interface of an industrial science fiction horror RTS. A flat overhead macro surface of worn dark graphite powder-coated steel, very restrained fine brushed grain, faint scuffs and tiny scratches, smoky desaturated green undertone. Mostly uniform low-contrast charcoal, no large streaks, no bright highlights, no seams, no panels, no rivets, no text, no objects, no borders, no UI. Perfectly diffuse flat lighting. Seamless on all four edges. Texture must remain quiet beneath small cream interface text. Square.

### Ground material

Use case: stylized-concept. Asset type: seamless square albedo ground texture for a top-down 3D industrial science-fiction horror RTS, used across a large continuous terrain surface. Primary request: a production-quality physically flat overhead ground material of charcoal basalt regolith, dark gray ash, compacted fine gravel, scattered small angular shale fragments, faint branching hairline fractures, very subtle muted dusty olive undertones. Rich fine tactile detail with broad quiet areas. Flat diffuse neutral illumination, no directional baked shadows, no perspective, no horizon, no objects or landmarks, no vegetation, no buildings, no text, no UI. Seamlessly tileable on all four edges. Restrained contrast and medium gray base values so the engine can light and tint it. Consistent world-scale variation rather than obvious repeating large cracks. Square 1024x1024.

### Title illustration

Use case: stylized-concept. Asset type: 16:9 title-screen background illustration for Erebus, a 3D industrial science fiction horror RTS. Primary request: a beautiful restrained painterly 3D concept illustration of a small expedition outpost surrounded by absolute alien night. Right half of composition: one compact graphite steel orbital Anchor lander with three squat landing feet, a few ivory armor panels, thin worn blue faction markings, a mast and tiny amber warning beacon. Beneath its warm industrial work lamps stand two small helmeted human expedition soldiers in heavy practical charcoal and ivory suits, seen from a high RTS camera angle on rough basalt regolith. Black jagged cliff silhouettes and receding ground texture disappear into cold dark mist. Two barely visible pale crab-like scavenger shapes linger at the far edge of the light. Strong graphic silhouettes, careful material contrast, tactile brushwork, cinematic but understated. Palette charcoal, desaturated slate, dusty ivory, warm amber, tiny accents of blue. No neon. The LEFT 45 percent must remain very dark, low detail negative space for a menu overlaid in the game. Wide composition, sophisticated negative space, a lonely island of light in an enormous darkness. No text, no logos, no UI, no watermark. Match a grounded stylized game world rather than photorealistic action-film spectacle.

## Reviewing the actual game

Use the review fixture with `-- --relay` for `build/visual-review/relay-on.png` and `relay-off.png`, showing the same source/Relay/remote Floodlight layout and its grid controls in both states.

Run `npm run export:web` and `npm run serve`, then `node tools/capture-look.mjs`. The capture helper records the real title screen, normal gameplay view, and a closer view under `build/visual-review/`. Inspect these captures and play the scene after changes; a successful import alone does not establish visual quality.

For a staged review of all six vehicle models and the crew inspector, run Godot with `--path . --script tools/preview-vehicles.gd`. It saves `build/visual-review/vehicles.png` and exits. This review fixture is excluded from the browser export.

The vehicle review helper also accepts `-- --sensors` to stage a powered Radar/Rampart/Lance cluster and a concealed contact, writing `build/visual-review/sensors.png`. This exercises the actual HUD, coverage overlays, anonymous contact marker and effective-armor inspector.

For combat review, the same helper accepts `-- --combat` and saves `build/visual-review/combat-feedback.png`. The pass adds weapon-specific ribbons/flashes, short damage overlays, shield impacts, debris, health trails, distinct Scavenger/Ravager proportions, and work-state machinery. The five new WAV cues are original deterministic synthesis from `tools/generate-feedback-audio.py`; no third-party recording license is required. See [feedback implementation](feedback.md) for tuning.

Remaining art work includes more individual industrial structure designs, refined animation and work/weapon effects, detailed Lightless silhouettes, and a broader sound palette. The current models are still procedural production placeholders.


## Father silhouette

The Father is a floating squid-like coordinator with a broad flesh-toned mantle,
pale dorsal carapace plates, lateral fins, amber eyes and eight tapered hanging
arms. Two longer feeding arms and curled tips distinguish it from crawling
Scavengers. It has an original command icon and matching squid portrait.
Hover, travel lean and staggered tentacle waves follow the presentation clock and
freeze while paused; movement, collision and gameplay ranges remain simulation-owned.
`presentation.fatherMotion` controls hover amplitude/frequency, tentacle amplitude/
frequency and movement lean. The existing Father creature scale still applies.
Use `tools/preview-vehicles.gd -- --father` with the native renderer to capture
`build/visual-review/father-0.png` and `father-1.png` beside a Scavenger for scale.

## Mother shambler

The Mother is a hunched biped with an oversized, lopsided head, sunken eyes, slack
jaw, exposed ribs, long hanging arms and splayed feet. Its uneven zombie-like gait
uses a stronger lead step, a delayed dragging leg, rocking shoulders and head lag.
The idle pose stays stooped; pausing freezes the pose. Its portrait and command icon
match the shambler silhouette. This changes presentation only.
`presentation.motherMotion` controls step frequency, leg swing, drag ratio, body sway
and head lag. The existing Mother creature scale still applies. Use the native
`tools/preview-vehicles.gd -- --mother` fixture for two walking-phase captures at
`build/visual-review/mother-0.png` and `mother-1.png`, beside a Scavenger for scale.

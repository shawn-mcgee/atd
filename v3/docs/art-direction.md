# Art direction and presentation assets

The visual target is a small industrial expedition holding a warm island of light against a cold, organic frontier. Gameplay readability takes priority over decorative detail.

## Palette and shapes

Use graphite steel and dusty ivory for Commonwealth equipment, with faction color confined to armor markings. Work lamps, warnings, and tool sparks use restrained amber. Lightless use bone, shale, and muted flesh tones; Gloom provides the darker organic color field. Avoid large saturated faction-colored surfaces.

Human structures use broad, grounded silhouettes, beveled armor plates, exposed supports, and small status lights. Scavengers use low bodies, pointed heads, and asymmetric walking phases. The Anchor should read as a lander, the Extractor as a working drill, and the Floodlight as a tall mast at the normal camera distance.

The terrain shader uses world-space texture coordinates across hexes. The placement grid remains a gameplay rule; it should become prominent during construction rather than make the whole landscape look like a board. A filtered visibility texture softens the fog edge. The ground shader masks local lamp contribution with the actual illumination field.

## Motion and feedback

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

Run `npm run export:web` and `npm run serve`, then `node tools/capture-look.mjs`. The capture helper records the real title screen, normal gameplay view, and a closer view under `build/visual-review/`. Inspect these captures and play the scene after changes; a successful import alone does not establish visual quality.

For a staged review of all six vehicle models and the crew inspector, run Godot with `--path . --script tools/preview-vehicles.gd`. It saves `build/visual-review/vehicles.png` and exits. This review fixture is excluded from the browser export.

The vehicle review helper also accepts `-- --sensors` to stage a powered Radar/Rampart/Lance cluster and a concealed contact, writing `build/visual-review/sensors.png`. This exercises the actual HUD, coverage overlays, anonymous contact marker and effective-armor inspector.

For combat review, the same helper accepts `-- --combat` and saves `build/visual-review/combat-feedback.png`. The pass adds weapon-specific ribbons/flashes, short damage overlays, shield impacts, debris, health trails, distinct Scavenger/Ravager proportions, and work-state machinery. The five new WAV cues are original deterministic synthesis from `tools/generate-feedback-audio.py`; no third-party recording license is required. See [feedback implementation](feedback.md) for tuning.

Remaining art work includes more individual industrial structure designs, refined animation and work/weapon effects, detailed Lightless silhouettes, and a broader sound palette. The current models are still procedural production placeholders.


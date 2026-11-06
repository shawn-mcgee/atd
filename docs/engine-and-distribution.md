# Engine, platforms, and distribution

## Confirmed targets

Use **Godot** with **3D presentation** for a **browser-only alpha**. Multiplayer is **player-hosted WebRTC using Trystero**. The active deployment routes are:

| Build | Distribution |
| --- | --- |
| Browser-playable web export | GitHub Pages and itch.io |
| Windows and Linux exports | Deferred; eventual downloads through GitHub Releases and itch.io |

The repository origin is `https://github.com/shawn-mcgee/atd`. If project Pages is enabled without a custom domain, its expected location is `https://shawn-mcgee.github.io/atd/`. This is a planned deployment address, not evidence of a published game. The itch.io account and project slug remain to be selected.

Native desktop export work is halted for the alpha. Windows and Linux remain intended later targets; macOS remains outside the test scope. The alpha must be tested in desktop browsers, including on the developer's available operating systems, but does not require native executable packaging. Mobile support is not part of the current scope.

## Technical baseline

The project pins **Godot 4.7.2** in `.godot-version`. The setup helper installs the matching editor and non-threaded web export templates. Engine upgrades should be explicit changes verified against the browser alpha.

Use **GDScript**, the **Compatibility renderer**, and an initially **single-threaded web export**. Godot's current web export requires WebAssembly/WebGL 2.0 and Compatibility rendering; Godot 4 C# projects cannot currently export to web. Single-threaded exports avoid the cross-origin-isolation requirements of threaded exports. These recommendations follow the [official Godot web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

Keep simulation logic, orders, entity state, and the prototype JSON independent of scene presentation. Browser limits influence scheduling and performance budgets from the start, particularly pathfinding, Gloom propagation, and expedition updates. No gameplay rule should require a background thread to function. Bundle Trystero with a JavaScript adapter exposed to Godot through its browser JavaScriptBridge; see the [networking plan](networking.md).

Presentation is **3D**, with the confirmed pointy-top hex grid still governing structure placement and continuous movement handled separately. Use the StarCraft II-style camera described below. The 3D asset pipeline remains to be defined, and visual features must work with the web-compatible renderer baseline.

## Camera and navigation

Use a **perspective camera** with an elevated RTS viewing angle, a stable default orientation, bounded zoom, and temporary rotation. This follows the requested StarCraft II reference: the [DeepMind/Blizzard research paper](https://storage.googleapis.com/deepmind-media/DeepMind.com/Blog/deepMind-and-blizzard-open-starcraft-ii-as-an-ai-research-environment/sc2le.pdf) describes its perspective rendering, and [Blizzard's controls guide](https://news.blizzard.com/en-us/article/4552955/game-guide-special-control) documents wheel zoom and holding Insert/Delete for temporary 90-degree rotation, with the original view restored on release.

The project adopts that camera style rather than claiming identical proprietary camera settings. The following are proposed first-playable values, editable in `camera` within [prototype.json](../config/prototype.json):

| Property | Proposed default |
| --- | --- |
| Projection | Perspective |
| Pitch | 55 degrees downward from horizontal |
| Default yaw / roll | 0 / 0 degrees |
| Vertical field of view | 40 degrees |
| Distance from ground focus | 24 tiles; minimum 12, maximum 32 |
| Wheel step | 2 tiles per notch |
| Pan speed | 18 tiles per real-time second at default zoom |
| Edge-scroll band | 12 logical viewport pixels |
| Rotation | Hold Insert: 90 degrees left; hold Delete: 90 degrees right; release to restore |

Pitch remains fixed during play; no free orbit or tilt control is introduced. Wheel zoom changes camera-to-focus distance while retaining the field of view and ground focus. A damped transition approaches the requested distance and orientation, with configurable response times. Exact visual matching and comfort remain playtesting tasks.

Support all four requested navigation methods:

- **Edge scrolling:** Pan when the pointer is inside the game viewport's edge band. Diagonal input is normalized. Disable it while the viewport lacks focus, the pointer is outside the canvas, or a UI overlay captures the pointer.
- **Keyboard panning:** WASD and arrow keys by default, represented as rebindable input actions. Ignore camera keys while a text field captures keyboard input.
- **Mouse dragging:** Hold the middle button to grab the ground plane and drag the view. Ray-plane movement keeps the same ground point under the pointer; it does not depend on units or structures under the cursor. Dragging takes precedence over edge scrolling.
- **Wheel zoom:** Wheel forward zooms in and backward zooms out within the distance limits. Only consume wheel events over the active game canvas when UI has not captured them.

Keyboard and edge movement follow camera-relative screen directions projected onto the ground plane, including during temporary rotation. Scale pan speed with zoom distance relative to the default, normalize combined input, and clamp the ground focus to the map's hexagonal bounds. The camera can see the boundary wall but cannot pan its focus beyond the map.

Navigation uses real time and remains available while a single-player simulation is paused. Game speed does not change camera speed. Losing focus cancels held pan/rotation/drag state so the view does not keep moving after returning to the game.

Camera movement, zoom, and rotation never reveal tiles or bypass fog of war, illumination, or detection. Camera preferences are local presentation data: exclude them from the multiplayer simulation-settings hash and allow per-player controls without changing match rules.

## Export artifacts

Export the browser entry point as `index.html` and preserve its associated generated filenames. Include all emitted JavaScript, WebAssembly, packed resources, and other required files. Use relative asset paths so the export works beneath the repository's `/atd/` path and inside an itch.io embed. See [Godot's export naming rules](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

Deploy the web export directory to GitHub Pages. Package that same directory as a ZIP with `index.html` at the archive root for itch.io's HTML-game upload. Include the pinned Trystero bundle and its Godot adapter. The HTML ZIP requirements and embedded browser behavior are documented in [itch.io's creator documentation](https://itch.io/docs/creators/html5).

Windows and Linux archives, native export presets, desktop WebRTC integration, and desktop download publication are deferred. The eventual intended destinations remain GitHub Releases and itch.io; none is an alpha release gate.

Use one version identifier, source revision, pinned networking-library version, and resolved gameplay-configuration identifier across the Pages and itch.io artifacts for the same alpha release. Build them from the same source revision so players can join compatible rooms across both hosted copies.

## Build and publication plan

1. Create the 3D Godot project with a pinned version.
2. Add the web export preset and bundle the pinned Trystero adapter. Do not require desktop export presets for the alpha.
3. Add headless import, configuration validation, and smoke checks in CI.
4. Produce the complete web export and itch.io ZIP as build artifacts before publication.
5. Deploy that alpha to GitHub Pages and itch.io.
6. Verify both hosted copies and cross-site Trystero rooms in actual browsers.

The Godot project, web export preset, Trystero bundle, headless checks, browser tests, ZIP packager, and build/test workflow now exist. See [implementation status](implementation-status.md) for coverage and local commands. The main-branch browser-alpha workflow tests and deploys the root project to GitHub Pages. The itch.io destination and publication credentials have not been configured.

## Multiplayer hosting

Players host the alpha's matches through **Trystero/WebRTC**. The implemented foundation runs the simulation and initial Lightless behavior in the hosting player's browser. Other clients submit orders and receive host-confirmed results. See [Browser alpha networking](networking.md) for the integration, room lifecycle, and proof-of-connectivity requirements.

GitHub Pages is [static file hosting](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages); it serves the client rather than running the simulation. Trystero's signaling strategy and any required TURN fallback remain connectivity configuration, separate from hosting gameplay on a player's machine.

Player hosting, WebRTC, and Trystero are decided for the alpha. Host departure or detected connection loss ends the match for everyone, with no migration or recovery attempt. Non-host departure eliminates that player; assets continue their existing orders and vehicles unload their occupants. The adapter defaults to Nostr signaling; public relay validation and a TURN provider remain pending. There is no reconnect recovery. No dedicated gameplay-server deployment or native Godot/Trystero interoperability is required for this alpha.

## Platform acceptance checks

- Load at the actual project Pages subpath with no missing assets, including a fresh browser cache.
- Load inside itch.io's frame, with working input focus, resizing/fullscreen, and audio after user interaction.
- Run the same resolved gameplay settings and map seed through both hosted web copies; compare host-confirmed logical results, not just editor behavior.
- Exercise browser single-player pause/speed controls and a full extraction match.
- Test every camera control in supported browsers on available Windows/Linux machines, the actual Pages deployment, and the itch.io embed. Verify edge behavior, mouse focus, paused navigation, wheel capture, temporary rotation reset, and hex-map camera bounds.
- Connect browser clients hosted on Pages and itch.io in the same Trystero match; native desktop clients are deferred.
- Measure late-match entity counts, pathfinding, Gloom, and convoy behavior in the single-threaded browser build.
- Verify browser Nacre persistence. Storage on the Pages origin and itch.io origin does not imply shared balances or cross-device synchronization; persistence and account policy remain open.

These are full-alpha acceptance requirements. The local browser foundation has automated smoke coverage; live deployments, full matches, and performance acceptance remain pending.

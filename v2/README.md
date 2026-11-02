# Rewrite foundation

Open `v2/project.godot` in Godot 4.7.2. The original game remains in `project/`.
The master design is [atd.md](../atd.md). Existing `game.gd`, `world.tscn`, and
`Assets/` are retained; the new entry is `scenes/prototype.tscn`.

This prototype is a sandbox with primitive meshes, a locked top-down orthographic
camera, movement, targeted combat, queued production, and Veil with global stances.
It is not yet the nacre mission. Briar mechanics, construction, full faction AI, logistics, progression,
and mission resolution remain to be implemented. Initial banks and costs are
sandbox fixtures, not implementations of ore, gas, chyme gathering, or nacre delivery.

## Author and play

The configurator provides JSON validation, a seed, and faction selection. Starting
locally adds an AI participant of the missing faction. This initial AI only acquires
and attacks enemies in sight; full species behavior follows later.

- Left-click selects; Shift adds. Right-click moves or attacks.
- Select HQ/Nest, choose a product, and press **Produce selected type**.
- WASD/arrows pan; the wheel zooms. The orthographic camera does not rotate.
- The HUD shows ownership, health, armor, weapon stats, production, ticks,
  confirmation, rollback count, and state hashes.
- Toggle Veil, local connections, illumination and perception overlays. Select a
  connected Lightless unit/structure to set its participant's global Veil stance.
- Neutral preserves default behavior. Defensive responds to threats inside Veil.
  Offensive asks for an outside point and directs units there. Newly connected
  Lightless inherit the global stance; units retain it after leaving. Direct unit
  orders take priority until complete. Stance-driven units attack enemies they can
  see and otherwise investigate last-known alert/target positions.
- **Q / Attack Veil** enters membrane attack targeting; click visible hostile Veil.
  Escape cancels. Walking over Veil never directly damages it.
- Return to the configurator to change definitions and start a fresh session.

`content/default.json` is the starting preset. Add a definition under `units`,
choose a primitive (`box`, `sphere`, `capsule`, `prism`, `cylinder`), compose
capabilities, and add its ID to a factory's `produces` list. Implemented capabilities
are `move`, `weapon`, `perception`, `illumination`, `detection`, `factory`, and `veil_source`.
Unsupported capabilities produce validation errors. Native preset save/load uses
file dialogs; browsers download exports and accept imports by pasting JSON.

Times use ticks at configurable `tick_hz`; speed is tiles/second and ranges are tile
steps. Core positions use integer axial sub-tiles at 1/1024 tile with a reserved
elevation coordinate; the view maps them to Vector3 positions. The arena is flat
and unobstructed: terrain routing and occlusion are not implemented. Zero minimum
damage is an exposed experimental default, not a settled armor decision.

## Veil slice

The Nest has `veil_source` by default. Add this capability to other stationary
Lightless definitions with integer `radius`, `growth_interval_ticks`, and
`growth_tiles`. Growth begins under its source and branches through adjacent empty
hexes, within radius. In this flat prototype, an occupied tile means a tile
containing any actor; the source's own tile is the exception. Units moving away
make those tiles eligible again. Communication does not allow growth to jump gaps.

`settings.veil` configures tile HP, illumination damage/tick, unsupported decay/tick,
alert cooldown and last-known-threat memory duration. Light blocks new growth and
damages existing membrane; perception does neither. Existing damaged Veil does not
passively heal. Destroying a source removes its support. Shared areas maintained
by surviving sources remain; only unsupported tissue decays.

All patches owned by the Lightless participant communicate globally. There is no
gap, splitting or merging logic. Units connect on Veil or one adjacent hex away.
Friendly and hostile entry are both detected. Alerts reach connected recipients
across the map; units outside connection range do not receive them. Illumination
damage, membrane destruction and Nest attacks also alert the global network.
Continuous alerts are throttled; tile-destruction alerts are always delivered.
Hostile occupancy remains sensed while the unit stands on Veil, without repeated
entry notifications; after it leaves, only its last-known location is retained.
The HUD only displays a participant's own Veil notifications, after confirmation.

Veil tiles, source claims, growth schedules, contacts, alert cooldowns, global
stance/target, and inherited unit orders are all checkpoint state. Overlay drawing
is read-only. Faction-specific species tactics and Father abilities remain pending.

## WebRTC and rollback

Browsers have WebRTC built in. On desktop, install the native dependency from the
outer repository root and restart Godot:

```powershell
python tools/setup-webrtc.py
```

This installs official `webrtc-native` 1.2.2 with a pinned SHA-256 check under
ignored `v2/addons/webrtc_native/`.

Choose factions before connecting, **Host room**, share its code, and **Join room**
on other peers. The host presses **Start network match** when everyone has joined.
Only one Lightless participant is allowed. Host content, seed, roster, protocol,
and engine version are verified before start. The initial descriptor is limited
to 60KB.

The default coordinator is the user's deployed `webrtc-coordinator`. Its signaling
WebSocket stays connected. Each client opens a reliable ordered WebRTC data channel
to the host, which authenticates and relays input. Every peer simulates the match
using rollback; the host does not stream authoritative gameplay state.

Missing frames predict no new commands. Late nonempty frames restore a checkpoint
and replay affected ticks. Ordering is tick, player ID, then within-frame order.
Presentation receives only confirmed events; future victory/progression effects
must use the same confirmation boundary. Confirmed hashes are exchanged. Conflicting
inputs and desyncs stop the session. A missing peer stalls advancement before
unconfirmed history is discarded.

ICE servers are configurable JSON. Default public STUN is not sufficient for every
network; supply TURN URLs/credentials for restrictive networks. Credentials are not
saved in content presets. Signaling reconnect can preserve existing RTC connections
within the coordinator's token window. Mid-match joining, game-state reconnect,
host migration, and network pause are not implemented. An RTC disconnect requires
a new match.

## Code map

| Work | Entry |
| --- | --- |
| Content schema and validation | `core/content.gd`, `content/default.json` |
| Roster and AI fallbacks | `core/match_rules.gd` |
| Ticks, state, commands, restore | `core/simulation.gd` |
| Veil growth, support, alerts and global stance | `core/veil.gd`, `core/hex_cells.gd` |
| Canonical hashing | `core/canonical.gd` |
| Input history, rollback, confirmation | `net/rollback_session.gd` |
| Lobby, input relay, desync checks | `net/match_session.gd` |
| Signaling and RTC connections | `net/coordinator_transport.gd` |
| Configurator, meshes, camera, HUD | `view/prototype.gd` |
| Read-only membrane and senses overlays | `view/veil_overlay.gd` |

Keep core state integer-based and free of nodes, rendering, wall time, native
physics, and unseeded randomness. Definitions are copied at initialization. Every
mutable gameplay value belongs in checkpoints; derived caches must be rebuilt
consistently. AI runs inside the core. Camera and selection remain view-only.

## Validate and export

Run from the repository root, substituting the local engine path:

```powershell
python tools/test-rewrite.py --godot <GodotExecutable> --network
python tools/test-game.py --godot <GodotExecutable> --jobs 3
```

The rewrite runner imports first and rejects script errors even on exit zero.
Import/Web export use recovery mode to avoid native-extension DLL reload locks
when the project is already open in a Windows editor; actual tests still load WebRTC.
`--network` creates a temporary room on the deployed coordinator and tests two
actual RTC peers, deliberately late input, rollback, and confirmed hash equality.
Without it, validation is offline. Logs are ignored in `v2/test-results/`.

The foundation suite covers content validation and authored units, faction limits,
ownership, production, RNG restoration, JSON checkpoints, turret-only sensor
targeting, late input, confirmed events, and bounded history. Its shared
`tests/veil_suite.gd` also checks growth/illumination, global alerts, friendly and
hostile entry, stance adoption/response, overlap support, source decay, weapon
clearing, and rollback after a late intrusion. View tests check overlay isolation.

With matching Web export templates installed:

```powershell
pwsh -File tools/build-web.ps1 -GodotExecutable <GodotExecutable> -ProjectDirectory v2
python -m http.server 8000 --directory build/rewrite-web
```

`tools/test-rewrite-browser.cjs` serves the export on an ephemeral loopback port,
runs the same suite in Chromium, compares the native result, captures the view,
and tests two browser peers through the coordinator. Use an externally installed
Playwright package and Chromium:

```powershell
node tools/test-rewrite-browser.cjs --playwright <PathToPlaywrightPackage> --chromium <ChromiumExecutable> --godot <GodotExecutable>
```

`--godot` also runs a real native-host/browser-client match and compares confirmed
hashes. The browser test interface is available only with `?selftest=1`. Matching native/Web
hashes validate covered scenarios, not future gameplay. Run
`res://tests/benchmark_rollback.gd` headlessly to measure checkpoint/rollback cost
for 128 sandbox actors. This is not a scale guarantee for later navigation or Veil.

# Rewrite foundation

Open `v2/project.godot` in Godot 4.7.2. The original game remains in `v1/`.
The master design is [atd.md](../atd.md). Existing `game.gd`, `world.tscn`, and
`Assets/` are retained; the new entry is `scenes/prototype.tscn`.

This prototype has primitive meshes, a locked top-down orthographic
camera, movement, targeted combat, queued production, Mother/Womb construction,
a Lightless chyme loop, Nest-loss escalation, Veil with global stances, and the first
nacre mission loop. Briar mechanics, Human construction, full faction AI, ore/gas
logistics and persistent progression remain pending. Initial reserves, costs, rates,
carrying limits, free mission repair and mission timers are prototype fixtures.

## Author and play

The configurator provides JSON validation, a seed, and faction selection. Starting
locally adds an AI participant of the missing faction. This initial AI acquires and
attacks enemies in sight, returns full chyme cargo, and assigns Human workers to
repair and known nacre deposits. Strategic exploration and full species behavior follow later.

- Left-click selects; Shift adds. Right-click moves or attacks.
- Select HQ/Nest, choose a product, and press **Produce selected type**.
- Humans: select an engineer and right-click your damaged extraction point to repair.
  Destroy the Nest, then right-click its revealed nacre remains to mine. Full cargo
  returns to your point, then mining resumes. **Start extraction** becomes available
  after the delivered threshold; you choose when to begin defending the countdown.
- Produce a Mother at the Nest, select a structure and press **Place Lightless
  structure**. Left-click a revealed empty tile. Right-click/Escape cancels targeting.
  **Cancel construction / refund** restores a growing Womb to its Mother.
- Scavengers collect chyme by damaging enemies. Right-click your Nest to deliver it,
  or press **Deliver chyme to nearest receiver**. Cargo becomes spendable only after delivery.
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

`content/default.json` is the main preset, importing `settings.json` and one JSON
file per actor under `content/{human,lightless}/{units,structures}/`. Select a file
in the configurator's searchable tree to edit it. Add a definition under `units`,
choose `capsule` or `cylinder`, set `visual.radius` (0.05–4 tile inner radii), compose
capabilities, and add its ID to a factory's `produces` list. Implemented capabilities
are `move`, `weapon`, `perception`, `illumination`, `detection`, `factory`, `veil_source`,
`chyme_collector`, `chyme_receiver`, `chyme_source`, `metamorphosis`,
`mission_worker`, and `extraction_point`.
Unsupported capabilities produce validation errors with a filename and field path.

### Configuration files

An `imports` array merges files relative to the file containing it. Imports apply
in listed order, followed by the importing file's own fields. Objects merge
recursively; arrays and scalar values replace earlier values. For example, a new
preset alongside `default.json` can tune one unit without copying its definition:

```json
{
  "imports": ["default.json"],
  "units": {"engineer": {"hp": 25}}
}
```

Imports can refer to parent directories inside the main preset's directory, but
cannot leave that directory or use absolute paths/URLs. Missing files, syntax
errors, import cycles and excessive depth produce errors before a match starts.
Projects are limited to 128 files, 16 import levels and 2 MB of source text.

- **Find file or definition** searches filenames and contents. Switching files
  retains edits, including temporarily invalid JSON; `*` marks modified files.
- **New imported file** creates an empty JSON file and adds it to the main file's
  imports. **Validate** discovers imports added by hand and validates the merged match.
- **Save files** writes the individual native source files. It refuses to overwrite
  a file changed externally since loading; export your edits before reloading it.
  Imported portable projects ask for a main-file destination on their first save.
- **Export project** saves every text buffer and relative filename in one portable
  `atd-project.json`, retaining the file layout and unfinished drafts. Browser
  **Save files** downloads this project bundle as well.
- **Export merged** creates a single validated `atd-content.json` with no imports.
  **Load project** accepts either a main JSON file (native), a portable project
  bundle, or a merged preset. Browsers use a file picker for bundles/merged presets;
  referenced native files must be bundled first. **Defaults** reloads the shipped project.

Only merged, validated definitions enter simulation checkpoints and network match
descriptors. Equivalent split and flat presets have the same content fingerprint;
peers do not read one another's local files. Source editing is pre-match only.

Actor meshes only support capsules and cylinders. `visual.radius` is measured in
tile inner radii: the distance from a hex center to the midpoint of an edge (the
apothem), not to a vertex. A radius of 1 gives the tile's inscribed circle, touching
all six edges without overflowing; 0.5 is half that radius. The grid has a unit
center-to-vertex distance, so the world-space radius is `visual.radius * sqrt(3) / 2`.
Movement and weapon ranges continue to use tile inner diameters. Radius controls
the visible body, selection outline and picking, without changing collision, occupancy
or combat range. Capsule height is three radii; cylinder height is two radii.
A white line starts at each body mesh's local origin and extends forward beyond
its radius. Actors initially face northwest (negative r), turn toward movement/combat/work targets,
and retain their facing when idle or stopped. Facing is an integer axial direction
in checkpoint state, so rollback and different rendering frame rates show the same
orientation. Old presets using other shapes or omitting radius must be updated.

Times use ticks at configurable `tick_hz`; speed is tiles/second and ranges are tile
steps. Core positions use integer axial sub-tiles at 1/1024 tile with a reserved
elevation coordinate; the view maps them to Vector3 positions. The arena is flat
and unobstructed: terrain routing and occlusion are not implemented. Zero minimum
damage is an exposed experimental default, not a settled armor decision.

## Nacre mission

The default `settings.mission.enabled` is true. Each Human receives one damaged
extraction point three tiles from HQ. It starts at one quarter health; 60 engineer
work ticks repair and activate it, restoring its health. This initial objective
repair is free and cannot rebuild a destroyed point. An engineer's `mission_worker`
configures cargo `capacity`, `mining_amount`, `mining_interval_ticks` and `work_range`.

Destroying the Nest exposes one shared finite deposit (100 nacre by default), while
also triggering Lightless escalation. Ordinary perception/illumination discovers
the remains; detection alone cannot. Known remains can be targeted after vision
leaves, but their current quantity is shown only while visible. Engineers physically
mine, carry up to 10 nacre, and return full or final cargo to their own extraction
point. The point accepts delivery during the countdown. HQ, other receivers and
other participants' points reject nacre. Death loses undelivered cargo. Nacre never
enters production banks. Mining resumes after automatic delivery; move/stop interrupts.
A return to an inactive point repairs it before depositing.

Delivering `threshold` (20 by default) enables **Start extraction** without starting
it automatically. The countdown lasts `countdown_ticks` (200) after the start tick.
Additional deposited nacre counts in the winning outcome. Destroying a Human's HQ
or extraction point defeats that Human, disables its remaining actors and clears
orders/production. Its survivors remain attackable. Lightless AI prioritizes active
opponents. The Lightless win after every Human, including AI Humans, is defeated;
the first Human to finish extraction wins for everyone. Defeat resolves before
countdown completion, so losing a point on the last tick prevents extraction.
Simultaneous successful extractions use deterministic roster order as a prototype tie rule.

Results, objective IDs, repairs, deposits, cargo, mine schedules, finite deposits,
discovery and countdowns are checkpoint state. Speculative results freeze gameplay
while input confirmation continues; late input can overturn an unconfirmed result.
The HUD announces the winner only after confirmation. The outcome records raw
extracted nacre; persistent progression and reward formulas remain unimplemented.
Older presets can omit `mission`, or set `enabled: false`, for the prior sandbox.
AI workers repair, mine known deposits and start a ready countdown; AI does not yet
strategically explore, escort or develop its faction.

## Chyme slice

Scavengers have `chyme_collector` with integer `capacity` and `yield_per_damage`.
Collection uses actual enemy health removed after armor and minimum damage, capped
by remaining cargo space. Overkill and membrane damage yield no extra chyme.
Full collectors can keep fighting. Death removes undelivered cargo; there are no drops.

Stationary Lightless definitions can have `chyme_receiver` with a delivery `radius`
and/or `chyme_source` with integer `amount` and `interval_ticks`. Neither requires
being on Veil. The preset Nest accepts deliveries and generates one chyme every 20
ticks, starting after a full interval. Generation stops when its source dies.
`settings.chyme.initial_reserve` sets starting Lightless chyme (100 if omitted).
Human banks are still sandbox credits. Lightless factory costs spend shared chyme
when queued; undelivered cargo cannot pay. Reserve storage is currently unbounded.

`deliver_chyme` accepts a receiver actor ID or selects the nearest owned receiver
(lowest actor ID breaks ties). It moves the collector into delivery range, transfers
all cargo once and completes. A destroyed receiver cancels the order and preserves
the cargo. Move/stop/attack commands can interrupt delivery. AI collectors return
when full unless following an explicit order; broader harvesting tactics remain pending.
Cargo, source schedules and delivery orders are checkpoint state; economic notices
are emitted through confirmed events. Older presets can omit all chyme capabilities.
State and network protocol are version 7; older peers must update before joining.

These values and policies are prototype choices, not settled balance.

## Nest-loss escalation

Destroying the Nest credits its Lightless owner once and permanently accelerates
that participant's stationary Lightless factories and growing Wombs. The preset
`settings.nest_loss` gives `chyme_grant: 500`, `production_rate: 2`, and
`construction_rate: 2`. Rates are integer work units per tick (1–8), not changes
to tick frequency, costs, movement, attack intervals, passive income or Veil growth.
Existing production queues and construction progress use the new rate immediately
from the following tick. Production carries spare work into subsequent queue entries.
Grant and bonuses resolve at the end of the death tick, before dead actors are removed;
they never depend on which factory acted before the killing attack. This is escalation,
not mission completion: Humans must still mine, deliver and successfully extract.

The prototype sets `affect_new_structures: true`, so later structures and Wombs
inherit the bonus. Set it to `false` to restrict bonuses to structures and Wombs
alive at the death boundary. An existing Womb keeps eligibility when it matures;
cancelling it releases eligibility, so a rebuilt structure cannot reuse the old bonus.
Mothers and Human actors receive no structure bonus. Losing other structures does
not trigger escalation. The Nest still cannot be rebuilt.

The grant guard, death tick and eligible actor IDs are checkpoint state. Late killing
attacks replay the reserve, work and confirmations without duplicate rewards.
The HUD shows local Nest status, each selected factory/Womb's actual work rate and
remaining work, plus an owned confirmed grant notice. Older presets may omit
`nest_loss` to retain the previous behavior. Rates, grant and inheritance are
explicit sandbox policies pending final mission balance.

## Mother/Womb construction

The Nest can produce Mothers. `metamorphosis` lists a builder's `womb` definition
and permitted `structures`. Each target has integer `construction_ticks`; the Womb
is a Lightless definition with no active capabilities. The preset offers a
Scavenger Spawner (production, delivery and Veil) and an experimental Chyme Pool
(passive income and delivery). Costs, health and times are configurable fixtures.

Perception and illumination permanently reveal tile centers for their owner;
detection does not. Revelation is checkpoint state and permits construction after
senses leave. The view's green/red hex preview checks known information only;
the core revalidates actual occupancy. Every structure currently occupies one tile.

A build order reserves a revealed empty tile and moves its Mother there. It pays
the target's chyme cost only on arrival, then transforms the Mother into a vulnerable
Womb at the same actor ID. The Womb cannot move, produce, receive deliveries or
grow Veil. It matures after the target's duration; completion waits for any units
passing through its tile to leave. The finished structure activates its capabilities,
and passive generation waits its full interval. There is no Nest rebuild path.

Cancelling travel releases the reservation without changing resources. Cancelling
a living Womb refunds its paid cost once and restores its Mother. Damage persists
proportionally, rounded against healing; undamaged cancellation restores the exact
original health. Completed structures retain the Womb's health fraction. Destroyed
Wombs lose both the Mother and investment. If a site becomes occupied or reserves
run short during travel, the unpaid order cancels. Move/stop can interrupt travel;
only the cancel command interrupts a growing Womb.

The construction lifecycle, reservations, refunds and revelation replay through
rollback; notices use confirmed events. Discovery's position cache is derived and
rebuilt on restore. This flat arena still has no terrain routing or structural
movement blocking. Mother AI, Human engineering, footprints larger than one tile,
and Briar defenses remain pending.

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
| Import graph, source buffers, merge and project persistence | `authoring/config_files.gd` |
| Configurator file navigation and editing | `view/config_editor.gd` |
| Roster and AI fallbacks | `core/match_rules.gd` |
| Ticks, state, commands, restore | `core/simulation.gd` |
| Veil growth, support, alerts and global stance | `core/veil.gd`, `core/hex_cells.gd` |
| Chyme collection, delivery and passive generation | `core/chyme.gd` |
| Mother/Womb lifecycle and site validation | `core/construction.gd` |
| Remembered revealed ground | `core/exploration.gd` |
| Nest death grant and permanent development rates | `core/nest_escalation.gd` |
| Nacre, extraction, Human defeat and match outcomes | `core/mission.gd` |
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
`tests/chyme_suite.gd` covers armor/overkill/capacity, delivery ownership and loss of
receivers, passive schedules, AI cargo return, production spending, JSON restore,
late collection input and exactly-once confirmed economic events. View tests also
check cargo/reserve inspection and delivery through the command queue.
`tests/construction_suite.gd` covers revealed ground, placement reservations,
Womb vulnerability, refunds, completion, source activation and rollback. View tests
check read-only placement and actor meshes across transformation and cancellation.
`tests/escalation_suite.gd` checks one-time grants, tick-boundary rate changes,
existing/future structure policies, queue work budgets, passive-income isolation,
refund eligibility and replay of delayed lethal input.
`tests/mission_suite.gd` covers finite mining, repair/receiver ownership, cargo loss,
delayed extraction, extra deliveries, all-Human defeat, JSON restore and overturning
an unconfirmed Human win through a delayed lethal attack. View tests cover objective
controls and read-only HUD inspection.
`tests/config_files_suite.gd` checks import resolution, precedence, source errors,
cycles, portable project roundtrips and native save conflicts. View tests check
navigation, search and preserving invalid/unsaved edits across file switches.

For rendered construction review, run `res://tests/preview.gd` with `-- --construction`
(add `--womb` for growth progress). It drives production and placement through the
session, saving `test-results/construction.png` or `test-results/womb.png`.
Add `--nest-loss` with `--womb` for `test-results/nest-loss.png`.
Use `-- --mission` to capture an authored fast mission through the command/session
path, saving `test-results/mission.png`.

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

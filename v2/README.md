# Rewrite foundation

Open `v2/project.godot` in Godot 4.7.2. The original game remains in `v1/`.
The master design is [atd.md](../atd.md). Existing `game.gd`, `world.tscn`, and
`Assets/` are retained; the new entry is `scenes/prototype.tscn`.

This prototype has primitive meshes, a locked top-down orthographic
camera, movement, targeted combat, queued production, engineer blueprints, Mother/Womb construction,
a Lightless chyme loop, passive Scavenger spawning, Nest-loss escalation,
Veil with global stances, and the first
nacre mission loop. Briar mechanics, full faction AI, ore/gas
logistics and persistent progression remain pending. Initial reserves, costs, rates,
carrying limits, free mission repair and mission timers are prototype fixtures.

## Author and play

The demo is multiplayer only; there are no AI participants or AI fallbacks.
AI behavior is deferred until both factions have established player control interfaces.
Network matches require at least one Human player and exactly one Lightless player.
The main menu uses a vertical sidebar. **Play** offers Local sandbox and Multiplayer;
**Match setup** groups starting faction and seed away from the landing screen.
**Multiplayer** groups room controls, showing lobby participants after connecting and
folding advanced connection settings. **Content** contains the editor and its
**Project** menu (load, export and defaults); **How to play** groups controls and
faction objectives. Content validation runs before starting a match.
**Start local sandbox** creates both factions without AI. During play, use the HUD
selector to control Humans, Lightless, or both without restarting. Orders already
issued continue after switching. In both mode, selection and commands work across
both factions. Vision, Veil tiles, selected connections and sense overlays combine
all controlled participants, independent of selection. The HUD follows the first
selected controlled actor (or the starting faction when nothing is selected).
Ownership, resources and hostility stay separate; controlling both does not ally them.
Idle factions wait for player orders; passive production and player-issued Veil stances
still run normally.

- Left-click selects; Shift adds. Right-click moves or attacks. Point moves finish
  within one tile; right-clicking a friendly actor approaches its adjacent range.
- Select HQ/Nest, choose a product, and press **Produce selected type**.
- Select a spawner and right-click ground to set its rally point, or press
  **Set rally point** and left-click. Selected owned spawners show a gold rally
  flag and connection line. Rally orders also work for passive-only spawners.
- Humans: select an engineer and right-click your damaged extraction point to repair.
  Destroy the Nest, then right-click its revealed nacre remains to mine. Full cargo
  returns to your point, then mining resumes. **Start extraction** becomes available
  after the delivered threshold; you choose when to begin defending the countdown.
- Produce a Mother at the Nest, select a structure and press **Place structure**. Left-click a revealed empty tile. Right-click/Escape cancels targeting.
  **Cancel construction / refund** restores a growing Womb to its Mother.
- Scavengers collect chyme by damaging enemies. Right-click your Nest to deliver it,
  or press **Deliver chyme to nearest receiver**. Cargo becomes spendable only after delivery.
- WASD/arrows pan; the wheel zooms. The orthographic camera does not rotate.
- The HUD keeps reserves and objectives together. Selection reveals actor details
  and applicable production, construction, cargo, combat and connected Veil commands;
  group commands remain available for eligible members of mixed selections.
  HUD refreshes preserve control visibility, focus and open dropdowns while their
  availability stays unchanged. Extraction appears when ready. **View & overlays**, **Session details** (ticks,
  confirmation, rollback, hashes and event history), and **Controls** expand on demand.
- Ground tiles always show visibility: warm gold is illuminated (and perceived),
  cool blue is perceived but unlit, dim slate is remembered fog, and near-black is
  unexplored darkness. The HUD includes a color legend. Detection alone never
  clears ground fog. Veil is translucent so visibility remains readable beneath it.
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
choose `capsule`, `cylinder`, or a structure-only `footprint` shape, set
`visual.radius` (0.05–4 tile inner diameters), compose
capabilities, and add its ID to a factory's `produces` list. Implemented capabilities
are `move`, `weapon`, `perception`, `illumination`, `light_blocker`, `detection`, `factory`, `veil_source`,
`chyme_collector`, `chyme_receiver`, `chyme_source`, `metamorphosis`,
`mission_worker`, `extraction_point`, `builder`, and `passive_spawner`.
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

Actor meshes support `capsule`, `cylinder`, and `footprint`. Sizes, movement and
ranges use a tile's inner diameter (the spacing between adjacent tile centers).
`visual.radius: 0.5` gives the tile's inscribed circle. Capsule height is three
radii; cylinder height is two. Primitive bodies sit at the arithmetic centroid
of their footprint, including asymmetric and rotated footprints. Visual radius
only affects the art; mobile `collision_radius` controls gameplay clearance.
`footprint` meshes extrude the full union of occupied hexes using `visual.height`
in tile units, with no internal side faces. Walls use a pale surface and a
permanent dark rim to distinguish them from ground tiles without selection.
Selected footprint shapes show their gold boundary above the top surface.

A white line starts at each body mesh's local origin and extends forward beyond
its radius. Actors initially face northwest (negative r), turn toward movement/combat/work targets,
and retain their facing when idle or stopped. Facing is an integer axial direction
in checkpoint state, so rollback and different rendering frame rates show the same
orientation. Old presets using other shapes or omitting radius must be updated.

Times use ticks at configurable `tick_hz`; speed is tiles/second and ranges are tile
steps. Core positions use integer axial sub-tiles at 1/1024 tile with a reserved
elevation coordinate; the view maps them to Vector3 positions. The arena is flat. Structures and authored `settings.terrain` hexes obstruct
routes; terrain also blocks placement, Veil and light. Terrain uses low, filled
hex columns. Elevation transitions and generated terrain remain pending. Zero minimum
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
orders/production. Its survivors remain attackable.
The Lightless win after every Human participant is defeated;
the first Human to finish extraction wins for everyone. Defeat resolves before
countdown completion, so losing a point on the last tick prevents extraction.
Simultaneous successful extractions use deterministic roster order as a prototype tie rule.

Results, objective IDs, repairs, deposits, cargo, mine schedules, finite deposits,
discovery and countdowns are checkpoint state. Speculative results freeze gameplay
while input confirmation continues; late input can overturn an unconfirmed result.
The HUD announces the winner only after confirmation. The outcome records raw
extracted nacre; persistent progression and reward formulas remain unimplemented.
Older presets can omit `mission`, or set `enabled: false`, for the prior sandbox.
Workers require player orders to begin repair or mining; extraction requires an explicit start command.

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
the cargo. Move/stop/attack commands can interrupt delivery. Full collectors wait
for a player delivery order.
Cargo, source schedules and delivery orders are checkpoint state; economic notices
are emitted through confirmed events. Older presets can omit all chyme capabilities.
State version is 16 and network protocol is 22; older peers must update before joining.

These values and policies are prototype choices, not settled balance.

## Passive spawning

Stationary Lightless definitions can have `passive_spawner` with a mobile Lightless
`definition`, integer `interval_ticks`, and source-local `max_alive`.
The legacy `spawn_radius` field (1-4) remains accepted for preset compatibility;
rally-based adjacent emergence determines placement. The preset Nest generates a Scavenger every 200 work ticks, capped
at six living offspring; Scavenger Spawners use 100 work ticks and a cap of four.
These are configurable prototype rates and limits.

The first birth waits a full interval after the source appears or finishes Womb
construction. Passive births spend no chyme and do not enter the paid queue.
Paid units and starting units do not count toward a passive cap. Moving offspring
away does not free slots; death does. Timers pause at cap, then resume when a slot
opens. Dead sources stop producing; their surviving offspring remain in play.

Paid factories and passive spawners store a settable rally point, initially directly
south of their footprint (kept inside the arena at map edges). New units emerge
on an empty adjacent footprint tile with the shortest traversable hex route to
that point, using the product's collision radius and hard obstacles. One reverse
A* search ranks the exits, with stable axial tie breaking. Larger bodies use a
wider clearance ring. Reserved construction sites and living units prevent spawn
overlap. A sealed perimeter keeps production ready and retries without spending
RNG or resources; an unreachable rally uses the nearest available exit and lets
the move order report that it is blocked. Spawn choices no longer consume RNG.

Newborns begin moving to the saved rally point on the next tick, finishing within
one tile as with other point moves. Changing the source rally affects future
births. Their initial rally order takes priority over automatic Veil stance orders;
stances resume after arrival. Nest-loss bonuses still accelerate production.

Source timers, start ticks, offspring origin IDs and RNG are checkpoint state.
The inspector shows living offspring, remaining work, rate and cap/blocked status;
birth notices use confirmed events. The cap follows living offspring actor IDs,
including any authored transformations. Full faction strategy and species-specific
retreat/harassment behavior remain pending.

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

## Human engineer construction

Select an engineer, choose **Defense Turret**, press **Place structure**, then click
revealed empty ground. Placement pays 35 sandbox credits immediately and creates
an inert, attackable blueprint. Its one assigned engineer travels to an adjacent
work position and supplies 100 work ticks. Costs and times are prototype fixtures.
The turret automatically targets the nearest perceived or detected hostile in range
every 10 ticks; direct attack orders take priority. Power and ammunition are deferred.

Move/stop interrupts work while preserving the blueprint. Select an engineer and
right-click an owned blueprint to resume or reassign it. **Cancel construction /
refund** on the blueprint or its assigned engineer returns the full paid cost,
even after partial work or damage. Destruction loses the investment. Losing the
engineer leaves the blueprint available for another engineer. Completion waits
for occupants to leave its tile and preserves its health fraction.

The `builder` capability specifies `blueprint` (an inert Human definition),
`structures` (stationary Human definitions with `construction_ticks`) and
`work_range` (1-4 tiles). HQ and extraction points cannot be rebuilt. Sites occupy
their authored footprints. Work approaches a reachable perimeter position with
the engineer's body clearance. If no approach exists, construction cancels with
a full refund. Checkpoints contain assignment, investment and remaining work.

## Mother/Womb construction

The Nest can produce Mothers. `metamorphosis` lists a builder's `womb` definition
and permitted `structures`. Each target has integer `construction_ticks`; the Womb
is a Lightless definition with no active capabilities. The preset offers a
Scavenger Spawner (production, delivery and Veil) and an experimental Maw
(passive income and delivery). Costs, health and times are configurable fixtures.

Perception and illumination permanently reveal tile centers for their owner;
detection does not. Revelation is checkpoint state and permits construction after
senses leave. The view's green/red hex preview checks known information only;
the core revalidates actual occupancy. All footprint cells must fit the arena and be revealed, clear and unreserved.

A build order reserves a revealed empty tile and moves its Mother there. It pays
the target's chyme cost only on arrival, then transforms the Mother into a vulnerable
Womb at the same actor ID. The Womb cannot move, produce, receive deliveries or
grow Veil. It matures after the target's duration; completion waits for units
intersecting the finished collision body to leave. The finished structure activates its capabilities,
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
rebuilt on restore. Movement, spawning and work use the shared footprint geometry. Mother AI,
elevation transitions and Briar defenses remain pending.

## Footprints, collision and navigation

Stationary definitions can author a connected set of relative axial offsets.
It must include `[0, 0]`, have no duplicates and contain at most 64 cells within
8 hexes of the anchor. Missing footprints default to `[[0, 0]]`. HQ and Nest use
seven cells; units use circular bodies rather than footprints. For example:

```json
{
  "footprint": [[0, 0], [1, 0], [2, 0]],
  "collision_shape": "footprint",
  "visual": {"shape": "footprint", "height": 0.6, "radius": 0.5, "color": "96a0ab"}
}
```

Press **R** while placing to rotate the footprint through six axial orientations.
Placement and selection show the full boundary; every occupied tile is pickable.
Blueprints and travelling Mothers reserve every future footprint cell. Blueprints
and growing Wombs render the target's full rotated footprint at its centroid,
using their own construction colors and heights. Blueprints
remain walkable until completion; completion waits until entire circular unit
bodies clear the final collision shape. Wombs obstruct movement with the target
collision shape while growing.

Build footprints determine placement, reservation, picking and interaction tile
centers. Movement uses independent `collision_shape`: `footprint` fills every
occupied hex (walls and terrain), while `circle` uses `collision_radius` in tile
units at the rotated footprint centroid. For example, HQ uses a seven-tile build
footprint with `"collision_shape": "circle", "collision_radius": 1`. Units can
walk through unused space within that footprint when their bodies fit. Circle
collision requires an explicit radius; omitted structure shapes retain the legacy
footprint default. Rendering remains independent: changing `visual` never changes
collision. Swept clearance, A*, smoothing, local steering and emergence all use
these same collision obstacles. Spawn exits exclude only the source's own body.

Mobile definitions use `collision_radius` in tile units (0.05-4, default 0.2).
Fixed-point A* and swept circle/hex clearance handle narrow gaps and corners.
Routes are smoothed into long, arbitrary-angle segments by skipping to the
farthest waypoint the entire collision circle can reach directly. Remaining
waypoints are skipped as corners clear during movement. Open-ground movement
goes directly to the exact clicked position; units do not stop at every hex.
Completed structures block movement unless `blocks_movement` is false. Light
blocking remains independent, so HQ obstructs movement without blocking light.
`settings.terrain` optionally lists solid axial hexes, such as `[[0, 0], [0, 1]]`.
These cells block movement, construction, light and Veil. Starting bases need
clear ground. Terrain outside explored ground stays hidden.

Orders route around obstacles, approaching targets along reachable perimeter
positions for building, combat and delivery. Building, repair and delivery radii
measure from the unit center to the center of the nearest occupied footprint tile,
not to a hex edge or the structure centroid. The engineer's authored one-tile work radius
excludes centers two tiles away. Larger workers can configure a larger work radius
to accommodate their collision radius. Navigation uses the same interaction metric;
physical clearance and weapon range retain their separate geometric rules. Blocked move orders stop; unreachable
construction refunds its blueprint. Production waits for clear emergence space
near the source; passive spawn radius is measured from the source footprint.
Routes are actor checkpoint state; derived obstacle/clearance caches rebuild on
restore and invalidate when structures change. Stable A* ties use cost, remaining
hex distance and axial coordinates. Selection and preview never change core state.

Friendly mobile bodies use soft local avoidance: they prefer separated routes,
but can overlap or pass through one another after bounded yielding in a tight
passage. Idle overlapping allies gently settle apart. Point orders finish within
one tile and keep that arrival range during settling. An `approach` order finishes
adjacent to a unit or the nearest structure footprint tile center; larger bodies
increase that range. Building, delivery and weapons retain their own ranges.
Hostile mobile bodies enforce hard swept-circle contact during movement and
spawning. Different participant ownership is hostile, including in both-control
sandbox mode. An initially overlapping hostile pair can only move outward.

Global A* and route smoothing use terrain and immobile structure collision only.
Mobile units never invalidate the route graph or enter its clearance cache.
Groups can join a compatible ally's static route. Nearby friendly and hostile
units contribute predictive local repulsion; hard-contact sliding keeps a stable passing side. Friendlies
can yield through one another, while swept hostile contact remains hard. Spatial
buckets bound soft neighbor sampling and only nearby hostile bodies need contact
checks. Every movement step still checks immobile geometry and all hostile bodies
within its swept reach. Steering uses one analytical passing prediction per
neighbor instead of scoring a dozen candidate velocities against every body.

Static clearance is shared by radius. At most six sampled neighbors influence
moving-unit repulsion; soft queries inspect at most 24 candidates per ownership query.
Idle settling considers every body a step could touch and only reduces their
combined overlap pressure, preventing cycles between changing neighbor subsets.
Separation forces update each tick without rotating a shared heading into repeated
detours. Soft pressure retains forward progress, and exactly coincident allies get
opposite separation forces. Movement reads typed body positions, radii and previous
velocities from a derived crowd index, updated after each move. Route and steering
decisions are checkpoint state; derived spatial,
visibility and exploration caches rebuild on restore. Elevation/cliff transitions,
vehicle turning constraints and formations remain future work.

## Illumination

Illumination flood-fills hex tiles from each emitter's containing tile. `radius`
is the maximum path length in tile steps (fractional values allow only complete
steps). Each neighbor costs one step, so light can travel around corners when
the detour fits the budget. The arena boundary stops propagation. A reached tile
is illuminated in full, including units on it.

Stationary structures can declare `light_blocker: {}`. A blocking tile receives
light but never forwards it. Emitters can spread outward from their own tile.
Walls are the only shipped Human light blockers; HQ, turrets and blueprints do
not block light. Engineers can build a Wall for 5 credits and 30 work ticks;
these are prototype costs. Walls block movement and light across their entire footprint. Blocks affect sources of every faction.

Overlapping sources combine for their owner. The same field drives full
visibility, permanent discovery, Veil growth prevention/damage and the tile
illumination overlay. Perception and detection retain their existing radial
rules and can reveal or detect units in unlit tiles independently. Light fields
are derived caches, rebuilt after restore and invalidated by source/blocker
changes; they never enter checkpoints or mutate gameplay during view queries.

## Veil slice

The Nest has `veil_source` by default. Add this capability to other stationary
Lightless definitions with integer `radius`, `growth_interval_ticks`, and
`growth_tiles`. Growth begins under its source, then randomly picks eligible
frontier hexes within its radius. Every pick touches membrane already claimed by
that source; new tiles extend the frontier immediately within the same pulse.
Candidates are sorted before each seeded RNG draw, so checkpoints and rollback
reproduce growth exactly. An empty frontier consumes no RNG. Overlapping friendly
Veil can be claimed for support using the same growth budget. Units of any owner
allow Veil to grow beneath them, even while stationary. Structures (including
Wombs and blueprints) block new growth, except on a source's own tile. The current
capability model identifies structures by the absence of `move`. Illumination
blocks growth regardless of occupancy. Authored `settings.terrain` cells also stop growth. A source can maintain
existing friendly membrane and spread beneath its own footprint.
Communication does not allow growth to jump gaps.

`settings.veil` configures tile HP, illumination damage/tick, unsupported decay/tick,
alert cooldown and last-known-threat memory duration. Light blocks new growth and
damages existing membrane; perception does neither. Existing damaged Veil does not
passively heal. Destroying a source removes its support. Shared areas maintained
by surviving sources remain; only unsupported tissue decays.

Every living Veil tile provides full perception to its owning Lightless participant,
in addition to unit/structure senses. This applies across disconnected patches and
without nearby units or network connections. The whole covered hex is perceived;
adjacent uncovered hexes receive no extra vision. Enemies on it are fully visible
and eligible for ordinary weapon targeting, subject to range. Veil perception also
reveals ground and discovers nacre remains. It never illuminates or damages Veil.
Unsupported tissue keeps perceiving until removed; revealed ground stays remembered
after current vision ends. The perception overlay includes owned Veil tile outlines.

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
| Player roster and faction limits | `core/match_rules.gd` |
| Ticks, state, commands, restore | `core/simulation.gd` |
| Veil growth, support, alerts and global stance | `core/veil.gd`, `core/hex_cells.gd` |
| Chyme collection, delivery and passive generation | `core/chyme.gd` |
| Human blueprints, engineer work and refunds | `core/engineering.gd` |
| Footprint cells, centroids and circle/hex geometry | `core/geometry.gd` |
| Deterministic routing and clearance caches | `core/navigation.gd` |
| Soft friendly avoidance and idle settling | `core/steering.gd` |
| Typed local movement bodies and spatial queries | `core/crowd.gd` |
| Compiled integer movement and canonical state-byte writer | `native/movement_kernel.hpp`, `native/extension.cpp`, [native build/ABI](native/README.md) |
| Mother/Womb lifecycle and site validation | `core/construction.gd` |
| Flood-filled light field and blockers | `core/illumination.gd` |
| Remembered revealed ground | `core/exploration.gd` |
| Nest death grant and permanent development rates | `core/nest_escalation.gd` |
| Passive birth timers and source caps | `core/spawning.gd` |
| Rally state, emergence ranking and newborn orders | `core/rally.gd` |
| Nacre, extraction, Human defeat and match outcomes | `core/mission.gd` |
| Canonical hashing | `core/canonical.gd` |
| Input history, rollback, confirmation | `net/rollback_session.gd` |
| Lobby, input relay, desync checks | `net/match_session.gd` |
| Signaling and RTC connections | `net/coordinator_transport.gd` |
| Extruded footprint shapes and boundaries | `view/footprint_mesh.gd` |
| Configurator, meshes, camera, HUD | `view/prototype.gd` |
| Persistent illumination, perception and fog tile colors | `view/visibility_ground.gd` |
| Read-only membrane and senses overlays | `view/veil_overlay.gd` |

Keep core state integer-based and free of nodes, rendering, wall time, native
physics, and unseeded randomness. Definitions are copied at initialization. Every
mutable gameplay value belongs in checkpoints; derived caches must be rebuilt
consistently. AI is deferred until both faction control interfaces are established.
Camera, sandbox control selection and actor selection remain outside the core.

## Validate and export

Build the compiled integer accelerator for the local editor and Web:

```powershell
python tools/build-native-movement.py --godot <GodotExecutable> --web
```

The helper generates the matching Godot C interface and builds the C++17 sources
in `native/`. On Windows it installs pinned Zig 0.14.1 in a temporary tool cache;
Linux/macOS use the system C++ compiler. Web builds install pinned Emscripten
4.0.20. Generated headers, libraries and the extension descriptor are ignored.
Libraries use content-addressed filenames so an open editor cannot lock a rebuild;
restart the editor to load a changed native ABI. Without the generated extension,
the same simulation runs through its GDScript reference implementation.

Run from the repository root, substituting the local engine path:

```powershell
python tools/test-rewrite.py --godot <GodotExecutable> --network --require-native
```

The rewrite runner imports first and rejects script errors even on exit zero.
`--require-native` also verifies that compiled movement is actually loaded. Native
and reference implementations are compared at every tick through collisions,
large bodies, terrain routes, production, death and JSON restoration. Native state
serialization preserves the existing sorted JSON bytes and SHA-256 hashes;
unsupported Variant types use Godot's serializer.
Import/Web export use recovery mode to avoid native-extension DLL reload locks
when the project is already open in a Windows editor; actual tests still load WebRTC.
`--network` creates a temporary room on the deployed coordinator and tests two
actual RTC peers, deliberately late input, rollback, and confirmed hash equality.
Without it, validation is offline. Logs are ignored in `v2/test-results/`.

The foundation suite covers content validation and authored units, faction limits,
ownership, production, RNG restoration, JSON checkpoints, turret-only sensor
targeting, late input, confirmed events, and bounded history. Its shared
`tests/veil_suite.gd` also checks seeded random frontiers, adjacency, pulse budgets,
RNG restoration, stable candidate ordering, growth beneath friendly/hostile units,
structure blocking, growth/illumination, global alerts, friendly and
hostile entry, stance adoption/response, overlap support, source decay, weapon
clearing, and rollback after a late intrusion. View tests check overlay isolation.
`tests/chyme_suite.gd` covers armor/overkill/capacity, delivery ownership and loss of
receivers, passive schedules, idle cargo retention, production spending, JSON restore,
late collection input and exactly-once confirmed economic events. View tests also
check cargo/reserve inspection and delivery through the command queue.
`tests/geometry_suite.gd` covers footprint validation/rotation, whole-site placement,
size-dependent gaps, swept corner clearance, wall detours, terrain changes, multi-tile
construction/spawning, JSON route restoration and late-command rollback. View tests
cover centroids, full-shape picking, rotation previews and hidden terrain.
`tests/engineering_suite.gd` covers blueprint payment, reservations, interruption,
reassignment, refunds, destruction, completion, turret combat, JSON restore and
late-input rollback with exactly-once confirmations. View tests cover placement,
inspection, resumption and cancellation through session commands.
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
`tests/rally_suite.gd` covers rally commands, paid/passive emergence, blocked exits,
path distance, arrival, JSON restore and late-input rollback.
`tests/spawning_suite.gd` covers source caps, casualty replacement, blocked/reserved
tiles, arena edges, paid queues, Womb timers, Nest-loss speed and rollback after
a delayed casualty. Passive spawn inspection remains read-only.
`tests/illumination_suite.gd` checks tile coverage, wall shadows, corner detours,
source ownership, source/blocker removal, discovery, Veil effects, JSON restore
and late wall-construction rollback. View tests verify tile overlay agreement
and read-only queries.
`tests/veil_perception_suite.gd` checks whole-tile perception, ownership, additive
senses, ordinary targeting, decay, immediate discovery and late-input replay.

For rendered menu review, run `res://tests/preview.gd` with no extra arguments for
Play, or `-- --multiplayer`, `-- --setup`, `-- --content`, or `-- --guide` for a section.
Add `--small` to capture a 960 by 640 window. PNGs are saved under `test-results/`.

For diagonal route review, use `res://tests/preview.gd -- --paths` for
`test-results/paths.png`, showing long swept-clearance shortcuts around a wall.

For unselected wall contrast across illumination, perception and fog, use
`res://tests/preview.gd -- --walls` for `test-results/walls.png`.

For footprint shapes, centroids, routing and terrain review, use
`res://tests/preview.gd -- --geometry` for `test-results/geometry.png`.

For persistent visibility/fog review, use `res://tests/preview.gd -- --visibility`
for illuminated, perceived, remembered and unexplored ground in
`test-results/visibility.png`. Add `--small` for the compact viewport.

For light propagation review, use `res://tests/preview.gd -- --illumination`
for a wall barrier and its lit/shadowed tiles in `test-results/illumination.png`.

For Human construction review, use `res://tests/preview.gd -- --engineering`
(add `--blueprint` for work in progress). Captures are saved as
`test-results/engineering.png` or `test-results/engineering-blueprint.png`.

For rendered construction review, run `res://tests/preview.gd` with `-- --construction`
(add `--womb` for growth progress). It drives production and placement through the
session, saving `test-results/construction.png` or `test-results/womb.png`.
Add `--nest-loss` with `--womb` for `test-results/nest-loss.png`.
Use `-- --mission` to capture an authored fast mission through the command/session
path, saving `test-results/mission.png`.
Use `-- --spawning` for a fast source-at-cap preview in `test-results/spawning.png`.

With matching Web export templates installed, including the single-threaded
GDExtension (`web_dlink_nothreads_*`) templates:

```powershell
pwsh -File tools/build-web.ps1 -GodotExecutable <GodotExecutable> -ProjectDirectory v2
python -m http.server 8000 --directory build/rewrite-web
```

The v2 export helper builds the native host/Web accelerator before exporting.
CI also validates the compiled v2 core; it does not run v1 regression suites.

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

Run `res://tests/benchmark_movement.gd` headlessly for deterministic crowded movement
with 16/32/64 movers and the same number of hostile bodies. It reports the first
ten ticks, the next fifty, overall p95 and peak for full ticks, including retained
checkpoints and the scheduled 20-tick state hash. Step, copy and hash costs are
also reported separately; elapsed time never enters gameplay. `-- --opposing --large`
runs only the 64-per-side stress case. The CPU target is below 4 ms per full tick,
including hash boundaries and command ticks; this remains an optimization target,
not a verified performance guarantee. Add `--verify` to check hostile separation
on every tick and replay from a JSON checkpoint, outside timed intervals.
`--require-native` rejects a missing accelerator; `--reference` selects GDScript
for comparison. Reports identify backend, platform and debug/release build.
The headless wrapper and Web self-test both call `tests/movement_benchmark.gd`;
add `--benchmark` to the browser harness command to save release-Web measurements
in `test-results/movement-browser.json`. Both modes measure the same complete ticks.
Timings are diagnostics, not guarantees; dense crowd work remains separate from
static route searches and is reported explicitly by the opposing-group probe.

Measured on the development workstation on 2026-11-02 with the compiled backend,
64 movers per side (134 actors), retained checkpoints and scheduled hashes:

| Build | Mean tick | p95 | Peak |
| --- | ---: | ---: | ---: |
| Windows editor/headless (debug) | 9.465 ms | 12.766 ms | 19.232 ms |
| Web export (release, headless Edge) | 23.675 ms | 30.400 ms | 60.100 ms |

Both probes passed hostile separation and JSON restore/replay verification with
the same final hash. These results do **not** meet the 4 ms target. Static routing
peaked at one search and nine expansions per tick; remaining work includes the
GDScript actor-update path, checkpoint copies and state serialization. Re-measure
on the next workstation before comparing timings across changes.

Run `res://tests/benchmark_frames.gd` with a display to measure the 1280x800 view
in a sandbox warmed for 600 ticks, with both factions visible. It reports paused
and running script CPU mean/p95, visibility/overlay/HUD costs, wall-frame p95,
viewport CPU/GPU timings and draw calls. VSync is disabled only for this probe;
script timing alone is not total frame time. Results depend on driver, debug
build overhead and competing workloads.

Presentation updates follow simulation ticks, rollback, selection and overlay
changes. Ground perception uses prepared source/light data and direct tile classification; unchanged visibility keeps
its mesh. Ground geometry is cached separately from packed color blocks and
uploaded in batches. Veil and rally/order geometry are retained while their inputs remain
unchanged. Match sessions calculate hashes at the existing 20-tick exchange
boundaries, retaining per-tick checkpoints/events. Standalone rollback sessions
default to per-tick hashes. HUD diagnostics display the latest calculated boundary
without rehashing state.

`benchmark_movement.gd -- --opposing` sends both interleaved armies toward one
point, exercising moving hostile obstacles and congestion; default mode leaves
the opposing army stationary. It also reports maximum searches and node expansions
per tick. `benchmark_simulation.gd` measures warmed gameplay, checkpoint copying
and state hashing separately. State uses exact native sorted JSON hashing;
checkpoint restoration normalizes JSON scalars once. `tests/cpu_suite.gd` checks
canonical hash equivalence, integer-root boundaries, exploration against exhaustive
rasterization, shared static routes, hostile separation and restore/replay.

Exploration shares shrinking unknown-tile envelopes between observers of the same
owner/radius in a hex; fully discovered envelopes require no further tile scans.
Radius stencils and immutable tile-key tables are prepared once; rollback retains
only those static tables and discards all observer/discovery cache entries.
Movement shares ordered lists of live spatial buckets between nearby queries,
invalidating them when a previously empty bucket gains a body. It uses integer-vector spatial bucket keys,
scalar swept-circle contact math and cached static clearance certificates covering
every steering direction in a tile; hostile contacts still run every movement tick.
Illumination validates once at tick entry and
invalidates on source/blocker movement, creation, death and transformation. Veil
maintenance avoids per-cell filter allocations and sorts only tissue needing damage.
State-dependent derived caches are discarded on restore. Integer roots use a native
estimate corrected by exact integer division, including at int64 square boundaries.

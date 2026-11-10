# Developer guide

The active project is `v3/`. Run the commands in this guide from that directory; open `v3/project.godot` in the editor.

## Run and tune

Use the Godot version pinned in `.godot-version`. `npm test` runs actual Godot simulation and interface checks. `npm run export:web` builds the browser game; `npm run serve` serves it at localhost:8080. `npm run test:browser` exercises the exported game and the custom coordinator. Export before browser tests whenever game scripts or configuration change.

Edit `config/prototype.json` for gameplay, camera, and presentation values; edit `config/networking.json` for transport policy. Run `npm run config:check` for native validation with JSON-path errors. Run `npm run config:reference` to update the [searchable default-value index](config-reference.md). Restart the game or re-export the browser build to apply changes. Configuration is loaded once, not hot-reloaded mid-match.

Use `npm run profile:cpu -- --active` for bounded CPU timings, or append `--frames --rendered` to exercise the native game callbacks. See [performance measurements and remaining work](performance.md). Normal browser sessions skip diagnostic enumeration; use `?diagnostics=1` when inspecting the browser bridge.

The presence of a definition does not implement a feature. Check [implementation status](implementation-status.md). In particular, full mining expeditions and the Lightless economy/coordination are still pending.

## Code map

| Concern | Main location | Contract |
| --- | --- | --- |
| Config loading, validation, hash, test patches | `scripts/settings.gd`, `ConfigRules` | `validate` returns errors, `merged` returns a deep copy, gameplay hash omits camera/metadata/presentation. |
| Entities, commands, simulation ordering | `scripts/world_state.gd` | Host-owned mutable state; no scene nodes, input, audio, or wall-clock calls. |
| Single-player contracts | `WorldState.Missions`, `config/prototype.json` `missions.*` | Start through `command`; seeded scenario setup, actual-delivery counters, simulation-owned completion. See [missions](missions.md). |
| Last-seen enemy structures | `WorldState.structure_memory`, `observed_entity`, `observed_structures` | Observer records remain separate from simulation entities and collision. UI must use observed views. See [fog memory](fog-memory.md). |
| Continuous routes and body clearance | `WorldState._route_path`, `MovementGraph`, `RouteNavigation` | Coarse hex topology, actual-position starts, clearance-aware shortcuts, swept collision and full movement budgets. See [navigation](navigation.md). |
| Lightless probes, obstruction targets, attack/retreat paths | `WorldState._probe_step`, `LightlessTactics` | Uses known Anchors and personal vision; full routes, simulation-time retries, preserved attack objectives. See [Lightless AI](lightless-ai.md). |
| Eligibility, concealment, armor and damage | `WorldState.TargetRules` | Query functions shared by simulation, snapshots, rendering and inspector. |
| Feedback events and weapon profiles | `WorldState.emit_feedback`, `feedback_for`, `FeedbackRules` | Bounded, audience-filtered events; renderer/audio/HUD consume independent serial cursors. |
| Radar contacts | `WorldState.RadarSystem` | Mutates `detected[owner]`, containing occupied tile coordinates only. |
| Burrow transitions and alternate weapons | `WorldState.BurrowRules` | Unit-local simulation timer; completion updates buried state and weapon together. |
| Automatic doors | `WorldState.GateRules` | Passage requests come from routes; manual state and locks remain separate. |
| Input and command panels | `scripts/main.gd` | Construct orders; route them through `_issue`, including multiplayer authority checks. |
| Models, movement interpolation, lights | `scripts/world_renderer.gd`, `scene_art.gd` | Read simulation state. Presentation must not move authoritative units or deal damage. |
| Tactical contacts and coverage | `scripts/tactical_overlay.gd` | Use `unknown_contacts`; never display a concealed enemy's identity/count/health. |
| Current tasks and blockers | `WorldState.activity`, `ActivityRules`, `CommandSkin.StatusPanel` | Read-only queries; owned snapshot activity survives route stripping. Query only owned selection for task markers. |
| Inspector and command art | `command_skin.gd`, `command_card.gd`, `unit_portrait.gd` | Display the same effective stats used by simulation. |
| Native/browser transport | `network_session.gd` | Transport orders and filtered snapshots; clients do not run authoritative simulation. |

The rule classes are currently nested in existing scripts to avoid creating additional `.gd` files while the local file-creation/editor termination issue is investigated. They have explicit state/query boundaries and can later be extracted without changing their callers' behavior. They are ordinary runtime classes, with no `@tool` annotations. The command-line `tools/` folder is excluded from editor scanning.

## Simulation contracts

IDs are stable integers allocated by `add_unit` / `add_structure`. Owners are human player indices, with `-1` reserved for the CPU Lightless. Positions are continuous `Vector2` values in the ground plane; construction uses axial `Vector2i` hex cells. Use `HexGrid.cell/world` rather than duplicating conversion formulas.

Unit dictionaries own orders, routes, cargo, stance, crew and transition state. Structure dictionaries own their footprint, power state, buffers and queues. Definition values live in configuration; instances hold changing state. Optional capabilities use explicit definition fields, such as `driverSeats`, `detectionRangeTiles`, or `buriedWeapon`.

`command(owner, order)` is the authority boundary. Validate ownership, payload shape, eligibility, costs and targets before mutation. The interface and test bridge use this same path. Background systems may call internal helpers after applying equivalent validation; they must not pretend that a player issued a new order.

Each simulation step advances gates, power and sensor contacts, production, units/occupants, separation/healing, defenses and extraction. Vision/Gloom refresh uses `targeting.refreshIntervalTicks`. Gate changes and crew unloading refresh relevant visibility immediately. Simulation time drives progress and damage; paused time does not advance these systems. Presentation time may animate interfaces independently.

Normal and dark navigation graphs are shared. Friendly unlocked gate cells are temporarily admitted during route calculation, then restored before another route is calculated. This assumes the current single-threaded simulation; do not parallelize route requests without replacing that transaction.

## Extend a mechanic

1. Put its numeric tuning and capability flags in JSON, using simulation seconds, tile distances and whole inventory units. Regenerate the reference and add validation for new constraints.
2. Add state through entity constructors or explicit capability initialization. Keep derived rules in query functions rather than caching contradictory copies on every entity.
3. Add commands through `WorldState.command`; expose usable commands in `_refresh_actions` and right-click dispatch. Include changing state in the action signature when controls need to refresh.
4. Integrate behavior into the appropriate simulation phase. Use the world's seeded random generator for gameplay randomness. Do not use UI frame rate, `Time`, or global random functions for simulation decisions.
5. Route combat, rendering and snapshot eligibility through `TargetRules`. Example: a new unit with Shade-like concealment can use a `targeting.unitRules` entry with `requiresIllumination` and `radarInvisible`; it does not need three separate hardcoded checks.
6. Serialize any new client-visible state in `snapshot/apply_snapshot`. Routes remain host-side. Convert vectors into JSON arrays explicitly, and assume numeric IDs may arrive as floating-point JSON numbers.
7. Add behavioral checks to `tests/simulation.gd`, controls to `tests/interface.gd`, and browser checks for real input/network flows. Favor conservation, ownership, interruption and failure recovery over tests that simply repeat an implementation formula.
8. Update implementation status and controls. A unit definition alone does not add factory buttons, art, AI production or a complete player workflow.

For a new attack mechanism, extend resolution deliberately: the current mechanisms are guaranteed unit targets and cones. Obstruction is checked before firing. Buried targets reject area attacks. The recursive attack system described in the design is not yet implemented.

See [combat and work feedback](feedback.md) for effect profiles, event payloads, privacy and playback budgets. Emit feedback when an action actually succeeds, rather than inferring it from a rendered animation.

## Configuration validation limits

Current validation checks required top-level sections, finite/nonnegative values (allowing signed audio dB), positive key timers, whole inventory/capacity values, unit health, vehicle fields, weapon references/mechanisms and kit sources. It is not a complete JSON Schema, balance validator, or guarantee that every configured pending system is playable. Add explicit checks when introducing new behavior, especially nested object shapes and cross-field constraints.

## Visibility and defense behavior

Radar detects enemy occupied tiles through walls/cliffs without revealing terrain or identity. Powered Radars and driven Scouts supply it; Shades do not create contacts. Turrets may use contacts in darkness, subject to range/obstruction. Infantry require vision. Buried targets additionally require detection and a unit-target weapon. Shades require both vision and illumination; illumination can come from another faction without granting vision. Area damage can hit concealed Shades but not buried targets.

Ramparts add one fixed armor layer to friendly structures in range. Overlaps do not sum. Enabled, built and powered are required. Inspector armor includes the shield bonus. Gates retain separate open/locked/manual/automatic states; they open automatically only for friendly routes, and automatically opened gates close after traffic clears.

The CPU Lightless controller still has simplified discovery and coordination. Wombs, Glands, and initial Father recruitment are implemented; human controls and Medusa network stance propagation remain incomplete. Human-side concealment filtering does not imply complete CPU knowledge.

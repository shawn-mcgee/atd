# Integer CPU accelerator

`movement_kernel.hpp` implements local mobile-body queries, predictive separation,
complete hostile swept-circle contact and idle overlap pressure. All positions,
velocities, radii and calculations use integer axial coordinates. Native square
roots are estimates corrected to the exact integer floor. Global routing remains
in the headless GDScript core. `static_world.hpp` mirrors its exact circle/hex
clearance, integer cube rounding and map-edge checks for compiled execution.
When a cached clearance disk encloses every possible local step, the adapter
also integrates movement and settles idle overlaps in one call. Nearby static
obstacles use the general per-step geometry checks. Hostile contact remains hard
in both paths, and position/velocity/facing arrays are replaced rather than edited.

`exploration_kernel.hpp` rasterizes exact integer perception circles against map
tile centers. Per-owner discovery bitsets suppress repeated writes; illumination
and Veil discoveries are still applied by the core. These caches record only
monotonic discovery between restores and are rebuilt with each new backend.

`crowd_adapter.hpp` builds the mobile-body index directly from actors and current
definitions, preserving actor order and previous-tick velocities. Definition
rules are local to each rebuild so content changes are observed. GDScript Body
wrappers are created only for queries that need them and last until the next
rebuild; movement patches both the native index and any existing wrappers.
Idle settling runs as one ordered native pass with full static and hostile
clearance. It updates the body index between actors, then the core patches
derived light/enemy caches before end-of-tick gameplay continues.
Contiguous independent point orders (and no-op idle actors) run in ordered
batches too. Batches stop before A*, production, construction, passive schedules
or due automatic targeting. They update the native body index immediately;
existing GDScript body/enemy snapshots are synchronized at the batch boundary,
and moving light sources invalidate the light field before the next handler.

`extension.cpp` is a small Godot C-ABI adapter with no godot-cpp dependency. It
registers a `RefCounted` utility, not scene nodes or native physics. Its legacy
`state_bytes` diagnostic writes sorted JSON UTF-8 bytes. ASCII string/name keys,
integers, booleans, strings, arrays, dictionaries and null are accelerated; other
values return an empty buffer. Interned names
and ordinary string keys sort together by text. Serialization does not change
state. Protocol 23 uses the compact canonical encoder in `state_codec.hpp` for
rollback snapshots and hashing; see [the ATD1 specification](STATE_CODEC.md).
`state_reader.hpp` decodes the same format into fresh Godot containers, validating
limits and UTF-8 before construction. The reference decoder remains an independent
oracle and fallback when no accelerator is loaded.
An immutable key-text cache avoids repeated UTF-8 conversion. Variant equality
checks hash collisions. Small recurring keysets reuse sorted keys only after
dictionary size and `has_all` prove an exact match; values are always read live.
The keyset cache holds at most four schemas per size up to 64 entries. Retained
key-text entries are capped between serialization calls.

Build from the repository root with `python tools/build-native-movement.py --godot <path>
--web`. The matching Godot executable generates interface headers and builtin
method hashes. The builder publishes complete, content-addressed libraries and
the runtime descriptor atomically; all generated output stays out of Git.

ABI 15 accepts low-level frame records in a `PackedInt64Array`, seven integers per living
mobile body: `id, owner, radius, q, r, previous_vq, previous_vr`. IDs are unique,
radii positive, and coordinates/speeds follow the core's validated map/content
limits. Movement updates those bodies sequentially in actor order. Small per-unit
calls use integer/Vector2i arguments without temporary packed arrays. `advance`
and `settle` update a validated mobile actor dictionary only after the caller has
certified static clearance. `explore` receives the revealed-owner dictionaries,
four-integer observer records (`owner, q, r, perception_radius`) and map radius.
Normal discovery uses `explore_actors` to read mobile observers directly and
returns stationary observers for the shared GDScript footprint-center calculation.
Definitions are reread each call. Bounded per-owner/cell/radius envelopes discard
already discovered candidates between restores, including discoveries made by
other observers. Restores replace the kernel and all discovery envelopes.
`world` accepts packed static shapes (`hex_count, q, r, ..., circle_count, q, r,
radius, ...`), map radius and the existing geometry hash. It returns a revision.
`static_clear` checks that revision before querying geometry; retained older
fields fall back to their original GDScript geometry. `point_move` combines
progress tracking, direct-route reuse, integration, static/hostile contact and
arrival. It declines without mutation when its revision is stale or A* is needed.
Mobile bodies never enter the static world or the global search graph. Geometry
oracle tests compare the compiled path with GDScript using independent fields.
Each restore rebuilds derived native bodies and discovery caches;
`Simulation.accelerated = false` selects the
reference implementation. Tests compare complete state hashes across both paths.
Normal simulation uses `prepare_actors(actors, definitions, previous_velocities)`
with integer actor IDs in the previous-velocity dictionary. `begin_tick(actors)`
captures those arrays and replaces each actor's velocity with an independent zero
array. Capture happens after commands and before actor updates, including
actors that will be removed at the end of the tick. Both native and reference
movement read the same integer-keyed previous-velocity dictionary.
Queries use lazy `body_info(id)` wrappers. `owner_ids()` returns sorted owners. The
`settle_actors` pass accepts actors, defeated owner IDs, tick frequency and static
world revision; it declines stale geometry before making changes. `state_unpack`
returns a dictionary or null for invalid bytes. None of these derived objects
enter simulation checkpoints. The wire protocol remains 23.
`point_orders` receives the actor array, starting index, defeated owners, tick,
frequency, static revision and a derived-cache synchronization flag. Its returned
count advances the general loop without reordering actors or skipping handlers.

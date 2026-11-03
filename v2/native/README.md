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

`extension.cpp` is a small Godot C-ABI adapter with no godot-cpp dependency. It
registers a `RefCounted` utility, not scene nodes or native physics. Its legacy
`state_bytes` diagnostic writes sorted JSON UTF-8 bytes. ASCII string/name keys,
integers, booleans, strings, arrays, dictionaries and null are accelerated; other
values return an empty buffer. Interned names
and ordinary string keys sort together by text. Serialization does not change
state. Protocol 23 uses the compact canonical encoder in `state_codec.hpp` for
rollback snapshots and hashing; see [the ATD1 specification](STATE_CODEC.md).
An immutable key-text cache avoids repeated UTF-8 conversion. Variant equality
checks hash collisions. Small recurring keysets reuse sorted keys only after
dictionary size and `has_all` prove an exact match; values are always read live.
The keyset cache holds at most four schemas per size up to 64 entries. Retained
key-text entries are capped between serialization calls.

Build from the repository root with `python tools/build-native-movement.py --godot <path>
--web`. The matching Godot executable generates interface headers and builtin
method hashes. The builder publishes complete, content-addressed libraries and
the runtime descriptor atomically; all generated output stays out of Git.

ABI 9 accepts frame records in a `PackedInt64Array`, seven integers per living
mobile body: `id, owner, radius, q, r, previous_vq, previous_vr`. IDs are unique,
radii positive, and coordinates/speeds follow the core's validated map/content
limits. Movement updates those bodies sequentially in actor order. Small per-unit
calls use integer/Vector2i arguments without temporary packed arrays. `advance`
and `settle` update a validated mobile actor dictionary only after the caller has
certified static clearance. `explore` receives the revealed-owner dictionaries,
four-integer observer records (`owner, q, r, perception_radius`) and map radius.
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

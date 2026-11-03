# Integer CPU accelerator

`movement_kernel.hpp` implements local mobile-body queries, predictive separation,
complete hostile swept-circle contact and idle overlap pressure. All positions,
velocities, radii and calculations use integer axial coordinates. Native square
roots are estimates corrected to the exact integer floor. Global routing and
immobile collision geometry remain in the headless GDScript core.
When a cached clearance disk encloses every possible local step, the adapter
also integrates movement and settles idle overlaps in one call. Nearby static
obstacles use the general per-step geometry checks. Hostile contact remains hard
in both paths, and position/velocity/facing arrays are replaced rather than edited.

`exploration_kernel.hpp` rasterizes exact integer perception circles against map
tile centers. Per-owner discovery bitsets suppress repeated writes; illumination
and Veil discoveries are still applied by the core. These caches record only
monotonic discovery between restores and are rebuilt with each new backend.

`extension.cpp` is a small Godot C-ABI adapter with no godot-cpp dependency. It
registers a `RefCounted` utility, not scene nodes or native physics. It also writes
the exact sorted JSON UTF-8 bytes used by state hashing. ASCII string/name keys,
integers, booleans, strings, arrays, dictionaries and null are accelerated; other
values return an empty buffer so the core uses Godot's serializer. Interned names
and ordinary string keys sort together by text. Serialization does not change
state or the wire hash format.
An immutable key-text cache avoids repeated UTF-8 conversion. Variant equality
checks hash collisions; values and dictionary layouts are never cached. Retained
key entries are capped between serialization calls.

Build from the repository root with `python tools/build-native-movement.py --godot <path>
--web`. The matching Godot executable generates interface headers and builtin
method hashes. The builder publishes complete, content-addressed libraries and
the runtime descriptor atomically; all generated output stays out of Git.

ABI 7 accepts frame records in a `PackedInt64Array`, seven integers per living
mobile body: `id, owner, radius, q, r, previous_vq, previous_vr`. IDs are unique,
radii positive, and coordinates/speeds follow the core's validated map/content
limits. Movement updates those bodies sequentially in actor order. Small per-unit
calls use integer/Vector2i arguments without temporary packed arrays. `advance`
and `settle` update a validated mobile actor dictionary only after the caller has
certified static clearance. `explore` receives the revealed-owner dictionaries,
four-integer observer records (`owner, q, r, perception_radius`) and map radius.
Each restore rebuilds derived native bodies and discovery caches;
`Simulation.accelerated = false` selects the
reference implementation. Tests compare complete state hashes across both paths.

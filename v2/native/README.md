# Integer CPU accelerator

`movement_kernel.hpp` implements local mobile-body queries, predictive separation,
complete hostile swept-circle contact and idle overlap pressure. All positions,
velocities, radii and calculations use integer axial coordinates. Native square
roots are estimates corrected to the exact integer floor. Global routing and
immobile collision geometry remain in the headless GDScript core.

`extension.cpp` is a small Godot C-ABI adapter with no godot-cpp dependency. It
registers a `RefCounted` utility, not scene nodes or native physics. It also writes
the exact sorted JSON UTF-8 bytes used by state hashing. ASCII string/name keys,
integers, booleans, strings, arrays, dictionaries and null are accelerated; other
values return an empty buffer so the core uses Godot's serializer. Interned names
and ordinary string keys sort together by text. Serialization does not change
state or the wire hash format.

Build from the repository root with `python tools/build-native-movement.py --godot <path>
--web`. The matching Godot executable generates interface headers and builtin
method hashes. The builder publishes complete, content-addressed libraries and
the runtime descriptor atomically; all generated output stays out of Git.

ABI 4 accepts frame records in a `PackedInt64Array`, seven integers per living
mobile body: `id, owner, radius, q, r, previous_vq, previous_vr`. IDs are unique,
radii positive, and coordinates/speeds follow the core's validated map/content
limits. Movement updates those bodies sequentially in actor order. Small per-unit
calls use integer/Vector2i arguments without temporary packed arrays. Each restore
rebuilds derived native bodies; `Simulation.accelerated = false` selects the
reference implementation. Tests compare complete state hashes across both paths.

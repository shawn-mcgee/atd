# ATD1 rollback state format

`core/state_codec.gd` is the reference encoder and decoder. `state_codec.hpp`
implements the optional compiled encoder. Both produce the same bytes from the
same state, independently of dictionary insertion order, native cache history and
interned versus ordinary string keys. SHA-256 of these bytes is the protocol 23
state hash. Content hashes still use canonical JSON; JSON state remains version 16.

Every snapshot starts with bytes `41 54 44 01` (hex). Counts and UTF-8 byte lengths
use unsigned base-128 integers, least significant group first, with bit 7 marking
continuation. Fixed-width scalars use little-endian order.

| Tag | Payload |
| --- | --- |
| 0 | null |
| 1 / 2 | false / true |
| 3 | signed 64-bit integer, eight bytes |
| 4 | UTF-8 byte count, then string bytes |
| 5 | item count, then array elements |
| 6 | key count (1–64), sorted key strings without tag 4, then values |
| 7 | previously defined small-keyset ID, then values in its key order |
| 8 | empty dictionary |
| 9 | key count (65+), sorted key strings without tag 4, then values |
| 10 | finite IEEE-754 binary64, eight bytes |
| 16–255 | integer `tag - 80`, covering −64 through 175 |

Small-keyset IDs start at zero for each snapshot and are assigned before writing
the corresponding values, on first occurrence in sorted traversal. Empty and
large dictionaries do not consume IDs. Keyset signatures include every key's
length and UTF-8 bytes; persistent native caches never assign snapshot IDs.
The encoder uses tag 7 whenever a small keyset has already appeared. Integral
floats within int64 range encode as integers, matching JSON restoration's scalar
normalization. Interned names encode as strings. Gameplay scalar state is integer.
Runtime `Vector3i` values encode exactly as tag 5 followed by three integer
components. Decoders return ordinary arrays. This preserves existing bytes,
schema IDs, protocol 23 hashes and version 16 JSON checkpoints.
The immutable `core/neutral_stance.gd` runtime default encodes as its ordinary
five-field dictionary. Native kernels register that one marker and reject other
objects. After its first occurrence, repeated bytes reuse the current traversal's
schema reference; this cache never survives an encoding call. Restores and public
JSON checkpoints still use ordinary dictionaries. Internally, exact default stance
dictionaries are compacted again; active, nondefault and extended dictionaries
retain all their data. Internal dictionary snapshots may share this read-only
value safely; exported stance dictionaries and target arrays are independent.
The native encoder retains at most four large keysets, checking size and complete
membership before reuse. Parent keysets remain owned during nested eviction.
This skips repeated sorting of stable revelation maps without retaining values
or changing large-dictionary wire encoding.

Limits are 16 MiB per snapshot, one million elements per container and depth 128.
Keys are strings/names. The compiled encoder handles ASCII keys and delegates
other keys to the reference encoder. Strings use valid UTF-8 without NUL, matching
Godot's text representation. The decoder rejects truncation, invalid UTF-8,
unknown tags/schema IDs, oversized containers, excess depth and trailing bytes.

`Simulation.rollback_checkpoint()` uses packed bytes and an event copy on desktop;
scheduled hashes reuse those bytes, avoiding another state traversal. Web uses
Godot's faster native deep copy and encodes only at hash boundaries because its
C-ABI traversal costs more than copying. On Web hash boundaries, it retains the
encoded bytes directly, avoiding a redundant dictionary copy. History can contain
both representations. `packed_rollback` is an implementation
choice outside state; both representations produce identical ATD1 hashes.
Packed restoration uses `state_reader.hpp` when available and the GDScript reader
otherwise. Both validate the complete packet and build fresh containers without
scene objects or pointers into the encoded buffer. Dictionary restoration normalizes
scalars. Both discard derived movement/light/discovery caches. Public
`checkpoint()`/`restore()` retain their editable JSON-compatible dictionary API.
Internal dictionary snapshots retain compact velocity/facing values. Public and
diagnostic checkpoints expand them into independent integer arrays. Restoring JSON
or packed snapshots rebuilds compact motion when all components fit signed int32;
legacy motion outside that range remains an array without narrowing.
Diagnostic checkpoint requests return independent state dictionaries. Snapshot bytes
are internal history; peers exchange commands and hashes, not these snapshots.

The movement probe uses this same checkpoint-and-hash path. It also reports the
ordinary JSON state hash so simulation behavior can be compared across the wire
hash transition. `--verify` replays from both packed and JSON checkpoints outside
timed intervals and checks hostile separation on every measured tick.

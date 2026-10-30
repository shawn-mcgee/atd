# Implemented gameplay changes

- [x] Batteries were an interesting idea, but not very fun. Disable/remove vehicle charging.

- [x] You should be able to use the minimap to issue commands.

- [x] Passively heal units that are within range of the hq.

- [x] The extractor should be a 7 tile structure so it can occupy all tiles of a resource field. An extractor must overlap with at least one resource tile. An extractor should pull evenly from its resource patches so that they all deplete at roughly the same rate (this also means that an extractor that somehow sits on top of two different resource types will produce resources according to the ratio of one to the other).

- [x] Repeaters should be able to connect to generators from far away, they shouldn't have to be placed right next to generators the same way that other structures are. The distance at which repeaters can connect to generators is `repeater_radius + generator_radius`. The distance at which repeaters can connect to other repeaters is `repeater_radius + repeater_radius`. Structures that require power simply have to have one tile in range of a powered generator or repeater.

- [x] Light should propagate using a flood fill so it doesn't pour over the tops of terrain. Light sources on the 2nd level can move freely to lower levels.

- [x] Change gameplay constants to be configurable via json.

- [x] Patrol input: plain left/right click places a point and exits; Shift left/right clicks queue points; plain left click finishes queued input without adding a point; Escape exits.

Implementation details and configuration: [Gameplay balance](project/docs/gameplay-balance.md).

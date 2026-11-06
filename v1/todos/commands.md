# Coordinated tactical commands

Extracted from `ideas.md`; tentative alternatives stay there.

- [x] Extend group behavior to attack-move, defense, and patrol: assign vehicle pilots, protect engineers as passengers where possible, and form infantry escorts.
- [x] Coordinate travel speed, shared routes/patrol points, defense anchors, and bounded pursuits instead of sending vulnerable units ahead alone.
- [x] Let scouts investigate approximate scanner signals without revealing hidden enemies or permitting fire without vision.
- [x] Preserve shift queues, direct-order interruption, surviving crews, and existing mining/exploration behavior.

Implementation notes: Shared tactical missions reserve pilots, board engineers, and retain foot escorts. Walking speed limits the group; direct orders detach recipients and manual unload cancels vehicle coordination. Defenders respect an 8m leash; scout investigations use coarse contacts, stay bounded, and time out after eight seconds. Shift queues group missions and extends shared patrol routes. Surviving passengers can replace lost pilots.

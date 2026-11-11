# Continuous movement and routing

The hex grid supplies a coarse route around obstacles. It does not constrain
units to hex centers: `RouteNavigation.assign` starts at the unit's actual
position and pulls each clear stretch into a straight segment. A valid off-grid
click remains the exact endpoint. If a requested point is occupied or cannot
fit the body, the existing nearest-free destination behavior applies.

Issuing another order changes the route, not the unit's position. The initial
cell-center waypoint is skipped whenever the next segment is safe. Manual
orders, patrol/escort, resource work, combat, and Lightless retreats share this
logic; the old escort-specific centering workaround has been removed.

`WorldState._route_path` temporarily configures a shared `MovementGraph` for the
requesting body. Godot's neighbor filter rejects graph edges without enough
clearance for larger units. Infantry fit normal adjacent-center edges and
avoid that callback overhead. Edge results are cached per owner and clearance,
and cleared when navigation is rebuilt. Queries remain synchronous; do not
parallelize requests against these shared graphs and their gate admissions.

Shortcuts and movement use continuous segment-to-hex distance against the
current structure footprints, cliffs, and map boundary, expanded by the body's
radius and clearance padding. Steering uses the same checks. A long timestep
cannot jump through an intervening obstacle. A body already too close to an
edge can move out of the overlap, but cannot penetrate it further. Larger
vehicles may need wider passages than infantry.

`_move` spends the whole distance budget across intermediate waypoints, so
short segments do not introduce a pause on every simulation tick. Units still
stop for a closed door. Only friendly unlocked gates can open automatically;
opening is requested when the moving body reaches the door. Gate waypoints
remain pinned during simplification, and physical occupants hold automatic
doors open. Far-away routes do not keep a door open indefinitely.

Dark-weighted routes retain their illumination avoidance. Smoothing cannot
replace a non-attacking Lightless detour with a shortcut across light. Committed
attacks can take that shortcut, as already allowed by the combat rules.

Structure occupancy is indexed in `WorldState.structure_cells` to keep repeated
geometry queries cheap. `add_structure` registers footprints; navigation
rebuilds and snapshot application refresh the index. If a new feature directly
changes a structure's location or footprint, rebuild navigation afterward.
Started/open flags are read live from the indexed structures.

Tune `movement.pathfinding` in `config/prototype.json`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `smoothingEnabled` | `true` | Pull clear path sections into straight segments. The initial center-skip fix also applies when disabled. |
| `clearancePaddingTiles` | `0.02` | Additional clearance beyond each unit's `collisionRadiusTiles`. |
| `waypointToleranceTiles` | `0.01` | Skip tiny intermediate segments. The final valid click position is reached exactly. |

Run the pinned Godot from `v3/` with
`--headless --path . --script tests/simulation.gd -- --movement-only` for the
focused regressions. `npm test` includes those plus gate, escort, construction,
collision, snapshot, and Lightless behavior checks.

Move commands retain their original destination when only a partial route is
available. On exhaustion or a new obstruction they retry using simulation time
and `expeditions.repathIntervalSeconds`, including directly controlled Lightless
support units. Clearing terrain or unlocking a gate resumes the order; Stop cancels
it. Unavailable destinations remain pending rather than falsely reporting arrival.
The move completion goal uses the normal nearest-free endpoint for occupied cells.

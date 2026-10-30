# Gameplay balance and the todo overhaul

`res://config/gameplay.json` is the balance source. It is loaded once; stop and relaunch the game after editing it (mission restart alone retains cached configuration). The web export explicitly includes `config/*.json`. Invalid JSON, missing sections, negative/non-finite values and invalid critical ranges stop the loading screen with a retry message. Preserve existing roster IDs and required fields. Times are seconds, distances are world metres, rates are per second. Replays require the same configuration.

| Section | Controls |
| --- | --- |
| structures / units / predators / turrets / production | Costs, HP, speed, training/build time, factories, weapons, production roster |
| simulation | Fixed tick (0.1 default), HQ heal radius/rate (7m/3 HP per second), harvesting interval, repair yield, infantry weapons |
| power | Generator/core/repeater radii, outputs, gas cost per served power-second |
| economy / vehicles / resources | Starting reserves and storage; cargo and drilling; hand/extractor yield and mining reach |
| lighting | Emergency, infantry, vehicle/headlight and spotlight radii/intensities |
| world | Map radius/elevation, ridge count/length, field reserves, base grace; sampled layout distances scale from reference radius 84 |
| mission / predators_ai | Extraction radius/time; probe/grace/reinforcement timings and creature cap |
| maintenance / exploration / patrol / scouting / tactics | Maintenance searches, leashes, patrol shape and scout investigation ranges |

Geometry constants (hex shape, neighbor offsets, numerical tolerances), algorithm budgets and source/roster identifiers remain code invariants. Do not change configuration in the middle of a simulation. Static aliases expose the loaded values to existing core callers; the core still has no rendering or wall-clock dependencies.

## Behavior

- Vehicles still require pilots, but do not drain/recharge batteries. Battery fields and the old recharge replay command are inert compatibility data. Charging buttons, hotkeys, status text and bars are gone; zero legacy battery values cannot stop lights, driving, scouting or drills.
- HQ heals living friendly units within its radius, including occupants whose carrier is nearby. Healing requires a living, completed HQ; it caps at each unit's configured maximum HP and never revives casualties.
- Extractors reserve the same seven-hex footprint as HQ. At least one occupied cell must contain a surveyed, nonempty deposit; other occupancy/height/clearance rules still apply. An engineer at any accessible perimeter tile can operate it. Each resource unit is taken from the patch with the greatest remaining fraction of its original reserve, using stable patch order for ties. This balances depletion and preserves mixed-resource ratios, partial cargo capacity and the existing delivery mechanics. Offline extractors only allow ordinary adjacent hand mining. An exhausted clicked patch can continue servicing other covered deposits.
- Repeater links use the sum of both source radii (13.9m to a default generator; 20.8m to another repeater). Consumers connect through any occupied tile. Preview status and live connectivity use the same rules; disabling sources still disconnects their branches.
- `illumination.gd` caches deterministic per-source hex flood fills by geometry/source revision. Ground light sees near blocking faces but cannot propagate through cliffs, closed walls/gates, or onto higher surfaces. Ramp transitions can rise; elevated sources can illuminate equal/lower surfaces. Discovery, enemy visibility and deterrence share this result. The renderer draws the aggregated field in one instanced mask, retaining smoke/terrain coverage and avoiding per-frame per-tile draw calls. Geometry edits invalidate the caches.
- Minimap right-clicks issue contextual orders without moving the camera; left-click/drag still pans. Armed targeting modes support minimap clicks and Shift. Visible contacts and surveyed resource markers snap to their world targets.
- Patrol: an initial unmodified left/right click places a point and exits. Shift left/right clicks queue points and retain targeting. After queueing, unmodified left click finishes without adding a stray point; unmodified right click places a final point and exits. Escape cancels input while retaining the selection.

Validate with the full test runner. `todo-upgrades` covers the core behavior and `command-input` covers world/minimap patrol handling. Existing deterministic replay, logistics, construction, power and lighting suites remain active.

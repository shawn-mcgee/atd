# Single-player missions

The expedition menu offers three missions at all times, with no unlocks or persistent progress requirement. Choose a mission, optionally enter a map seed, then choose **Deploy selected mission**. Ordinary **Deploy expedition** retains the standard game. Leave or finish a mission to return to the same menu and replay any contract.

| Mission | Related mechanics | Completion |
| --- | --- | --- |
| First foothold | Worker mining and physical delivery, spending/capacity, construction, electrical placement | Deliver 20 Ore, finish a Depot, and operate a powered Floodlight. |
| Supply and steel | Powered processing, physical hauling, resource budgeting, personnel requests and specialization kits | Deliver 5 Alloy, finish a powered Foundry and Armory, and equip an additional Marine. |
| The last light | Exploration, squad combat, recovery logistics, manual extraction and defensive survival | Destroy the small central Medusa, deliver 60 Nacre, manually begin extraction and keep the Anchor alive for 30 seconds. |

The first two missions have no enemies or colony spawning. The third starts with an extra Engineer and four extra Marines, two nest Scavengers and a 250-health Medusa at the map center. Extraction sends two attacking Scavengers every ten simulation seconds, starting immediately. These contracts deliberately group mechanics; none is a single-action drill. The HUD shows current objectives and contextual control hints. Pause and speed controls remain available.

In First foothold, spend Ore on the Depot/Floodlight to make room for incoming Ore, then use **M** with a worker and click a starting Ore patch. A Depot expands storage; place the Floodlight inside the Anchor's electrical footprint. Work does not charge the blueprint again.

In Supply and steel, mine Ore to fund buildings, personnel and kits. Build the Foundry and Armory inside the Anchor grid. Select a worker, press **M** and click the Foundry to collect its buffered Alloy and return it to storage. Alloy starts at zero in this mission so there is room for deliveries. In the Armory queue a Marine kit with automatic Operator requests enabled, or request an Operator from the Anchor and send it to pick up the finished kit. Starting resources and extra workers are scenario supplies, not unlocked rewards.

In The last light, move the Marines toward the map center and attack the nest. Workers mine the remains using **M**, physically returning Nacre to the Anchor. Once 60 is delivered, select the Anchor and choose Extract. Keep the squad near the Anchor during the assault; more Nacre may still be hauled during extraction. Losing the Anchor fails any mission under normal defeat rules.

## Implementation and configuration

`config/prototype.json` owns `missions.*`. Each definition has a title/briefing, map radius and boundary inset, cleared base radius, starting inventory, and counts of additional Engineers/Marines. The peaceful missions define delivery resource/target and required completed structures; industry also defines its additional Marine count. Extraction defines nest health/Scavengers, cleared nest radius and enemy spawn radius, Nacre threshold, countdown, assault interval and wave size. Its nest health also overrides maximum health, so regeneration cannot restore the standard Medusa's larger health pool. Values are indexed in the generated [configuration reference](config-reference.md). Distances use tiles, health uses ordinary hit points, inventories/counts are whole units and timers use simulation seconds.

`WorldState.command(0, {action: start_mission, mission: id})` accepts only a fresh, one-player world. It copies the configuration, applies the scenario map and extraction overrides, then resets from the same seed. `WorldState.Missions` owns setup, requirements and completion; renderer/UI only display those results. Actual accepted cargo deposits accumulate objective progress, so initial inventory, buffered output and carried cargo do not count. Construction/power and personnel requirements query current assets. Progress is included in snapshots. Normal deployments restore the shared configuration; mission setup never modifies it.

These are initial learning contracts rather than a balanced campaign. Vehicle convoys, advanced Lightless systems and a longer combat curriculum can be added after their underlying mechanics are complete.

Validation on 2026-11-10: automated command-driven playthroughs completed all three contracts without injecting progress, and Shawn independently played and successfully completed all three missions.

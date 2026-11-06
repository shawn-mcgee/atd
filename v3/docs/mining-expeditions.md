# Mining expeditions

This is the proposed first-playable implementation of the complex mining command. The broad behavior follows the confirmed mechanics; role allocation, state transitions, and recovery rules below are implementation choices for review. Tuning lives in [prototype.json](../config/prototype.json), principally `expeditions`, `economy`, and `units`.

## Issuing the command

Select units and vehicles, press **M**, and choose a revealed resource patch or Extractor. The command requires at least one participating Operator or Engineer. An inaccessible or invalid target is rejected without replacing existing orders. No additional units or vehicles are requested or purchased automatically.

A selected occupied vehicle brings its friendly driver and passengers into the expedition. A unit already assigned to another expedition leaves that command when it accepts the new one. Manually interrupting a participant removes it from this expedition permanently; the scheduler cannot reclaim it merely because it remains nearby.

The expedition records its participants, selected source and resource, current destination, vehicle/driver pairs, worker seats, assigned gathering locations, and current phase. Individual orders issued by the player take priority over its generated orders.

## Role allocation

Allocation is deterministic: preserve valid occupied driver seats first, then sort candidates by role preference, path distance to their assigned vehicle, and stable unit ID. Re-evaluate after a death, interruption, loss of a vehicle, or seat becoming available.

1. Fill at most one driver seat per participating vehicle. Prefer **Operators**, then Marines, Flamers, Lancers, and finally Engineers. Do not remove a valid existing driver merely to improve the preference ranking.
2. Keep at least one Operator or Engineer available to gather. A worker assigned as a retained driver cannot gather at the same time. If filling another driver seat would consume the last available gatherer, leave that vehicle unassigned and report that an additional driver is needed.
3. Prioritize drivers for cargo vehicles: Rangers first, then Excavators, Scouts, and combat mechs. Existing valid pairs remain intact. Only selected vehicles are considered.
4. Assign **Engineers to Ranger passenger seats first**, followed by Operators. Use remaining Scout passenger seats for workers who cannot fit in Rangers. Surplus workers walk; unavailable seats never prevent the command from proceeding.
5. Military units not needed as drivers escort on foot. Their current stance is preserved. A defensive escort's intended position follows the convoy during travel and the defended worksite during gathering. A neutral escort still does not attack automatically.
6. Uncrewed vehicles stay where they are. They provide no light or vision. The command never pretends that an unstaffed vehicle can travel or illuminate the site.

For example, two Operators, three Engineers, two Marines, and two empty Rangers produce two Operator drivers, three Engineer passengers, and two walking Marine escorts. At the site, Engineers disembark and work while the two Operators keep the Rangers operating and lighting the area.

An Engineer and an empty Ranger alone cannot provide a retained driver and a gatherer simultaneously. This selection proceeds as a foot expedition, leaving the Ranger unused and identifying the staffing shortage. Adding an Operator or military driver enables vehicle support.

## State transitions

| Phase | Work | Completion condition |
| --- | --- | --- |
| Assemble | Assign roles, approach vehicles, and board workers. | Ready participants are assembled or the boarding timeout expires. |
| Travel to source | Move along reachable routes; escorts remain with the convoy. | Convoy reaches accessible unloading positions adjacent to the worksite. |
| Deploy | Keep drivers aboard; unload other occupants onto free reachable positions. | Gatherers have work positions and escorts have defense positions. |
| Gather and load | Mine or collect output, transfer material into vehicles, and fill personal cargo. | Shared transport is full, work is exhausted/stopped with cargo to deliver, or no reachable work remains. |
| Regroup | Return workers to assigned seats and form the convoy. | Ready participants regroup or the regroup timeout expires. |
| Travel to deposit | Choose and travel to the nearest eligible reachable delivery structure. | Cargo carriers reach deposit range. |
| Deposit | Vehicles deposit cargo; workers disembark to deposit personal cargo. | All cargo is deposited; otherwise remain waiting for capacity. |
| Repeat | Choose remaining source work and reassemble. | Return to travel, or wait visibly when no valid work remains. |

Timeouts prevent one blocked participant from freezing every other participant. Timed-out units remain members unless manually interrupted: they repath independently and can catch up when reachable. The expedition reports blocked or stranded participants rather than teleporting, silently deleting membership, or issuing impossible paths.

## Travel, boarding, and illumination

Drivers stay aboard during ordinary gathering and depositing. No automatic passenger-unload action may also unload the only driver. Boarding uses real seat counts; cargo and personal inventories never consume passenger seats.

The convoy's travel speed is limited by its slowest participating walking escort or gatherer. Vehicles wait within the configured regroup distance when companions lag. Faster vehicles do not repeatedly race ahead and expose the workers they were assigned to carry.

At the worksite, cargo vehicles park near reachable worker loading positions, outside the resource or structure footprint. Scouts and Rangers face their forward lights toward the gathering area. Driver retention keeps light and vehicle vision active. Combat follows each participant's stance and weapon restrictions; the command does not grant firing while moving or passenger firing beyond the Scout's existing exception.

## Gathering and loading

Choose reachable work positions adjacent to the source, assigning nearest positions before more distant ones and using stable IDs for ties. Avoid sending every worker through the same occupied interaction point. Nearby patches of the same resource may be used within the gathering radius.

Operators gather or collect **one item per one-second cycle**; Engineers gather or collect **two**. Both have **20** personal cargo capacity in the initial settings. These are proposed values, not final balance. Collection cannot exceed source output, worker capacity, or the whole-number resource amount available.

Workers first gather into their own inventory. When an assigned nearby cargo vehicle has room, they transfer material to it within interaction range, freeing personal capacity to continue. Prefer the worker's assigned Ranger, then another reachable participating cargo vehicle. Loading transfers existing resources; it never duplicates them or adds them to global supply.

When vehicle cargo is full, workers fill their remaining personal capacity. The expedition leaves once all usable transport capacity is full. If one worker fills before the rest, it can load a vehicle or wait while other workers finish; it does not independently leave the shared convoy.

An operational facility with an empty buffer remains a valid source: workers wait for output. A stopped facility can still have existing buffered output collected. After that output is exhausted, a partial load is delivered. Depleted patches are replaced with the nearest reachable same-resource patch inside the configured search radius.

If work is unavailable for the inactivity interval and the expedition carries anything, it delivers that cargo. With no cargo and no alternative work, it remains in a waiting/defending state and explains the reason. It does not make empty deposit trips or pretend a stopped source can produce.

## Delivery

Choose a destination at the start of each delivery trip, using reachable path distance from the convoy and stable structure ID for ties. Any ordinary Depot accepts every ordinary resource regardless of its configured capacity type. If any participating carrier has Nacre, use the owning player's Anchor so the mixed load can be delivered together.

Deposit vehicle cargo directly when in range. Workers with personal cargo disembark and deposit from a reachable position in range. Drivers remain aboard. Depositing is instantaneous up to the receiving player's free capacity for each resource; remaining cargo stays on its original carrier.

When capacity is full, stay at the destination and wait. The command does not discard cargo, change Depot configurations, purchase storage, or repeatedly drive between equally full Depots. Resources in transit remain outside the global supply until deposited.

If the destination is destroyed, select the nearest remaining eligible reachable structure. With none available, retain cargo, stop the delivery leg, and expose a no-destination status. A player may redirect any carrier; doing so removes the explicitly interrupted participants from the expedition.

After every load is deposited, workers return to their assigned vehicles and the cycle repeats. Reconfiguration of a Depot does not invalidate it as a drop-off point.

## Loss, interruption, and recovery

- **Worker killed:** Its personal cargo is lost. Release its seat and work position, then redistribute available tasks among remaining workers.
- **Vehicle destroyed:** Its cargo is lost. Occupants unload with their current health. Reassign their roles using surviving vehicles; otherwise they continue on foot.
- **Driver lost or removed:** The vehicle stops, loses light and vision, and waits for a valid replacement. Reassign only willing participants still belonging to this expedition. Keep a gatherer available when possible.
- **All workers lost or interrupted:** Keep the complex command alive, as specified. Remaining military participants defend the source, and retained drivers provide light. Show that no gatherers remain; do not automatically pull in unrelated workers.
- **Path blocked:** Recompute routes at the configured interval. After the stuck timeout, mark affected participants blocked while allowing reachable participants to continue. Recheck when the obstruction changes.
- **Player gives a new order:** Respect the interruption and release the participant. Never re-enroll it automatically. If a vehicle departs with passengers aboard, respect actual occupancy and replan affected work after they unload.
- **Player eliminated:** Existing orders continue and every vehicle forcibly unloads all occupants. The unload is a real event; the existing scheduler subsequently follows its standing orders, including any later boarding that those orders require. No new player control is provided.

## Configuration and observability

Initial timeouts are **8 seconds** for boarding, regrouping, and stuck detection; allocation and path checks run every **1 second**. Initial regroup distance is **3 tiles**, escort distance **4 tiles**, gathering radius **6 tiles**, and replacement-resource search radius **8 tiles**. See `expeditions` for the editable values.

The player should be able to inspect the active source, destination, participants, drivers, remaining cargo capacity, and current phase. Waiting states distinguish no storage capacity, no worker, no driver, no output, and no reachable route. These are command explanations, not additional resources or gameplay systems.

The first playable is accepted only after the example above completes repeated trips, a foot-only worker can work, a single unavailable seat cannot deadlock the group, full storage causes a stable wait, and deaths or manual interruptions preserve inventory and membership rules.

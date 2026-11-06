# Vehicle mechanics implemented in the browser prototype

Every vehicle needs a driver to move, use its weapon, emit light, or provide vision. Operators, Engineers, Marines, Flamers, and Lancers can drive. The first unit aboard takes the driver seat. Passenger and cargo capacities are separate, and a passenger retains its specialization, health, and personal cargo.

| Vehicle | Driver | Passengers | Vehicle cargo |
| --- | --- | --- | --- |
| Scout | 1 | 1 | 0 |
| Ranger | 1 | 3 | 100 |
| Excavator | 1 | 0 | 250 |
| Reaper, Cremator, Javelin | 1 | 0 | 0 |

All values, costs, build times, weapons, headlight ranges, and excavation rates come from `config/prototype.json`.

## Production and crew

The Factory assembles vehicles sequentially. Payment happens when the order is queued. Cancelling an unstarted vehicle refunds its vehicle cost; started orders do not refund. Destroying the Factory loses its orders. Power loss pauses production. A completed vehicle waits if its exit is blocked.

The Factory's optional Operator request adds the Operator cost and queues that Operator at the configured Anchor or Cradle. The requested Operator travels to the Factory, waits for its assigned vehicle, and boards as the driver. Vehicle and personnel orders are separate: cancelling a vehicle does not cancel or refund an Operator order. If that vehicle is cancelled or the Factory disappears, the arriving Operator becomes idle. A vehicle produced without an Operator request awaits manual boarding.

**Board vehicle** explicitly targets boarding, including when the unit carries cargo. Right clicking a friendly cargo vehicle with a loaded worker instead transfers cargo. Workers retain resources that do not fit and wait until redirected or space becomes available. Automated collect/load/drive expeditions remain future work; see [mining expeditions](mining-expeditions.md).

Engineers can use the explicit **Repair** command to repair a friendly vehicle instead of boarding it.

An occupied vehicle accepts friendly passengers up to its passenger limit. An entirely empty enemy vehicle can be commandeered by boarding it; ownership changes when the new driver enters. An occupied enemy vehicle cannot be boarded.

**Unload crew** unloads all passengers first. If only the driver remains, the next unload releases the driver. Occupants emerge at nearby reachable positions. Destruction unloads everyone at their current health, preserving personal cargo; the destroyed vehicle's cargo is lost. Player elimination also unloads everyone. Unloaded occupants become idle; other assets retain their existing orders.

## Weapons, light, and excavation

Occupants cannot be targeted or damaged separately while aboard. The Scout's passenger uses its normal weapon, follows the Scout's combat stance, and uses only the Scout's vision. It can fire while the Scout moves. Its personal stance is retained for when it disembarks. Other passengers and drivers cannot fire independently.

All driven vehicles illuminate nearby tiles. Scouts and Rangers additionally project light and vision into a forward cone. Walls, closed gates, and cliffs obstruct propagation. Unloading the last driver removes the vehicle's light and vision.

A driven Excavator can be ordered to clear a revealed interior cliff by right clicking it. Excavation takes time and leaves cosmetic, buildable rubble. The configured raw-resource yield goes directly into the Excavator's cargo; any amount beyond capacity is lost. Deposits beneath the cliff remain available after clearing. The map boundary cannot be excavated. Excavation changes and crew state are included in host snapshots.

Convoy role allocation, automated vehicle-assisted mining, advanced collision recovery, and Scout radar detection remain pending.

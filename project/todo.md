# Todo - Hive Recovery iteration

Implemented in this pass:

- [x] Rename the alien creatures to **Lightless**, adapted to a planet without light.
- [x] Mission layout: landing zone/HQ, repairable extraction beacon, and a defended Lightless Hive containing the **Hive Core**.
- [x] Repair extraction, steal the core with infantry, then remain within 7m of extraction for 30 seconds.
- [x] Hive defense and intensified swarms after theft. The core follows its carrier, including aboard vehicles, and drops on death.
- [x] Defeat when Lightless recover the dropped core or HQ is destroyed. Beacon destruction leaves repairable ruins; leaving extraction or losing the beacon resets the timer.
- [x] Halve tile radius while keeping the world extent. HQ: seven cells; barracks/generator: three-cell triangles; garage: four-cell diamond. Rotatable footprint previews, placement, clearance, and navigation agree.
- [x] Vehicle batteries discharge while driving and recharge near operating generators or repeaters. Empty batteries stop vehicles/headlights and preserve the route for charging.
- [x] Powered Extractors on resource patches: engineers gather three resources per cycle rather than one.
- [x] Generator radius reduced to about two tile steps; repeaters extend coverage and can be toggled on/off with Y or the command button.
- [x] Fix placement beside terrain by checking occupied cells rather than excluding nearby circles.
- [x] Shift queues direct orders; immediate orders and Stop clear the queue. Queued destinations are visible when selected.
- [x] Destroy owned structures/units through the command button or Delete.
- [x] Infantry can target visible Lightless or the hive; A attack-move pursues visible enemies and resumes its route.
- [x] V defends a location, structure, or unit, with a bounded pursuit leash and return to the defense point.
- [x] P patrols between the current position and a clicked point. Shift-click adds further patrol points. Escape exits targeting.
- [x] Garage-produced drill vehicle: battery, three-second rock/mesa clearing, and fixed five-methane cost per tile.
- [x] Rename displayed resources to **Materials (MAT)** and **Methane (CH4)**; retain internal resource keys for compatibility.
- [x] One-cell resource patches grouped into fields; clicking a surveyed patch reports patch and field totals.
- [x] Separate **M mining** from **E exploration**. Mining requires engineers and a patch or matching resource receiver.
- [x] Generate drill, extractor, beacon, and hive models through Asset Forge; verify imported geometry and rendered appearance.

See [README](../README.md) for controls, balance values, and validation commands.

Next playtest: tune the 30-second extraction hold, swarm pressure, battery range, and methane economy. Tentative rival-company/creature concepts remain in `../ideas.md`.

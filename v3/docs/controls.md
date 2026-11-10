# Controls

The expedition menu includes a single-player mission selector and **Deploy selected mission**. All three missions are available immediately and replayable with a chosen seed. Their HUD shows goals and control hints; **Leave** returns to the menu. See [missions](missions.md) for objectives. **Deploy expedition** starts the ordinary game.

Leave the deployment seed blank for a fresh random map and Medusa corner, or enter a seed to replay a layout. Hover the seed field to see the last deployed seed. In multiplayer, the host chooses the seed and shares it with guests.

Idle Engineers automatically seek friendly construction sites within six tiles of their footprint, then repair nearby damaged structures using Ore. Explicit jobs and queued player orders take priority; unreachable sites are skipped. Select an Engineer and choose **B, W**, then drag and release to place a straight wall line. The preview shows affordable clear cells and total cost; blocked cells appear red and are skipped. **Shift** appends the stroke to the Engineer's plan and keeps wall placement active. **Escape** or right click cancels before payment. Each segment costs its normal blueprint price; the ordinary order-queue limit applies.

Select with left click or drag; Shift adds to selection. Double-click selects matching owned units or structures in view. Right-click gives a contextual order.

Left-click and drag the minimap to pan continuously; releasing outside it still ends the drag. Right-click the minimap to issue a context order to the mapped location or visible entity. Armed attack/mine/repair/patrol/etc. modes also accept minimap left-click targets. Minimap commands use the same ownership, visibility and target checks as battlefield commands.

Hold Shift while issuing orders to append them to each selected unit's plan. Ordinary orders replace the plan; X clears it. Shift-placed construction sites appear and charge immediately, then the Engineer works them in sequence. Cancel unwanted unstarted sites separately for their refund. Queued positions appear as dashed waypoints. Continuous mining, patrol, escort and research remain active until their task ends or is replaced; queuing does not impose a timed cutoff. Paused orders remain planned until the simulation resumes.

Paid construction sites wait when units cross the footprint or access becomes blocked. Passing units keep their routes and orders. Stop interrupts the Engineer without canceling the site; select the site and use **Cancel site** to remove it. Cancellation refunds the full cost before actual work starts, including above current storage capacity; after work starts it does not refund. Enemy destruction still loses the investment.

Special targeting modes use action-specific cursors. Visible units obscured by structures receive blue friendly or amber hostile silhouettes; hidden enemies and vehicle occupants are excluded. Stance buttons update when the accepted stance changes without requiring reselection.

Click any visible model part to select a unit or structure, including roofs and outer structure parts. Small units also accept clicks close to their center. When models overlap, the nearest intersected model is selected.

Warm service lamps and loading-edge strips mark operating facilities. Production lamps and machinery indicate active work; a powered idle facility keeps its service lights. Power-off extinguishes them, while power/fuel faults blink a warning. Your facilities show queued kit cases and personnel capsules; finished kits have colored cases and lit latches while powered. The inspector and queue chips retain exact counts, progress, costs and cancellation controls.

The starting Anchor supplies 4 power: one 3-power turret plus one 1-power Floodlight. Relays extend the grid without consuming power. Floodlights provide only one tile of local vision when disabled or unpowered; their full eight-tile sight returns with power. Explored ground remains remembered after sight is lost.

Relay blueprints and selected Relays show their electrical coverage, dashed connection lines, and rings around structures in linking range. Neighbor footprints are shown because overlapping electrical footprints can connect even when the neighbor's center is outside the Relay's own footprint. Green indicates an available supply; amber indicates links without a supply. An off Relay shows grey potential links. Select it and use **Switch off / Switch on** to disconnect or reconnect its electrical footprint. Downstream supply updates immediately, including while paused. Relays consume zero power but still act as controllable grid switches.

| Key | Action |
| --- | --- |
| WASD / arrows | Pan camera |
| Middle drag / wheel | Pan / zoom |
| Q | Explicit attack target |
| X | Stop |
| M / P / E | Mine / patrol / escort |
| G / L / R / U | Board / load cargo / repair / unload |
| B | Engineer build catalogue; choose the displayed letter |
| N / F / V | Unit stance: neutral / defensive / aggressive |
| T, with a structure selected | Global automatic Operator requests on/off |
| O, at an Anchor or Cradle | Queue an Operator |
| E, at an Anchor or Cradle | Queue an Engineer kit |
| M / F / L, at an Armory | Queue Marine / Flamer / Lancer kits |
| S / R / E / H / C / J, at a Factory | Queue Scout / Ranger / Excavator / Reaper / Cremator / Javelin |
| B then D | Arm a Depot blueprint with the remembered resource type; initially Ore |
| O / G / A / P / C, while holding a Depot blueprint or with a Depot selected | Choose/reconfigure Ore / Gas / Alloy / Polymer / Crystal capacity |
| Z / Home | Focus selection / Anchor |
| Shift + 1?9 | Assign control group (browser safe) |
| Ctrl + 1?9 | Assign control group (where browser permits) |
| 1?9 | Recall group; double-tap to focus |
| Space | Single-player pause; orders remain available |
| Escape | Cancel targeting or placement |

The question-mark button opens the in-game controls guide. Build shortcuts only apply while the catalogue is open. Camera keys remain available during blueprint placement. `config/prototype.json` contains command keys, build order, selection limits, camera bindings, and route tuning; presentation controls are excluded from the multiplayer gameplay hash.

Depot resource selection is optional: after B, D, click a site immediately to use the current type. The five buttons are available while the blueprint is armed, and the last chosen type is remembered between placements. The general construction catalogue has no resource dropdown. Contextual production/resource keys take precedence over unit commands and letter-based camera panning; arrow-key camera movement remains available. The Operator toggle is global, while each Armory/Factory keeps its own personnel-source assignment.

Patrol repeats between its origin and the chosen point. Escort follows a friendly unit or structure using spaced positions. Stances determine automatic engagement; Q issues an explicit attack and is not attack-move. Coordinated vehicle mining expeditions remain unfinished.

The viewport expands to fill the window at any aspect ratio. Edge panning uses a 32-logical-pixel band at every edge; pulsing double arrows show the active direction, including both edges at corners. Edge hover takes priority over HUD hover; minimap interaction and captured drags still suppress it. Camera tuning lives under `camera.edgeBandLogicalPixels`, `edgeIndicatorSizeLogicalPixels` (8), and `edgeIndicatorPulseSeconds` (0.9) in the configuration.

Selected units and structures now show a compact task card: task icon/name, work progress, an amber blocker when waiting, and health/cargo meters. Cargo chips always name each carried resource and its quantity; group selections show summed cargo contents and a blocked-unit count. Hover the card for full combat stats and control guidance. Selected assets also show task icons in the world; waiting assets pulse amber and highlight a known friendly destination or known resource site. These indicators never identify concealed enemies.

Blockers distinguish full storage, absent drop-offs, missing recipe/repair resources, empty or unpowered production, missing drivers, unfinished vehicles/kits, cargo that must be unloaded, occupied/obstructed construction footprints, missing Engineers, and unreachable assigned work. Status is read-only and owner-filtered in multiplayer snapshots. Objective instructions and detailed statistics live in tooltips, keeping the normal HUD compact. Indicator size and pulse timing use `presentation.activityIndicators` in the configuration reference.

Multiplayer Host/Join now work in the native Godot runtime and web export. Wait for the coordinator to create the room before sharing its invitation. Guests may paste the full invitation or the room code.

Pause and speed controls are shown only in single player. Multiplayer hosts and guests do not display them; the pause shortcut remains disabled during network matches.

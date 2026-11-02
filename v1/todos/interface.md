# Interface and world status

- [x] Add materials, methane, and power icons; keep selection information and commands in one bottom dock.
- [x] Show local grid statistics for a connected selection instead of a misleading global power total.
- [x] Keep construction in an engineer Build tab, remove persistent tutorial clutter, and retain controls in F1 help/tooltips.
- [x] Show overhead health bars only for damaged allies, structures, and visible enemies; hide them after full repair/healing.
- [x] Show vehicle battery bars beneath models and let each vehicle toggle automatic recharge (N).
- [x] Set starting reserves and HQ storage to 100 materials / 100 methane.

- [x] Cache minimap terrain in one instanced mesh; update colors only for newly revealed or changed cells. Full-map redraw CPU time fell from 207?259ms to 0.5?0.9ms in the local rendered benchmark.

Validation: HUD integration coverage includes independent grids, disconnected and boarded units, recharge controls, visibility, health restoration, and window layout. Rendered previews verify world bars and both command tabs.

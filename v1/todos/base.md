# Minimal starting base

Extracted from `ideas.md`; tentative alternatives stay there.

- [x] Start with exactly the Command Center, one engineer, and one marine; build vehicles and infrastructure during play.
- [x] Increase HQ storage and let it receive both materials and methane without requiring a starting depot/tank.
- [x] Give HQ medium repeater coverage and modest bootstrap power, without starting generators or repeaters.
- [x] Reduce HQ illumination to a dim radius of about two tile steps; keep the minimal start economically playable.

- [x] Replace HQ resource scanning with discovery through illumination; add small starter material and methane deposits.

Implementation notes: Starting roster: HQ + one engineer + one marine; reserves: 100 MAT / 100 CH4. HQ: 100 MAT / 100 CH4 storage, accepts both deliveries, 7m relay range, four free auxiliary power, zero idle self-consumption, and 5.93m dim illumination. HQ can produce engineers and scouts (hotkeys 1 and 2). HQ has no resource scan or charging draw. Starter deposits: three material cells (172 each, 516 total) and one methane cell (129), discovered by HQ illumination. Remote deposits require scouting. Starting-area damage grace is 120 seconds; distant exploration remains dangerous.

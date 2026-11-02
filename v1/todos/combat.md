# Turrets and ammunition

Extracted from `ideas.md`; tentative alternatives stay there.

- [x] Add a material-fed minigun turret with lower power demand.
- [x] Add a high-power laser turret with no ammunition or reload requirement.
- [x] Add a methane-fed flame turret with area damage.
- [x] Implement automatic reload on empty, per-turret auto-reload toggles, and manual reload commands.
- [x] Reload must consume available resources atomically and disable firing until its cooldown ends; unavailable resources must not start a reload.

Implementation notes: Minigun: 3 power, 30 rounds, 8 MAT / four-second reload. Laser: 8 power, unlimited shots. Flame: 4 power, 12 shots, splash damage, 6 CH4 / five-second reload. R reloads selected turrets; Z toggles automatic reload. Reloading pauses on power loss. Types reuse the existing turret chassis with different colors.

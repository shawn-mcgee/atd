# Scenario and discovery

Extracted from `ideas.md`; tentative alternatives stay there.

- [x] Seeded random terrain, resource fields, extraction beacon, and hive on every new mission; guarantee reachable approaches and a clear landing zone.
- [x] Expose the seed for reproducible bug reports and playtests.
- [x] Keep extraction and hive off the minimap and world presentation until actually scouted; remember discovered objectives.
- [x] Increase extraction to 60 seconds. The alternative 90-second duration remains an open question.

Implementation notes: New games randomize rock ridges, resource fields, extraction, and hive positions. Protected approaches guarantee access. The HUD/end screen retain the seed; `--seed=42` reproduces it. Objectives require illumination to discover and remain recorded on the minimap afterward. Extraction is 60 seconds.

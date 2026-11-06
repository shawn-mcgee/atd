# Project instructions

The active browser alpha is the Godot 4.7.2 project at the repository root. Run commands from here. See README.md, docs/developer-guide.md, docs/implementation-status.md, and docs/controls.md.

Keep simulation deterministic and independent of scene rendering. Gameplay commands pass through WorldState; presentation and local controls must not mutate simulation state directly. Configuration lives in config/*.json; document new settings and run npm run config:reference.

Run npm test for simulation and interface checks. For browser changes run npm run export:web then npm run test:browser. Use the pinned portable engine via tools/setup-engine.py. Preserve script UID sidecars; do not regenerate editor caches or introduce @tool scripts without need.

The older v1/ and v2/ projects are preserved for reference and excluded from the root project with .gdignore files. Legacy maintenance instructions are in docs/legacy-project-instructions.md. Do not alter those games when working on the root alpha.

Keep updates concise, inspect narrow relevant code ranges, and finish authorized work without unnecessary confirmation.

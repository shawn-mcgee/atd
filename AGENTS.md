# Project instructions

The active Godot 4.7.2 browser alpha lives in v3/. Open v3/project.godot and run npm/Python project commands from v3/. Read v3/README.md and v3/docs/developer-guide.md; implementation coverage is in v3/docs/implementation-status.md.

Keep simulation deterministic and independent of presentation. Gameplay commands pass through WorldState. Configuration lives in v3/config/; document new values and regenerate the configuration reference. Preserve existing script UID sidecars; do not regenerate caches or add @tool scripts without need.

Run npm test, npm run export:web, and npm run test:browser from v3/ for relevant changes. The repository workflow stages the exported build at both / and /v3/ using v3/tools/stage-site.py. Do not deploy the legacy game at the root URL.

v1/ is preserved legacy code. Its instructions are in v3/docs/legacy-project-instructions.md. Do not mix its tooling or assets into v3/.

Keep communication concise, inspect narrow relevant code ranges, and finish authorized work without unnecessary confirmations.

# Project instructions

- Work in `v3/` (Godot 4.7.2); open `v3/project.godot`. Run npm/Python there. Read relevant sections of `README.md`, `docs/developer-guide.md`, and `docs/implementation-status.md` once; reuse findings.
- Minimize tokens/compute: use targeted `rg` searches and small line ranges, bounded tool output, and batched independent reads. Avoid whole-file dumps, repeated inspection, speculative refactors, redundant tests, and delegation unless requested. Keep updates/final concise; finish authorized work without unnecessary confirmation.
- Keep simulation deterministic and presentation-independent; commands use `WorldState`. Put tuning in `config/`; document new values and regenerate the configuration reference. Preserve script UID sidecars; avoid needless cache regeneration or `@tool` scripts.
- For gameplay changes, finish edits, then run `npm test`, `npm run export:web`, and `npm run test:browser` once. Rerun only checks affected by subsequent edits/failures. Skip game suites for documentation-only changes.
- `tools/stage-site.py` stages v3 at `/` and `/v3/`. CI's `tools/export-legacy.py` exports v1 separately under `/v1/`; never at `/`.
- Preserve `v1/`; consult `v3/docs/legacy-project-instructions.md` before legacy work. Keep its tooling/assets out of v3.

# Editor startup investigation

Use the pinned Godot version in `.godot-version`. Run `npm run check:project` before opening the editor after adding or copying scripts. Tests and browser exports run this same read-only preflight before editor import.

Every source `.gd` file must have its corresponding `.gd.uid` sidecar. Preserve these IDs when editing or moving scripts, and commit sidecars with their scripts. The preflight reports missing, malformed, or duplicate script IDs without modifying files or launching Godot. It is a guard, not a replacement for Godot's importer.

The `tools/` directory contains explicit command-line helpers and is excluded from editor scanning by `.gdignore`. No project scripts use `@tool`, and no editor plugins are enabled. The Settings autoload loads game configuration when the game runs.

## Observed failure on this Windows workspace

Editor imports repeatedly exited during filesystem scanning when new scripts lacked sidecars. Temporary `.gd.uid*.tmp` files remained. Supplying valid existing sidecars allowed import to finish. A separate Node process also terminated during file-creation testing with exit code `0xE0000027`, without a JavaScript error. Consequently, the failure is not established as a GDScript parser bug. Its OS/engine/endpoint cause remains unconfirmed.

The attempted UID-generation workaround was removed. No automatic UID generation is performed by our preflight. The interrupted combat/configuration work is preserved as text under ignored `build/interrupted-mechanics/`, outside Godot's live resource scan. These backups are not shipped. Mechanics work has resumed as nested runtime rule classes in the existing `world_state.gd` and `settings.gd` scripts, keeping new `.gd` creation out of this pass.

If the editor exits again, record its exit code, exact time, and stdout/stderr. Inspect Windows Application events and any endpoint-protection events at that time. CrowdStrike is present on this workstation, but its available local log did not establish a matching detection. A process dump or matching endpoint event is needed to assign a cause confidently.

## Local checks

```powershell
npm run check:project
npm test
& .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --import --quit
```

Verified after rollback: headless import, simulation/interface tests, and a 600-frame native editor session completed successfully (native exit code 0, no stderr errors). This does not establish the cause of earlier terminations.

The diagnostic native-editor launch writes `build/editor-stability-stdout.log` and `build/editor-stability-stderr.log`. Browser export remains the previously verified vehicle milestone until subsequent feature work passes validation.

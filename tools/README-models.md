# Generate 3D models for this project

The bridge tooling is versioned in `tools/assetforge/`. Asset Forge and Godot are installed separately, with their paths configured locally. No Godot editor plugin is required. The original 2D world remains separate from this workflow.

From the project root, run in PowerShell 7:

```powershell
pwsh -NoProfile -File .\tools\build-model.ps1 -Name bridge_sample
```

For a new asset, write `art_source/models/tower.lua` and run:

```powershell
pwsh -NoProfile -File .\tools\build-model.ps1 -Name tower
```

The command builds the model, publishes its glTF and binary buffer, imports them in Godot, creates a wrapper scene if absent, and verifies that both resources load and contain geometry. It prints JSON containing the resource paths and imported dimensions. Open `scenes/props/<name>.tscn` to inspect the result. The first build starts the worker; later builds reuse it.

Defaults preserve separate objects at 100 percent export scale. To combine the blocks:

```powershell
pwsh -NoProfile -File .\tools\build-model.ps1 -Name tower -Merge
```

Regenerating updates the model files and authoring source while preserving existing wrapper scenes. Add gameplay collision, scripts, and custom nodes to the wrapper. The wrapper creates no collision or gameplay behavior automatically. The verification checks geometry and file loading; it does not render a visual comparison.

`art_source/models/<name>.build.json` records the source hash, settings, and imported bounds. Raw staging files and logs are in `art_source/.build/`. The `.gdignore` excludes all authoring files from Godot's resource scan.

Machine-specific executable paths live in `tools/assetforge.local.psd1`, which is excluded by `.gitignore`. Other machines should copy `tools/assetforge.local.example.psd1` to that filename and set their paths. Install the bridge into a dedicated Asset Forge copy using the [bridge setup instructions](assetforge/README.md). The wrapper always uses the CLI in this repository, passing the configured application path explicitly.

The agent workflow is in the root `AGENTS.md`.

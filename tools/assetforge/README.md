# Asset Forge Lua bridge

This folder owns the bridge CLI, Unity runtime source, installer, restore script,
and a Lua example. Asset Forge itself and its block collections are installed
separately. Generated jobs, catalogs and runtime assemblies live in the dedicated
Asset Forge installation's `Bridge/` and `Asset Forge_Data/Managed/` directories.
They are not repository dependencies or files to commit.

Use a dedicated copy of your Asset Forge installation: the worker replaces its
working scene. Set its path and the Godot executable in the ignored
`tools/assetforge.local.psd1`; see `../assetforge.local.example.psd1`.

Run these commands from the project root in PowerShell 7:

```powershell
$config = Import-PowerShellDataFile ./tools/assetforge.local.psd1
# Close the dedicated copy before installing or restoring.
./tools/assetforge/Install-Bridge.ps1 -AssetForgePath $config.AssetForgeBridgePath
./tools/assetforge/assetforge-job.ps1 -AssetForgePath $config.AssetForgeBridgePath -Command status
./tools/build-model.ps1 -Name tower
./tools/assetforge/assetforge-job.ps1 -AssetForgePath $config.AssetForgeBridgePath -Command stop
# Optional: restore the dedicated copy's original assembly.
./tools/assetforge/Restore-Original.ps1 -AssetForgePath $config.AssetForgeBridgePath
```

The installer compiles `BridgeRuntime.cs` against your local Asset Forge/Unity
assemblies and patches the dedicated copy. It downloads Mono.Cecil 0.11.6 into
the ignored `.cache/` on first use. The original assembly is backed up locally.
The app needs a graphics device even when used as an unattended worker.

The CLI starts the worker automatically when building or requesting its catalog.
`-Command catalog` prints valid, case-sensitive `Collection/block` IDs. Its
generated catalog is also available at `<AssetForgeBridgePath>/Bridge/catalog.json`.
Author Lua under `art_source/models/`; the worker supplies `forge` and saves and
exports automatically. Do not add save or export dialogs to scripts.

The project wrapper publishes glTF resources, invokes Godot import, and verifies
nonempty geometry. See [the project workflow](../README-models.md) for details.

# Project instructions

This is a Godot 4.7 project with a 3D game world. Use the Asset Forge workflow below to generate or update 3D models.

The Godot project is in `project/`. The Asset Forge tools in `tools/` and the local Godot executable stay at the repository root. Run repository commands from that outer root; `res://` paths are relative to `project/`.

## Generate or update a 3D model

Use the project-owned Asset Forge Lua bridge in `tools/assetforge/` through the project's wrapper. Run from the repository root in PowerShell 7:

```powershell
pwsh -NoProfile -File .\tools\build-model.ps1 -Name tower
```

1. Read `tools/assetforge.local.psd1` to find the local Asset Forge bridge and Godot executable. If it is missing, copy the example config and obtain the correct local paths. Do not commit the local config.
2. Search `<AssetForgeBridgePath>/Bridge/catalog.json` for valid parts. Use exact, case-sensitive `Collection/block` IDs. Search relevant names instead of dumping all entries into the conversation. The existing Lua generators in the installation's `Scripts` folder provide placement examples.
3. Write the model's Lua to `project/art_source/models/<name>.lua`. Names must be lowercase snake_case, starting with a letter. The bridge supplies `forge`, starts with an empty scene, and saves/exports automatically. Do not automate the app's UI. Do not call `forge.save` or add an export dialog action.
4. Run `tools/build-model.ps1 -Name <name>`. Optionally use `-Merge`, `-Scale <percentage>` or `-TimeoutSeconds <seconds>`. The default scale is 100 percent and separate model objects are preserved. An external Lua file can be supplied with `-Script`; it will be copied into the canonical source folder after generation.
5. Check the JSON result. The wrapper invokes Godot's importer and verifies that both the imported model and wrapper scene instantiate with nonempty mesh geometry. Verify the reported bounds against the requested dimensions; passing this check does not establish visual quality. Review a rendered preview when appearance needs checking.
6. Use `res://scenes/props/<name>.tscn` in gameplay. Add collision, scripts, and behavior to that wrapper scene as needed. Regenerating a model preserves an existing wrapper scene.

## File ownership and conventions

- `project/art_source/models/<name>.lua`: procedural source; edit this to regenerate geometry.
- `project/art_source/models/<name>.model`: editable Asset Forge project.
- `project/art_source/models/<name>.build.json`: latest build settings, source hash, and verified dimensions.
- `project/assets/models/<name>/model.gltf` and `model.bin`: generated resources; keep together. Regeneration replaces these two files. Preserve their stable paths and existing Godot import settings.
- `project/scenes/props/<name>.tscn`: gameplay wrapper; preserve user edits. No collision is added automatically.
- `project/art_source/.build/`: per-build staging, import logs, and verification reports. Excluded from Godot scans and version control.
- Do not edit `.godot/` or generated mesh data by hand. Let Godot manage its import cache.
- Use Godot's Y-up coordinates. For directional assets, design their front along -Z. Prefer a ground-level origin centered under the object unless the request needs a hinge, grip, or other pivot. These are authoring conventions; the bridge does not reposition models automatically.
- Godot dimensions are interpreted as meters by convention. Compare actual imported bounds with the requested size; do not assume a block is one meter across.

## Failure handling

Read the log path in a failed command. Do not claim success based only on files existing. Fix invalid Lua/part names and rerun the wrapper. Each job gets a new staging directory; old jobs remain available for diagnosis.

The underlying worker starts automatically. It is an unattended desktop process that still needs a graphics device. A timeout does not cancel a running Lua job. The bridge CLI supports `-Command status`, `-Command catalog`, and `-Command stop`. Run these through `tools/assetforge/assetforge-job.ps1` with `-AssetForgePath` set from the local config. Reserve that copied app for generated jobs because its working scene is replaced each time. Install/restore source and instructions are in `tools/assetforge/`; application binaries, downloaded dependencies and runtime job folders do not belong in Git.

See `tools/README-models.md` for setup and commands.

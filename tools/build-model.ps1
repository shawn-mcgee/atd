param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_]*$')][string]$Name,
    [string]$Script,
    [ValidateRange(0.001,100000)][single]$Scale = 100,
    [switch]$Merge,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Join-Path $repositoryRoot 'project'
if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project was not found: $projectRoot"
}
$configPath = Join-Path $PSScriptRoot 'assetforge.local.psd1'
if (!(Test-Path -LiteralPath $configPath)) {
    throw 'Copy tools/assetforge.local.example.psd1 to tools/assetforge.local.psd1 and set your paths.'
}
$config = Import-PowerShellDataFile -LiteralPath $configPath
$bridgeCli = Join-Path $PSScriptRoot 'assetforge\assetforge-job.ps1'
$godot = $config.GodotExecutable
$verifyScript = Join-Path $PSScriptRoot 'verify-model.gd'
foreach ($required in @($bridgeCli,$godot,$verifyScript)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required tool was not found: $required" }
}
$sourceFolder = Join-Path $projectRoot 'art_source\models'
$canonicalScript = Join-Path $sourceFolder "$Name.lua"
if (!$Script) { $Script = $canonicalScript }
$Script = (Resolve-Path -LiteralPath $Script).Path
if ([IO.Path]::GetExtension($Script) -ne '.lua') { throw 'Provide a Lua script.' }
New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null
$run = [Guid]::NewGuid().ToString('N')
$stage = Join-Path $projectRoot "art_source\.build\$Name-$run"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$generated = Join-Path $stage 'generated'
# The bridge prints only JSON on success and throws on failed jobs.
$built = (& $bridgeCli -AssetForgePath $config.AssetForgeBridgePath -Script $Script -OutputDirectory $generated -Scale $Scale -Merge:$Merge -TimeoutSeconds $TimeoutSeconds | Out-String) | ConvertFrom-Json
if (!$built.success) { throw 'The model bridge did not report success.' }
$assetFolder = Join-Path $projectRoot "assets\models\$Name"
New-Item -ItemType Directory -Path $assetFolder -Force | Out-Null
Copy-Item -LiteralPath $built.gltf -Destination (Join-Path $assetFolder 'model.gltf') -Force
Copy-Item -LiteralPath $built.buffer -Destination (Join-Path $assetFolder 'model.bin') -Force
Copy-Item -LiteralPath $built.model -Destination (Join-Path $sourceFolder "$Name.model") -Force
if ($Script -ne $canonicalScript) { Copy-Item -LiteralPath $Script -Destination $canonicalScript -Force }

$sceneFolder = Join-Path $projectRoot 'scenes\props'
New-Item -ItemType Directory -Path $sceneFolder -Force | Out-Null
$scenePath = Join-Path $sceneFolder "$Name.tscn"
$modelResource = "res://assets/models/$Name/model.gltf"
$sceneResource = "res://scenes/props/$Name.tscn"
$createdScene = !(Test-Path -LiteralPath $scenePath)
if ($createdScene) {
    $nodeName = (($Name -split '_' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join '')
    $scene = @"
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="$modelResource" id="1_model"]

[node name="$nodeName" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]
"@
    [IO.File]::WriteAllText($scenePath,$scene,[Text.UTF8Encoding]::new($false))
}

# Keep all logs/staging outside Godot's resource scan via art_source/.gdignore.
$importLog = Join-Path $stage 'godot-import.log'
& $godot --headless --path $projectRoot --import 2>&1 | Out-File -LiteralPath $importLog -Encoding utf8
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern '(^|\s)(ERROR:|SCRIPT ERROR:)' -Quiet)) {
    throw "Godot import failed. See $importLog"
}
$verificationPath = Join-Path $stage 'verification.json'
$verifyLog = Join-Path $stage 'godot-verify.log'
& $godot --headless --path $projectRoot --script $verifyScript -- $modelResource $sceneResource $verificationPath 2>&1 | Out-File -LiteralPath $verifyLog -Encoding utf8
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $verificationPath)) {
    throw "Godot could not load the generated model/scene. See $verifyLog"
}
$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
if (!$verification.success) { throw "Model verification failed. See $verificationPath" }
$receipt = [ordered]@{
    success = $true
    name = $Name
    source = "art_source/models/$Name.lua"
    source_sha256 = (Get-FileHash -LiteralPath $canonicalScript -Algorithm SHA256).Hash
    scale_percent = $Scale
    merged = [bool]$Merge
    blocks = $built.blocks
    model = $modelResource
    scene = $sceneResource
    verification = $verification.resources
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$receiptJson = $receipt | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText((Join-Path $sourceFolder "$Name.build.json"),$receiptJson,[Text.UTF8Encoding]::new($false))
$receiptJson

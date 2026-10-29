param(
    [ValidateSet('build','status','catalog','stop')][string]$Command = 'build',
    [string]$Script,
    [string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AssetForgePath,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 120,
    [ValidateRange(0.001,100000)][single]$Scale = 100,
    [switch]$Merge
)
$ErrorActionPreference = 'Stop'
$bridgeDir = Join-Path $AssetForgePath 'Bridge'
$exe = Join-Path $AssetForgePath 'Asset Forge.exe'
$statusPath = Join-Path $bridgeDir 'status.json'

function Read-WorkerStatus {
    if (!(Test-Path -LiteralPath $statusPath)) { return $null }
    try {
        $state = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $worker = Get-Process -Id $state.pid -ErrorAction SilentlyContinue
        if (!$worker -or $worker.Path -ne $exe) { return $null }
        if (((Get-Date).ToUniversalTime() - [datetime]::Parse($state.utc).ToUniversalTime()).TotalSeconds -gt 15) { return $null }
        return $state
    } catch { return $null }
}

function Ensure-Worker {
    if (Read-WorkerStatus) { return }
    $existing = Get-Process -Name 'Asset Forge' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
    if (!$existing) {
        New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
        $workerArgs = '-batchmode -screen-width 640 -screen-height 480 -logFile "' + (Join-Path $bridgeDir 'worker.log') + '"'
        Start-Process -FilePath $exe -WorkingDirectory $AssetForgePath -ArgumentList $workerArgs -WindowStyle Hidden | Out-Null
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Read-WorkerStatus) { return }
        Start-Sleep -Milliseconds 250
    }
    throw "Bridge did not become ready. See $bridgeDir\worker.log"
}

function Convert-GlbToGltf([string]$InputPath, [string]$Destination) {
    $bytes = [IO.File]::ReadAllBytes($InputPath)
    if ($bytes.Length -lt 20 -or [BitConverter]::ToUInt32($bytes,0) -ne 0x46546C67 -or
        [BitConverter]::ToUInt32($bytes,4) -ne 2 -or [BitConverter]::ToUInt32($bytes,8) -ne $bytes.Length) {
        throw 'Exporter produced an invalid GLB 2.0 container.'
    }
    $offset = 12
    $doc = $null
    $binary = $null
    while ($offset -lt $bytes.Length) {
        if ($offset + 8 -gt $bytes.Length) { throw 'Truncated GLB chunk header.' }
        $length = [BitConverter]::ToUInt32($bytes,$offset)
        $kind = [BitConverter]::ToUInt32($bytes,$offset + 4)
        $offset += 8
        if ($offset + $length -gt $bytes.Length) { throw 'Truncated GLB chunk.' }
        if ($kind -eq 0x4E4F534A) {
            $doc = [Text.Encoding]::UTF8.GetString($bytes,$offset,$length).TrimEnd([char]0,[char]32) | ConvertFrom-Json
        } elseif ($kind -eq 0x004E4942) {
            $binary = New-Object byte[] $length
            [Array]::Copy($bytes,$offset,$binary,0,$length)
        }
        $offset += $length
    }
    if (!$doc -or $doc.asset.version -ne '2.0' -or !$doc.meshes -or !$doc.buffers -or $null -eq $binary) {
        throw 'Export lacks the expected glTF 2.0 meshes/buffer.'
    }
    if ($doc.buffers.Count -ne 1 -or $doc.buffers[0].byteLength -gt $binary.Length) { throw 'Unexpected GLB buffer layout.' }
    foreach ($view in $doc.bufferViews) {
        if ($view.buffer -ne 0 -or ($view.byteOffset + $view.byteLength) -gt $doc.buffers[0].byteLength) {
            throw 'Invalid buffer view in export.'
        }
    }
    # The bundled exporter writes alphaCutoff even for opaque/blended materials.
    # glTF ignores it there; remove that redundant property to avoid import warnings.
    foreach ($material in $doc.materials) {
        if ($material.alphaMode -ne 'MASK') { $material.PSObject.Properties.Remove('alphaCutoff') }
    }
    $binPath = [IO.Path]::ChangeExtension($Destination,'.bin')
    $doc.buffers[0] | Add-Member -NotePropertyName uri -NotePropertyValue ([IO.Path]::GetFileName($binPath)) -Force
    $payload = New-Object byte[] $doc.buffers[0].byteLength
    [Array]::Copy($binary,0,$payload,0,$payload.Length)
    [IO.File]::WriteAllBytes($binPath,$payload)
    $json = $doc | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Destination,$json,[Text.UTF8Encoding]::new($false))
}

if ($Command -eq 'status') {
    $state = Read-WorkerStatus
    if ($state) { $state | ConvertTo-Json } else { '{"state":"stopped"}' }
    return
}
if ($Command -eq 'stop') {
    # Stop only this dedicated copy, never the user's original installation.
    $workers = Get-Process -Name 'Asset Forge' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
    $state = Read-WorkerStatus
    if ($state -and $state.state -eq 'busy') { throw 'Worker is busy; wait for completion before stopping.' }
    $workers | Stop-Process
    foreach ($workerProcess in $workers) {
        try { $workerProcess.WaitForExit(10000) | Out-Null } finally { $workerProcess.Dispose() }
    }
    # Windows may briefly enumerate a terminated process while other handles close.
    $stopDeadline = (Get-Date).AddSeconds(10)
    do {
        $remaining = @(Get-Process -Name 'Asset Forge' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and !$_.HasExited })
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $stopDeadline)
    if ($remaining.Count -gt 0) { throw 'Worker has not stopped yet.' }
    return
}
if ($Command -eq 'build') {
    if (!$Script) { throw 'Provide -Script with an existing Lua file.' }
    $Script = (Resolve-Path -LiteralPath $Script).Path
    if ([IO.Path]::GetExtension($Script) -ne '.lua') { throw 'Script must have a .lua extension.' }
    if (!$OutputDirectory) { throw 'Provide -OutputDirectory for a new or empty output folder.' }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    if ((Test-Path -LiteralPath $OutputDirectory) -and (Get-ChildItem -LiteralPath $OutputDirectory -Force | Select-Object -First 1)) {
        throw 'Output folder must be empty, so existing assets cannot be overwritten.'
    }
}
Ensure-Worker
if ($Command -eq 'catalog') {
    Get-Content -LiteralPath (Join-Path $bridgeDir 'catalog.json') -Raw
    return
}
$id = [Guid]::NewGuid().ToString('N')
$scriptDir = Join-Path $bridgeDir 'scripts'
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
$snapshot = Join-Path $scriptDir "$id.lua"
Copy-Item -LiteralPath $Script -Destination $snapshot
$job = @{ id=$id; operation='build'; script=$snapshot; merge=[bool]$Merge; scale=$Scale }
$queuePath = Join-Path $bridgeDir "queue\$id.json"
[IO.File]::WriteAllText("$queuePath.tmp",($job | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath "$queuePath.tmp" -Destination $queuePath
$resultPath = Join-Path $bridgeDir "results\$id.json"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (!(Test-Path -LiteralPath $resultPath)) {
    if ((Get-Date) -ge $deadline) {
        throw "Timed out waiting for job $id. It may still be running. Its eventual result will be at $resultPath"
    }
    Start-Sleep -Milliseconds 250
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if (!$result.success) { throw "Asset Forge job failed: $($result.error)" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$gltfPath = Join-Path $OutputDirectory 'model.gltf'
Convert-GlbToGltf $result.glb $gltfPath
Copy-Item -LiteralPath $result.model -Destination (Join-Path $OutputDirectory 'model.model')
$summary = [ordered]@{
    success=$true; job=$id; blocks=$result.blocks
    gltf=$gltfPath; buffer=(Join-Path $OutputDirectory 'model.bin'); model=(Join-Path $OutputDirectory 'model.model')
    messages=$result.messages
}
$summary | ConvertTo-Json -Depth 5

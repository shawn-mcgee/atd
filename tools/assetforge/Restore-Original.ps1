param([Parameter(Mandatory=$true)][string]$AssetForgePath)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $AssetForgePath 'Asset Forge.exe'
if (Get-Process -Name 'Asset Forge' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe -and !$_.HasExited }) {
    throw 'Stop the bridge copy before restoring it.'
}
$main = Join-Path $AssetForgePath 'Asset Forge_Data\Managed\Assembly-CSharp.dll'
$backup = "$main.bridge-original"
if (!(Test-Path -LiteralPath $backup)) { throw 'Original assembly backup was not found.' }
Copy-Item -LiteralPath $backup -Destination $main -Force
Write-Output 'Original assembly restored. Bridge jobs and generated assets have been retained.'

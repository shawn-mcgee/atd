# Compatibility wrapper for the active repository-root browser alpha.
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & npm.cmd run export:web
    if ($LASTEXITCODE -ne 0) { throw 'Browser export failed' }
} finally { Pop-Location }

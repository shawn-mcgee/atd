param([string]$GodotExecutable)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
if (!$GodotExecutable) {
    $GodotExecutable = Join-Path $repositoryRoot 'Godot_v4.7.2-stable_win64.exe'
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
$projectRoot = Join-Path $repositoryRoot 'project'
$output = Join-Path $repositoryRoot 'build/web'
New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($phase in @('import', 'export')) {
    $log = Join-Path $output "$phase.log"
    $arguments = @('--headless', '--path', $projectRoot)
    if ($phase -eq 'import') { $arguments += @('--editor', '--import', '--quit') }
    else { $arguments += @('--export-release', 'Web', (Join-Path $output 'index.html')) }
    & $GodotExecutable @arguments 2>&1 | Out-File -LiteralPath $log -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '(^|\s)(SCRIPT ERROR:|ERROR:)' -Quiet)) {
        throw "Web $phase failed. See $log"
    }
}
foreach ($file in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    $path = Join-Path $output $file
    if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Web export is missing a nonempty $file"
    }
}
New-Item -ItemType File -Path (Join-Path $output '.nojekyll') -Force | Out-Null
Write-Output "Web build ready: $output"
Write-Output 'Preview from the repository root: python -m http.server 8000 --directory build/web'

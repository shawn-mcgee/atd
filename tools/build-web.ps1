param([string]$GodotExecutable, [ValidateSet('all', 'v1', 'v2')][string]$ProjectDirectory = 'all')
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
if (!$GodotExecutable) {
    $GodotExecutable = Join-Path $repositoryRoot 'Godot_v4.7.2-stable_win64.exe'
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
$outputDirectory = if ($ProjectDirectory -eq 'v2') { 'build/rewrite-web' } else { 'build/web' }
$siteOutput = Join-Path $repositoryRoot $outputDirectory
$projects = if ($ProjectDirectory -eq 'all') { @('v1', 'v2') } else { @($ProjectDirectory) }
foreach ($project in $projects) {
    $projectRoot = Join-Path $repositoryRoot $project
    $output = if ($ProjectDirectory -eq 'all') { Join-Path $siteOutput $project } else { $siteOutput }
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    if ($project -eq 'v2') {
        $nativeLog = Join-Path $output 'native-build.log'
        & python (Join-Path $repositoryRoot 'tools/build-native-movement.py') --godot $GodotExecutable --web 2>&1 |
            Out-File -LiteralPath $nativeLog -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Native movement build failed. See $nativeLog" }
    }
    foreach ($phase in @('import', 'export')) {
        $log = Join-Path $output "$phase.log"
        $arguments = @('--headless', '--path', $projectRoot)
        if ($project -eq 'v2') { $arguments += '--recovery-mode' }
        if ($phase -eq 'import') { $arguments += @('--editor', '--import', '--quit') }
        else { $arguments += @('--export-release', 'Web', (Join-Path $output 'index.html')) }
        & $GodotExecutable @arguments 2>&1 | Out-File -LiteralPath $log -Encoding utf8
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '(^|\s)(SCRIPT ERROR:|ERROR:)' -Quiet)) {
            throw "Web $project $phase failed. See $log"
        }
    }
    foreach ($file in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
        $path = Join-Path $output $file
        if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "Web export for $project is missing a nonempty $file"
        }
    }
    New-Item -ItemType File -Path (Join-Path $output '.nojekyll') -Force | Out-Null
}
if ($ProjectDirectory -eq 'all') {
    # Keep v1's relative asset URLs working at both / and /v1/.
    Get-ChildItem -LiteralPath (Join-Path $siteOutput 'v1') -File |
        Where-Object { $_.Extension -ne '.log' } |
        Copy-Item -Destination $siteOutput -Force
}
Write-Output "Web build ready: $siteOutput"
Write-Output "Preview from the repository root: python -m http.server 8000 --directory $outputDirectory"

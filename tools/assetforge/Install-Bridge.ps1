param([Parameter(Mandatory=$true)][string]$AssetForgePath,
      [string]$CecilPath)
$ErrorActionPreference = 'Stop'
$managed = Join-Path $AssetForgePath 'Asset Forge_Data\Managed'
$main = Join-Path $managed 'Assembly-CSharp.dll'
$backup = "$main.bridge-original"
if (Get-Process -Name 'Asset Forge' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $AssetForgePath 'Asset Forge.exe') -and !$_.HasExited }) {
    throw 'Close the bridge copy before installing.'
}
if (!$CecilPath) {
    $toolDir = Join-Path $PSScriptRoot '.cache'
    $CecilPath = Join-Path $toolDir 'cecil\lib\netstandard2.0\Mono.Cecil.dll'
    if (!(Test-Path -LiteralPath $CecilPath)) {
        New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
        Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/mono.cecil/0.11.6/mono.cecil.0.11.6.nupkg' -OutFile (Join-Path $toolDir 'cecil.zip')
        Expand-Archive -LiteralPath (Join-Path $toolDir 'cecil.zip') -DestinationPath (Join-Path $toolDir 'cecil') -Force
    }
}
if (!(Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $main -Destination $backup }
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$compilerArgs = @('/nologo','/target:library',"/out:$managed\AssetForgeBridge.dll",
    "/reference:$backup", "/reference:$managed\Assembly-CSharp-firstpass.dll",
    "/reference:$managed\UnityEngine.CoreModule.dll", "/reference:$managed\UnityEngine.JSONSerializeModule.dll",
    (Join-Path $PSScriptRoot 'BridgeRuntime.cs'))
& $csc @compilerArgs
if ($LASTEXITCODE -ne 0) { throw 'Bridge compilation failed.' }
Add-Type -Path $CecilPath
$resolver = [Mono.Cecil.DefaultAssemblyResolver]::new()
$resolver.AddSearchDirectory($managed)
$parameters = [Mono.Cecil.ReaderParameters]::new()
$parameters.AssemblyResolver = $resolver
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($backup, $parameters)
$bridge = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((Join-Path $managed 'AssetForgeBridge.dll'), $parameters)
$bridgeType = $bridge.MainModule.Types | Where-Object Name -eq 'AssetForgeBridge'
$tick = $assembly.MainModule.ImportReference(($bridgeType.Methods | Where-Object Name -eq Tick))
$choose = $assembly.MainModule.ImportReference(($bridgeType.Methods | Where-Object Name -eq ChooseExportPath))
$validate = $assembly.MainModule.ImportReference(($bridgeType.Methods | Where-Object Name -eq ValidateBlock))
$update = ($assembly.MainModule.Types | Where-Object Name -eq Global).Methods | Where-Object Name -eq Update
$update.Body.GetILProcessor().InsertBefore($update.Body.Instructions[0], [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, $tick))
$export = ($assembly.MainModule.Types | Where-Object Name -eq Export).Methods | Where-Object Name -eq ExportModel
$calls = @($export.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.Name -eq 'SaveFile' })
if ($calls.Count -ne 1) { throw 'Unexpected exporter: refusing to patch.' }
$calls[0].OpCode = [Mono.Cecil.Cil.OpCodes]::Call
$calls[0].Operand = $choose
$build = ($assembly.MainModule.Types | Where-Object Name -eq Forge).Methods | Where-Object {
    $_.Name -eq 'build' -and $_.Parameters.Count -eq 4 -and $_.Parameters[1].ParameterType.FullName -eq 'System.Single[]'
}
if (@($build).Count -ne 1) { throw 'Unexpected Lua block builder: refusing to patch.' }
$buildIl = $build.Body.GetILProcessor()
$first = $build.Body.Instructions[0]
$buildIl.InsertBefore($first, [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$buildIl.InsertBefore($first, [Mono.Cecil.Cil.Instruction]::Create([Mono.Cecil.Cil.OpCodes]::Call, $validate))
$assembly.Write("$main.bridge-new")
$assembly.Dispose(); $bridge.Dispose()
Move-Item -LiteralPath "$main.bridge-new" -Destination $main -Force
New-Item -ItemType Directory -Path (Join-Path $AssetForgePath 'Bridge') -Force | Out-Null
Write-Output 'Bridge installed. The original assembly is preserved beside the patched file.'

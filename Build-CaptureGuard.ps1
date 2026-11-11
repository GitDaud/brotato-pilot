param([string]$Zig = '')
$ErrorActionPreference = 'Stop'
if (Get-Process Brotato -ErrorAction SilentlyContinue) {
    throw 'Close the finished game before rebuilding its window guard.'
}
if (-not $Zig) {
    $localCompiler = Join-Path $PSScriptRoot 'tools/zig/zig-x86_64-windows-0.15.2/zig.exe'
    if (Test-Path -LiteralPath $localCompiler) { $Zig = $localCompiler }
    elseif (Get-Command zig -ErrorAction SilentlyContinue) { $Zig = (Get-Command zig).Source }
    else { throw 'Zig C compiler required; provide -Zig with the path to zig.exe.' }
}
$outputDirectory = Join-Path $PSScriptRoot 'tools/compiled'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
& $Zig cc -target x86_64-windows-gnu -O2 -shared (Join-Path $PSScriptRoot 'capture_window_guard.c') -luser32 -lkernel32 -o (Join-Path $outputDirectory 'capture_window_guard.dll')
if ($LASTEXITCODE -ne 0) { throw 'Capture window guard compilation failed.' }

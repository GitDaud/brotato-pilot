param(
    [ValidateSet("ranged", "brawler")][string]$Profile = "ranged",
    [ValidateSet(1, 2, 4)][int]$Speed = 1,
    [switch]$Record,
    [switch]$Isolated,
    [switch]$CaptureBackground
)
$ErrorActionPreference = 'Stop'
if (Get-Process Brotato -ErrorAction SilentlyContinue) {
    throw 'Brotato is already running. Close it before starting Pilot.'
}
if (-not (Test-Path -LiteralPath 'F:\SteamLibrary\steamapps\common\Brotato\Brotato.exe') -or
    -not (Test-Path -LiteralPath 'F:\SteamLibrary\steamapps\common\Brotato\Brotato.pck')) {
    throw 'Brotato.exe or Brotato.pck is missing from the game install directory. Restore the game before starting Pilot.'
}
if ($Record -and -not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw 'ffmpeg is required for automatic per-run recording.'
}
Push-Location $PSScriptRoot
try {
    python build_pack.py
    if ($LASTEXITCODE -ne 0) { throw 'Resource pack build failed.' }
    $oldAppId = $env:SteamAppId
    $oldGameId = $env:SteamGameId
    try {
        $env:SteamAppId = '1942280'
        $env:SteamGameId = '1942280'
        $launchArgs = @('launch_background.py','--profile',$Profile,'--speed',$Speed)
        if ($Record) { $launchArgs += '--record' }
        if ($Isolated) { $launchArgs += '--isolated' }
        if ($CaptureBackground) { $launchArgs += '--capture-background' }
        python @launchArgs
        if ($LASTEXITCODE -ne 0) { throw 'Background launch failed.' }
    } finally {
        $env:SteamAppId = $oldAppId
        $env:SteamGameId = $oldGameId
    }
} finally {
    Pop-Location
}

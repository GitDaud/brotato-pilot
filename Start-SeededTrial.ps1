param(
    [ValidateRange(0,2147483646)][int]$Seed = 2026111106,
    [ValidateRange(0,20)][int]$Wave = 0,
    [ValidateSet('weapon_double_barrel_shotgun','weapon_smg','weapon_slingshot','weapon_stick')][string]$Weapon = 'weapon_stick',
    [string]$SourceRunId = '',
    [switch]$ContinueAfterWave,
    [switch]$Record,
    [switch]$WindowCapture
)
$ErrorActionPreference = 'Stop'
if (Get-Process Brotato -ErrorAction SilentlyContinue) {
    throw 'Close the current game after reviewing its result before loading another strategy.'
}
$challenge = [ordered]@{
    enabled = $true; difficulty = 6; profile = 'ranged'
    character = 'character_well_rounded'; weapon = $Weapon; seed = $Seed
}
if ($Wave -gt 0) {
    $checkpointRoot = Join-Path $PSScriptRoot "run/checkpoints/$Seed"
    if ($SourceRunId) {
        if ($SourceRunId -notmatch '^run-[0-9-]+$') { throw 'Invalid source run ID.' }
        $candidates = @(Get-Item -LiteralPath (Join-Path $checkpointRoot "$SourceRunId/wave-$('{0:D2}' -f $Wave).json"))
    } else {
        $candidates = @(Get-ChildItem -LiteralPath $checkpointRoot -Recurse -File -Filter "wave-$('{0:D2}' -f $Wave).json" | Sort-Object LastWriteTime -Descending)
    }
    if ($candidates.Count -eq 0) { throw "No reached-wave checkpoint found for wave $Wave and seed $Seed." }
    $checkpoint = $candidates[0]
    $payload = Get-Content -Raw -LiteralPath $checkpoint.FullName | ConvertFrom-Json
    if ($payload.seed -ne $Seed -or $payload.wave -ne $Wave -or $payload.difficulty -ne 6 -or $payload.character -ne 'character_well_rounded') {
        throw 'Checkpoint seed, character, wave or difficulty mismatch.'
    }
    if (-not $PSBoundParameters.ContainsKey('Weapon')) {
        $checkpointWeapon = [string]$payload.state.players_data[0].selected_weapon
        $challenge.weapon = $checkpointWeapon -replace '_[1-4]$', ''
    }
    $challenge.resume_checkpoint = $checkpoint.FullName.Replace('\','/')
    $challenge.practice_wave_only = -not $ContinueAfterWave
    Write-Output "Practice replay: wave $Wave, source $($payload.source_run_id). Native retry count will increase."
}
$runDirectory = Join-Path $PSScriptRoot 'run'
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $runDirectory 'challenge.json'), ($challenge | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Start-Pilot.ps1') -Profile ranged -Speed 1 -Isolated:(-not $WindowCapture) -CaptureBackground:$WindowCapture -Record:($Record -or $WindowCapture)

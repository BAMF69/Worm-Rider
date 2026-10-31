# Worm Rider launcher for Dune: Awakening (Solo).
# Starts the game with the bundled UE4SS loader and the Worm Rider mod, then
# removes the loader again when the game closes, so normal (online, BattlEye)
# launches from Steam stay untouched.
param([switch]$RestoreOnly)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Journal = Join-Path $Root 'session.json'
$GameProcs = 'DuneSandbox', 'DuneSandbox_BE', 'DuneSandbox-Win64-Shipping'

function Say($m) { Write-Host "[Worm Rider] $m" }

function Find-Game {
    $parent = Split-Path -Parent $Root
    if (Test-Path (Join-Path $parent 'DuneSandbox\Binaries\Win64\DuneSandbox-Win64-Shipping.exe')) { return $parent }
    $steam = $null
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam') {
        try { $p = (Get-ItemProperty $k -ErrorAction Stop); if ($p.SteamPath) { $steam = $p.SteamPath } elseif ($p.InstallPath) { $steam = $p.InstallPath } } catch {}
        if ($steam) { break }
    }
    $libs = @()
    if ($steam) {
        $libs += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) { $libs += ([regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }) }
    }
    foreach ($lib in $libs) {
        $g = Join-Path $lib 'steamapps\common\DuneAwakening'
        if (Test-Path (Join-Path $g 'DuneSandbox\Binaries\Win64\DuneSandbox-Win64-Shipping.exe')) { return $g }
    }
    throw 'Could not find Dune: Awakening. Put this WormRider folder inside your DuneAwakening game folder and run it again.'
}

function Get-Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

function Restore-Session {
    if (-not (Test-Path $Journal)) { return }
    $s = Get-Content $Journal -Raw | ConvertFrom-Json
    foreach ($f in $s.files) {
        if (Test-Path -LiteralPath $f.path) {
            if ((Get-Hash $f.path) -ne $f.hash) { Say "Left $($f.path) alone: it was changed by something else."; continue }
            Remove-Item -LiteralPath $f.path -Force
        }
        if ($f.backup -and (Test-Path -LiteralPath $f.backup)) { Move-Item -LiteralPath $f.backup -Destination $f.path -Force }
    }
    Remove-Item $Journal -Force
    Say 'Loader removed; normal Steam launches are back to stock.'
}

if (Get-Process -Name $GameProcs -ErrorAction SilentlyContinue) {
    Say 'Dune: Awakening is already running. Close it yourself first, then run Worm Rider again.'
    if (-not $RestoreOnly) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}

Restore-Session
if ($RestoreOnly) { exit 0 }

$Game = Find-Game
$Bin = Join-Path $Game 'DuneSandbox\Binaries\Win64'
$Exe = Join-Path $Bin 'DuneSandbox-Win64-Shipping.exe'
$Ue4ss = Join-Path $Root 'ue4ss'
$Mods = Join-Path $Root 'Mods'
Say "Game: $Game"

# Point UE4SS at our own Mods folder (only Worm Rider is listed in mods.txt).
$ini = Join-Path $Ue4ss 'UE4SS-settings.ini'
$text = Get-Content $ini -Raw
$text = [regex]::Replace($text, '(?m)^ModsFolderPath\s*=.*$', "ModsFolderPath = $Mods")
$text = [regex]::Replace($text, '(?m)^ControllingModsTxt\s*=.*$', "ControllingModsTxt = $(Join-Path $Mods 'mods.txt')")
[IO.File]::WriteAllText($ini, $text, (New-Object Text.UTF8Encoding $false))

# Place the loader next to the game for this session only, journaling first.
$files = @()
foreach ($name in 'dwmapi.dll', 'UE4SS.dll') {
    $src = if ($name -eq 'dwmapi.dll') { Join-Path $Root 'dwmapi.dll' } else { Join-Path $Ue4ss 'UE4SS.dll' }
    $dest = Join-Path $Bin $name
    $backup = $null
    if (Test-Path -LiteralPath $dest) { $backup = Join-Path $Root "$name.original"; Copy-Item -LiteralPath $dest -Destination $backup -Force }
    $files += [pscustomobject]@{ path = $dest; backup = $backup; hash = (Get-Hash $src); src = $src }
}
@{ files = $files } | ConvertTo-Json -Depth 4 | Set-Content $Journal -Encoding UTF8
foreach ($f in $files) { Copy-Item -LiteralPath $f.src -Destination $f.path -Force }

# REF.cli_nobattleye: Solo session without BattlEye (mods never load online).
# REF.cli_ue4ss_path: use the bundled UE4SS.
$launchArgs = @('-nobattleye', '--ue4ss-path', ('"' + (Join-Path $Ue4ss 'UE4SS.dll') + '"'))
try {
    Say 'Starting Dune: Awakening. Pick SOLO on the main menu.'
    $p = Start-Process -FilePath $Exe -WorkingDirectory $Bin -ArgumentList $launchArgs -PassThru
    $p.WaitForExit()
    while (Get-Process -Name $GameProcs -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
} finally {
    $log = Join-Path $Ue4ss 'UE4SS.log'
    if (Test-Path $log) { Copy-Item $log (Join-Path $Root 'last-run.log') -Force }
    Restore-Session
}

# Restore script. Puts the TV back to the state saved by 2-backup.ps1.
#   .\restore.ps1                 restore from the latest backup
#   .\restore.ps1 -Backup <dir>   restore from a specific backup folder
#   .\restore.ps1 -KeepLauncher   keep the minimal home app, restore everything else
param(
    [string]$Backup,
    [switch]$KeepLauncher
)

. "$PSScriptRoot\common.ps1"
Connect-Saved

if ($Backup) { $bk = $Backup } else { $bk = Get-LatestBackup }
if (-not (Test-Path $bk)) { throw "Backup folder not found: $bk" }
Write-Host "Restoring from $bk"

# 1. Re-enable every package this kit disabled.
$logFile = Join-Path $bk 'disabled.log'
$logged = @()
if (Test-Path $logFile) {
    $logged = @(Get-Content $logFile | Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split "`t")[2] } | Sort-Object -Unique)
}

# Packages disabled now that were not disabled at backup time.
$before = @()
$beforeFile = Join-Path $bk 'packages-disabled-before.txt'
if (Test-Path $beforeFile) { $before = @(Get-Content $beforeFile | ForEach-Object { $_ -replace '^package:', '' }) }
$nowDisabled = @(Sh pm list packages -d | ForEach-Object { $_ -replace '^package:', '' })
$extras = @($nowDisabled | Where-Object { $before -notcontains $_ -and $logged -notcontains $_ })

Write-Host "Re-enabling $($logged.Count) logged packages..."
foreach ($p in $logged) {
    $r = (Sh pm enable --user 0 $p) -join ' '
    Write-Host "  $p : $r"
}

if ($extras.Count -gt 0) {
    Write-Host ''
    Write-Host 'These packages are disabled now but were enabled at backup time and are not in the log:'
    $extras | ForEach-Object { Write-Host "  $_" }
    if (Ask-YesNo 'Enable them too?' $true) {
        foreach ($p in $extras) { $r = (Sh pm enable --user 0 $p) -join ' '; Write-Host "  $p : $r" }
    }
}

# 2. Animation values.
$animFile = Join-Path $bk 'animation-before.txt'
if (Test-Path $animFile) {
    Write-Host ''
    Write-Host 'Restoring animation settings...'
    foreach ($line in (Get-Content $animFile | Where-Object { $_ -match '=' })) {
        $k, $v = $line -split '=', 2
        if ($v -eq '' -or $v -eq 'null') { Sh settings delete global $k | Out-Null }
        else { Sh settings put global $k $v | Out-Null }
        Write-Host "  $k -> $(if ($v -eq '' -or $v -eq 'null') { 'default' } else { $v })"
    }
}

# 3. Home screen.
$installed = @(Sh pm list packages $script:Pkg) -contains "package:$($script:Pkg)"
if ($installed -and -not $KeepLauncher) {
    Write-Host ''
    $stockFile = Join-Path $bk 'home-before.txt'
    if (Test-Path $stockFile) {
        $stock = (Get-Content $stockFile -Raw).Trim()
        Write-Host "Setting stock home back: $stock"
        Sh cmd package set-home-activity $stock | Out-Null
    }
    Write-Host 'Disabling the minimal home app.'
    Sh pm disable-user --user 0 $script:Pkg | Out-Null
    if (Ask-YesNo 'Also uninstall the minimal home app? It is your own app, not a system app.' $false) {
        Sh pm uninstall $script:Pkg | Out-Null
        Write-Host 'Uninstalled.'
    }
}

Press-Home
$null = Shot 'after-restore'
$null = Health-Check
Write-Host ''
Write-Host 'Restore finished. Attach the screenshot in chat. If anything still looks wrong, restart the TV from Settings.'

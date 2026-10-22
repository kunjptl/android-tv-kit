# Read-only check. Presses Home, waits, saves a screenshot and prints what the TV runs as home.
. "$PSScriptRoot\common.ps1"
Connect-Saved

Press-Home
Start-Sleep -Seconds 8
$null = Shot 'status'

Write-Host ''
Write-Host 'Home resolves to:'
Sh cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" }
Write-Host 'Top activity:'
Sh "dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'" | ForEach-Object { Write-Host "  $_" }
Write-Host 'Launcher log:'
Sh "logcat -d -s TVHome:*" | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
Write-Host 'Free memory:'
Sh "grep -E 'MemTotal|MemAvailable' /proc/meminfo" | ForEach-Object { Write-Host "  $_" }
Write-Host 'Disabled by this kit:'
$bk = Get-LatestBackup
(Get-Content (Join-Path $bk 'disabled.log') | Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split "`t")[2] }) | ForEach-Object { Write-Host "  $_" }

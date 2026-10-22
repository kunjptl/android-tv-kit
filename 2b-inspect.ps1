# Step 2b. Read-only look at what slows the TV and what the Hisense packages are allowed to do.
# Changes nothing. Writes inspect.txt into the latest backup folder.
. "$PSScriptRoot\common.ps1"
Connect-Saved
$bk  = Get-LatestBackup
$out = Join-Path $bk 'inspect.txt'
$buf = New-Object System.Collections.Generic.List[string]

function Section([string]$Title, $Lines) {
    $buf.Add("")
    $buf.Add("=== $Title ===")
    foreach ($l in @($Lines)) { if ($null -ne $l) { $buf.Add([string]$l) } }
    Write-Host "  $Title"
}

Write-Host 'Reading TV state (this takes about a minute)...'

Section 'Memory summary' (Sh "dumpsys meminfo | head -n 70")
Section 'Top processes by CPU' (Sh "top -b -n 1 -m 25")
Section 'Running services (Hisense, VT, VIDAA, Google feedback)' (Sh "dumpsys activity services | grep -E 'ServiceRecord' | grep -iE 'hisense|com.vt|vidaa|feedback|partnersetup'")

$sysPk = @(Sh pm list packages -s | ForEach-Object { $_ -replace '^package:', '' })
$watch = @($sysPk | Where-Object { $_ -match '^(com\.hisense|com\.vt|net\.vidaatv|com\.google\.android\.feedback|com\.google\.android\.partnersetup|com\.google\.android\.apps\.nbu|com\.google\.android\.apps\.tv\.launcherx)' })
Write-Host "  Permissions for $($watch.Count) packages"
foreach ($p in $watch) {
    $lines = @(Sh "dumpsys package $p | grep -E 'versionName|firstInstallTime|android.permission.(INTERNET|READ_PHONE_STATE|READ_LOGS|PACKAGE_USAGE_STATS|RECEIVE_BOOT_COMPLETED|SYSTEM_ALERT_WINDOW|GET_TASKS|READ_EXTERNAL_STORAGE|RECORD_AUDIO|CAMERA)'")
    Section "Package $p" $lines
}

Section 'Services that start at boot (Hisense, VT, VIDAA)' (Sh "dumpsys package | grep -B1 -iE 'BOOT_COMPLETED' | grep -iE 'hisense|com.vt|vidaa'")
Section 'Advertising and diagnostics settings' @(
    ('secure limit_ad_tracking = ' + ((Sh settings get secure limit_ad_tracking) -join '')),
    ('secure advertising_id = ' + ((Sh settings get secure advertising_id) -join '')),
    ('global send_action_app_error = ' + ((Sh settings get global send_action_app_error) -join '')),
    ('global stay_on_while_plugged_in = ' + ((Sh settings get global stay_on_while_plugged_in) -join ''))
)

[IO.File]::WriteAllLines($out, [string[]]$buf.ToArray())
Write-Host ''
Write-Host "Saved: $out"
Write-Host 'Tell me when this finishes. I read the file and tune step 3 to what your TV runs.'

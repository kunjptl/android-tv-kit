# Step 2. Back up the TV state before any change.
# Add -WithApks to also pull every user-installed app APK (can be large).
param([switch]$WithApks)

. "$PSScriptRoot\common.ps1"
Connect-Saved

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bk = Join-Path $Data "backup-$stamp"
New-Item -ItemType Directory -Force -Path $bk | Out-Null

Write-Host "Backing up to $bk"

function Save([string]$Name, $Lines) {
    $arr = [string[]]@($Lines | Where-Object { $null -ne $_ })
    [IO.File]::WriteAllLines((Join-Path $bk $Name), $arr)
    Write-Host ("  {0}: {1} lines" -f $Name, $arr.Count)
}

Save 'packages-all-with-paths.txt'   (Sh pm list packages -f -u)
Save 'packages-enabled-before.txt'   (Sh pm list packages -e)
Save 'packages-disabled-before.txt'  (Sh pm list packages -d)
Save 'packages-system.txt'           (Sh pm list packages -s)
Save 'packages-thirdparty.txt'       (Sh pm list packages -3)
Save 'settings-global.txt'           (Sh settings list global)
Save 'settings-secure.txt'           (Sh settings list secure)
Save 'settings-system.txt'           (Sh settings list system)
Save 'props.txt'                     (Sh getprop)
Save 'meminfo.txt'                   (Sh "cat /proc/meminfo")
Save 'storage.txt'                   (Sh df)
Save 'home-resolve.txt'              (Sh cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN)

# Values the restore script puts back.
$keys = 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'
$vals = foreach ($k in $keys) { '{0}={1}' -f $k, ((Sh settings get global $k) -join '') }
Save 'animation-before.txt' $vals

# Remember the stock home component.
$stockHome = (Get-Content (Join-Path $bk 'home-resolve.txt') | Where-Object { $_ -match '^[\w\.]+/[\w\.\$]+$' } | Select-Object -Last 1)
if ($stockHome -and $stockHome -notmatch '^android/') {
    Set-Content -Path (Join-Path $bk 'home-before.txt') -Value $stockHome
    Write-Host "  Stock home: $stockHome"
} else {
    Write-Host '  Stock home could not be read. Restore will skip the home reset.'
}

if ($WithApks) {
    $apkDir = Join-Path $bk 'apks'
    New-Item -ItemType Directory -Force -Path $apkDir | Out-Null
    Get-Content (Join-Path $bk 'packages-thirdparty.txt') | ForEach-Object {
        $p = $_ -replace '^package:', ''
        $path = (Sh pm path $p | Select-Object -First 1) -replace '^package:', ''
        if ($path) { A pull $path (Join-Path $apkDir "$p.apk") 2>&1 | Out-Null }
    }
    Write-Host '  APKs pulled.'
}

Set-Content -Path (Join-Path $Data 'latest-backup.txt') -Value $bk
[IO.File]::WriteAllText((Join-Path $bk 'disabled.log'), '')

Press-Home
Shot 'backup-done-home-screen' | Out-Null

Write-Host ''
Write-Host "Backup complete: $bk"
Write-Host 'Attach the screenshot in chat. Next: .\3-debloat.ps1'

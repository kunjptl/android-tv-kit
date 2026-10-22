# Step 3. Disable junk on a Hisense SmartTV 4K FFM (Android 11, Google TV). Nothing is uninstalled.
# Every change is "pm disable-user", logged to the backup folder, and undone by restore.ps1.
# Each group asks first. After each group the script takes a TV screenshot and asks if the TV still works.
# The package list comes from your own backup of this TV.

. "$PSScriptRoot\common.ps1"
Connect-Saved
$bk  = Get-LatestBackup
$log = Join-Path $bk 'disabled.log'
if (-not (Test-Path $log)) { [IO.File]::WriteAllText($log, '') }

Write-Host "Using backup: $bk"
$enabled = @(Sh pm list packages -e | ForEach-Object { $_ -replace '^package:', '' })

# Packages that run the TV. This script never touches them.
$kept = @(
    'com.hisense.tv.smartservice', 'com.hisense.tv.hitvinput', 'com.hisense.tv.ota', 'com.hisense.remoteupgrade',
    'com.hisense.audio_update_service', 'com.hisense.tv.customerlauncher', 'com.hisense.tv.protector',
    'com.hisense.tv.videocolor', 'com.hisense.uifac', 'com.hisense.udpserver',
    'com.vt.tv.input', 'com.vt.tv.commonui', 'com.vt.tv.mediacenter', 'com.vt.tvplayer', 'com.vt.tv.usbota',
    'com.google.android.apps.tv.launcherx', 'com.google.android.gms', 'com.google.android.katniss',
    'com.google.android.tv.assistant', 'com.google.android.tv.remote.service', 'com.android.tv.settings',
    'com.android.systemui', 'com.android.vending', 'com.netflix.ninja', 'com.google.android.youtube.tv'
)

$groups = @(
    @{
        Title = 'Junk and demo tools'
        Why   = 'No use at home. Low risk.'
        Items = @(
            @{ Pkg = 'com.hisense.storemode';           Name = 'Retail store demo mode';             Lose = 'Nothing at home.' },
            @{ Pkg = 'com.google.android.feedback';     Name = 'Google feedback and crash reporter'; Lose = 'Nothing. Stops crash report uploads.' },
            @{ Pkg = 'com.android.wallpaperbackup';     Name = 'Wallpaper backup';                   Lose = 'Nothing.' },
            @{ Pkg = 'com.android.dynsystem';           Name = 'Dynamic System updates (developer tool)'; Lose = 'Nothing.' },
            @{ Pkg = 'com.android.htmlviewer';          Name = 'HTML file viewer';                   Lose = 'Local .html files do not open.' },
            @{ Pkg = 'com.android.printspooler';        Name = 'Printing';                           Lose = 'You cannot print from this TV.' },
            @{ Pkg = 'com.android.dreams.basic';        Name = 'Basic screensaver';                  Lose = 'Clock-style screensaver stops.' }
        )
    },
    @{
        Title = 'Features you might use'
        Why   = 'Each one asks. Press Enter to keep.'
        Items = @(
            @{ Pkg = 'com.hisense.alexa';                    Name = 'Alexa on the TV';                  Lose = 'Alexa voice commands on this TV stop.' },
            @{ Pkg = 'com.hisense.hibrowser';                Name = 'Hisense web browser';              Lose = 'The built-in browser app stops.' },
            @{ Pkg = 'com.hisense.fte';                      Name = 'Hisense first-time setup';         Lose = 'Nothing after setup is done. A factory reset reruns setup without it.' },
            @{ Pkg = 'com.hisense.tv.dlna';                  Name = 'DLNA media sharing';               Lose = 'You cannot push local videos from a PC or phone using DLNA.' },
            @{ Pkg = 'com.google.android.apps.mediashell';   Name = 'Chromecast built-in';              Lose = 'You cannot cast from your phone or laptop to this TV.' },
            @{ Pkg = 'com.google.android.apps.tv.dreamx';    Name = 'Google TV ambient screensaver';    Lose = 'The photo and art screensaver stops.' },
            @{ Pkg = 'com.google.android.videos';            Name = 'Google TV movies app';             Lose = 'You lose access to movies you bought or rented from Google.' },
            @{ Pkg = 'com.google.android.play.games';        Name = 'Play Games';                       Lose = 'Google game profiles and achievements stop.' },
            @{ Pkg = 'com.google.android.youtube.tvmusic';   Name = 'YouTube Music';                    Lose = 'The YouTube Music TV app stops.' },
            @{ Pkg = 'com.google.android.marvin.talkback';   Name = 'TalkBack screen reader';           Lose = 'The spoken menu accessibility feature stops.' },
            @{ Pkg = 'com.vt.miracast';                      Name = 'Miracast screen mirroring';        Lose = 'Android screen mirroring to the TV stops.' },
            @{ Pkg = 'com.vt.tv.homekitproxy';               Name = 'Apple HomeKit bridge';             Lose = 'HomeKit control of this TV stops.' },
            @{ Pkg = 'com.vt.roomcalibration';               Name = 'Room audio calibration';           Lose = 'The room calibration feature stops.' },
            @{ Pkg = 'com.vt.tv.aiot';                       Name = 'Hisense smart home (AIoT)';        Lose = 'Hisense smart home linking stops.' }
        )
    },
    @{
        Title = 'Purpose not confirmed'
        Why   = 'Hisense packages whose job the names do not show. Run 2b-inspect.ps1 first and send me inspect.txt. Default is keep. Each gets a screenshot test.'
        Items = @(
            @{ Pkg = 'com.hisense.tv.smartsense'; Name = 'Hisense SmartSense';        Lose = 'Unknown. Possibly auto picture or usage features.' },
            @{ Pkg = 'com.vt.tv.smartsense.ui';   Name = 'SmartSense settings UI';    Lose = 'Unknown. Goes with SmartSense.' },
            @{ Pkg = 'com.hisense.evservice';     Name = 'Hisense EV service';        Lose = 'Unknown.' },
            @{ Pkg = 'net.vidaatv.android.tv';    Name = 'VIDAA TV platform app';     Lose = 'Unknown. Possible Hisense content or ad source.' }
        )
    }
)

function Apply-Batch([string]$Group, [string[]]$Pkgs) {
    $done = @()
    foreach ($p in $Pkgs) {
        if ($kept -contains $p) { Write-Warning "  skipped protected $p"; continue }
        $r = (Sh pm disable-user --user 0 $p) -join ' '
        if ($r -match 'disabled-user') {
            $done += $p
            Add-Content -Path $log -Value ("{0}`t{1}`t{2}" -f (Get-Date -Format s), $Group, $p)
            Write-Host "  disabled $p"
        } else {
            Write-Warning "  could not disable ${p}: $r"
        }
        Sh am force-stop $p | Out-Null
    }
    if ($done.Count -eq 0) { return }

    Press-Home
    $null = Shot "after-$($Group -replace ' ', '-')"
    $ok    = Health-Check
    $looks = Ask-YesNo 'Does the TV look and respond normally?' $true
    if (-not $ok -or -not $looks) {
        Write-Host 'Reverting this group...'
        foreach ($p in $done) { Sh pm enable --user 0 $p | Out-Null; Write-Host "  re-enabled $p" }
        $keep = @(Get-Content $log | Where-Object {
            $line = $_
            -not ($done | Where-Object { $line -match ("`t" + [regex]::Escape($_) + '$') })
        })
        [IO.File]::WriteAllLines($log, [string[]]$keep)
        $null = Shot "reverted-$($Group -replace ' ', '-')"
    }
}

foreach ($g in $groups) {
    $present = @($g.Items | Where-Object { $enabled -contains $_.Pkg })
    Write-Host ''
    Write-Host "=== $($g.Title) ==="
    Write-Host $g.Why
    if ($present.Count -eq 0) { Write-Host 'Nothing from this group is enabled on your TV.'; continue }

    $sel = @()
    foreach ($it in $present) {
        Write-Host ''
        Write-Host "$($it.Name)  ($($it.Pkg))"
        Write-Host "  If disabled: $($it.Lose)"
        if (Ask-YesNo '  Disable?' $false) { $sel += $it.Pkg }
    }
    Apply-Batch $g.Title $sel
}

$total = @(Get-Content $log | Where-Object { $_ -ne '' }).Count
Write-Host ''
Write-Host "Done. $total packages disabled. Log: $log"
Write-Host 'Animations are already off on your TV, so this script leaves them alone.'
Write-Host 'Attach the screenshots in chat. Next: .\4-wallpapers.ps1 then .\5-launcher.ps1'
Write-Host 'To undo everything: .\restore.ps1'

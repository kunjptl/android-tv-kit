# Step 3. Disable ads, telemetry and junk. Nothing is uninstalled.
# Every change is "pm disable-user", logged to the backup folder, and undone by restore.ps1.
# Each group asks you first. After each group the script takes a TV screenshot and asks if the TV still works.

. "$PSScriptRoot\common.ps1"
Connect-Saved
$bk  = Get-LatestBackup
$log = Join-Path $bk 'disabled.log'
if (-not (Test-Path $log)) { [IO.File]::WriteAllText($log, '') }

Write-Host "Using backup: $bk"
Write-Host 'Reading installed system apps...'
$enabled = @(Sh pm list packages -s -e | ForEach-Object { $_ -replace '^package:', '' } | Sort-Object -Unique)
Write-Host "$($enabled.Count) enabled system packages found."

# Packages this script never offers. These keep the TV booting, networked, and able to play and search.
$never = '^(android|com\.android\.(systemui|settings|providers\..*|inputmethod.*|bluetooth|packageinstaller|permissioncontroller|server.*|shell|webview|certinstaller|keychain|vending|networkstack.*|wifi.*|location.*|nfc|tv|externalstorage|documentsui|captiveportallogin|cellbroadcast.*|emergency|managedprovisioning|se|phone|incallui|carrierconfig|mtp|proxyhandler|storagemanager)|com\.google\.android\.(gms|gsf.*|vending|webview|tvlauncher|leanbacklauncher.*|tvrecommendations|inputmethod.*|katniss|setupwraith|packageinstaller|permissioncontroller|ext\..*|tts|syncadapters.*|configupdater|overlay.*|apps\.tv\.launcherx|tv\.remote.*|tvremote.*|networkstack.*)|com\.(mediatek|realtek|amlogic|hisilicon|mstar|broadcom|nxp)\..*|com\.droidlogic.*|.*\.overlay.*|.*auto_generated_rro.*|.*tuner.*|.*hdmi.*|.*\.cec.*|.*tvservice.*|.*bluetooth.*|.*wifi.*|com\.kunj\.tvhome)$'

$candidates = @($enabled | Where-Object { $_ -notmatch $never })

$adsRx    = '(^|\.)(ads?|adv|advert\w*|advertis\w*|promo\w*|marketing|sponsor\w*|banner|recommend\w*|hiads|adservice\w*|adsdk)(\.|$)'
$telRx    = '(telemetry|analytics|datacollect|dataupload|usagestat|tracker|tracking|crashreport|bugreport|logger|diagnos|statistic|feedback|collect)'
$vendorRx = 'hisense|vidaa|hismart|vewd|himedia|hitv'
$essRx    = '(input|tuner|tvsetting|hdmi|cec|audio|display|picture|panel|setting|update|ota|upgrade|wifi|network|bluetooth|remote|power|boot|provider|framework|platform|permission|factory|core|system|driver|hal|launcher|home)'

$already = New-Object System.Collections.Generic.HashSet[string]

function Apply-Batch([string]$Group, [string[]]$Pkgs) {
    $done = @()
    foreach ($p in $Pkgs) {
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
    $null = Shot "after-$Group"
    $ok   = Health-Check
    $looks = Ask-YesNo 'Does the TV look and respond normally?' $true
    if (-not $ok -or -not $looks) {
        Write-Host 'Reverting this group...'
        foreach ($p in $done) { Sh pm enable $p | Out-Null; Write-Host "  re-enabled $p" }
        $keep = @(Get-Content $log | Where-Object {
            $line = $_
            -not ($done | Where-Object { $line -match ("`t" + [regex]::Escape($_) + '$') })
        })
        [IO.File]::WriteAllLines($log, [string[]]$keep)
        $null = Shot "reverted-$Group"
    }
}

function Choose([string]$Title, [string]$Why, [string[]]$Pkgs) {
    $Pkgs = @($Pkgs | Where-Object { -not $already.Contains($_) })
    if ($Pkgs.Count -eq 0) { Write-Host ""; Write-Host "$Title : nothing found."; return @() }
    Write-Host ''
    Write-Host "=== $Title ==="
    Write-Host $Why
    $Pkgs | ForEach-Object { Write-Host "  $_" }
    $r = (Read-Host 'Disable [A]ll, [P]ick one by one, [S]kip (default S)').Trim().ToLower()
    if ($r -like 'a*') { return $Pkgs }
    if ($r -like 'p*') {
        $sel = @()
        foreach ($p in $Pkgs) { if (Ask-YesNo "  Disable $p ?" $false) { $sel += $p } }
        return $sel
    }
    return @()
}

# 1. Ads and promotions
$ads = @($candidates | Where-Object { $_ -match $adsRx })
$pick = @(Choose 'Ads and promotions' 'Package names that look like ad or promo services.' $ads)
$pick | ForEach-Object { [void]$already.Add($_) }
Apply-Batch 'ads' $pick

# 2. Telemetry and reporting
$tel = @($candidates | Where-Object { $_ -match $telRx })
$pick = @(Choose 'Telemetry and reporting' 'Usage stats, crash and bug reporters, feedback uploaders.' $tel)
$pick | ForEach-Object { [void]$already.Add($_) }
Apply-Batch 'telemetry' $pick

# 3. Manufacturer apps that do not look essential
$vendor = @($candidates | Where-Object { $_ -match $vendorRx })
$kept   = @($vendor | Where-Object { $_ -match $essRx })
$offer  = @($vendor | Where-Object { $_ -notmatch $essRx })
if ($kept.Count -gt 0) {
    Write-Host ''
    Write-Host 'Manufacturer packages kept because the names suggest they run the TV:'
    $kept | ForEach-Object { Write-Host "  $_" }
}
$pick = @(Choose 'Manufacturer apps' 'Hisense or platform apps with no sign they run hardware. Pick one by one if unsure.' $offer)
$pick | ForEach-Object { [void]$already.Add($_) }
Apply-Batch 'vendor' $pick

# 4. Features you might use. Each one asks with what you lose.
$features = @(
    @{ Pkg = 'com.google.android.apps.mediashell';    Name = 'Chromecast built-in';          Lose = 'You cannot cast from your phone or laptop to this TV.' },
    @{ Pkg = 'com.google.android.videos';             Name = 'Google TV / Play Movies app';  Lose = 'You lose access to movies you bought or rented from Google.' },
    @{ Pkg = 'com.google.android.play.games';         Name = 'Play Games';                   Lose = 'Google game profiles and achievements stop.' },
    @{ Pkg = 'com.google.android.music';              Name = 'Play Music';                   Lose = 'Old Play Music library stops.' },
    @{ Pkg = 'com.google.android.youtube.tvmusic';    Name = 'YouTube Music';                Lose = 'The YouTube Music TV app stops.' },
    @{ Pkg = 'com.google.android.backdrop';           Name = 'Ambient screensaver';          Lose = 'Google photos and art screensaver stops.' },
    @{ Pkg = 'com.android.dreams.basic';              Name = 'Basic screensaver';            Lose = 'Clock-style screensavers stop.' },
    @{ Pkg = 'com.android.dreams.phototable';         Name = 'Photo table screensaver';      Lose = 'Photo screensaver stops.' },
    @{ Pkg = 'com.google.android.tv';                 Name = 'Live Channels (antenna and cable tuner)'; Lose = 'Live TV from the built-in tuner stops. HDMI boxes are unaffected.' },
    @{ Pkg = 'com.android.printspooler';              Name = 'Printing';                     Lose = 'You cannot print from this TV.' },
    @{ Pkg = 'com.android.bips';                      Name = 'Built-in print service';       Lose = 'Same as printing.' },
    @{ Pkg = 'com.android.egg';                       Name = 'Android Easter egg';           Lose = 'Nothing.' },
    @{ Pkg = 'com.android.traceur';                   Name = 'System tracing tool';          Lose = 'Nothing for normal use.' },
    @{ Pkg = 'com.android.wallpaperbackup';           Name = 'Wallpaper backup';             Lose = 'Nothing for normal use.' },
    @{ Pkg = 'com.android.htmlviewer';                Name = 'HTML file viewer';             Lose = 'Local .html files do not open.' }
)

Write-Host ''
Write-Host '=== Features you might use ==='
Write-Host 'Answer y to disable. Press Enter to keep.'
$sel = @()
foreach ($f in $features) {
    if ($enabled -contains $f.Pkg -and -not $already.Contains($f.Pkg)) {
        Write-Host ''
        Write-Host "$($f.Name)  ($($f.Pkg))"
        Write-Host "  If disabled: $($f.Lose)"
        if (Ask-YesNo '  Disable?' $false) { $sel += $f.Pkg; [void]$already.Add($f.Pkg) }
    }
}
Apply-Batch 'features' $sel

# 5. Animation speed. Backed up in step 2.
Write-Host ''
if (Ask-YesNo 'Speed up system animations to 0.5x? Makes menus feel faster. Restore puts the old values back.' $true) {
    'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale' | ForEach-Object {
        Sh settings put global $_ 0.5 | Out-Null
    }
    Press-Home
    $null = Shot 'animations'
}

$total = @(Get-Content $log | Where-Object { $_ -ne '' }).Count
Write-Host ''
Write-Host "Done. $total packages disabled. Log: $log"
Write-Host 'Attach the screenshots in chat. Next: .\4-wallpapers.ps1 then .\5-launcher.ps1'
Write-Host 'To undo everything: .\restore.ps1'

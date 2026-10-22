# Step 5. Build the minimal home app on this PC, install it on the TV, and make it the default home.
# First run downloads a JDK (via winget) and the Android build tools (about 1 GB). Later runs are fast.
#   .\5-launcher.ps1
#   .\5-launcher.ps1 -Favorites "com.netflix.ninja,com.google.android.youtube.tv"
param([string]$Favorites)

. "$PSScriptRoot\common.ps1"

function Run([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Exe" }
}

# ---------- 1. Wallpapers ----------
$wallDir = Join-Path $Data 'wallpapers'
if (-not (Test-Path $wallDir) -or @(Get-ChildItem $wallDir -Filter *.jpg -ErrorAction SilentlyContinue).Count -eq 0) {
    Write-Host 'No wallpapers yet. Running step 4 first.'
    & "$PSScriptRoot\4-wallpapers.ps1"
}

# ---------- 2. JDK ----------
function Find-Javac {
    $c = Get-Command javac -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $roots = @("$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Java", "$env:ProgramFiles\Microsoft")
    foreach ($r in $roots) {
        if (Test-Path $r) {
            $f = Get-ChildItem $r -Directory -Filter 'jdk*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
            if ($f -and (Test-Path "$($f.FullName)\bin\javac.exe")) { return "$($f.FullName)\bin\javac.exe" }
        }
    }
    return $null
}

$javac = Find-Javac
if (-not $javac) {
    Write-Host 'Installing a JDK with winget (Eclipse Temurin 17)...'
    winget install -e --id EclipseAdoptium.Temurin.17.JDK --accept-source-agreements --accept-package-agreements
    $javac = Find-Javac
    if (-not $javac) { throw 'JDK installed but not found. Open a new PowerShell window and run this script again.' }
}
$jdkBin = Split-Path $javac -Parent
$env:JAVA_HOME = Split-Path $jdkBin -Parent
$env:PATH = "$jdkBin;$env:PATH"
$keytool = Join-Path $jdkBin 'keytool.exe'
Write-Host "JDK: $javac"

# ---------- 3. Android SDK pieces ----------
$sdk = Join-Path $Data 'android-sdk'
$jar = $null
function Find-Jar([string]$s) {
    $p = Get-ChildItem "$s\platforms" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($p -and (Test-Path "$($p.FullName)\android.jar")) { return "$($p.FullName)\android.jar" }
    return $null
}
$jar = Find-Jar $sdk
if (-not $jar -or -not (Test-Path "$sdk\build-tools")) {
    $sm = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sm)) {
        Write-Host 'Downloading Android command-line tools...'
        $zip = Join-Path $Data 'cmdline-tools.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $zip
        $tmp = Join-Path $Data 'cmdtmp'
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
        Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest" -Force
        Remove-Item $zip -Force
    }
    Write-Host 'Accepting SDK licences and installing platform 34 and build-tools 34.0.0...'
    1..40 | ForEach-Object { 'y' } | & $sm "--sdk_root=$sdk" --licenses | Out-Null
    Run $sm @("--sdk_root=$sdk", 'platforms;android-34', 'build-tools;34.0.0')
    $jar = Find-Jar $sdk
}
$bt = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $jar -or -not $bt) { throw 'Android SDK install incomplete.' }
$btp = $bt.FullName
Write-Host "SDK: platform jar $jar, build-tools $($bt.Name)"

# ---------- 4. Pick dock apps from what is installed on the TV ----------
Connect-Saved

$favList = @()
if ($Favorites) {
    $favList = @($Favorites -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
} else {
    Write-Host ''
    Write-Host 'Apps on the TV that have a launcher entry:'
    $lines = @(Sh cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER)
    $pkgs = @()
    foreach ($l in $lines) {
        if ($l -match '([A-Za-z][\w\.]*)/[\w\.\$]+') { $pkgs += $Matches[1] }
    }
    $pkgs = @($pkgs | Where-Object { $_ -ne $script:Pkg } | Sort-Object -Unique)
    if ($pkgs.Count -eq 0) {
        $pkgs = @(Sh pm list packages -3 | ForEach-Object { $_ -replace '^package:', '' } | Sort-Object)
    }
    for ($i = 0; $i -lt $pkgs.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $pkgs[$i]) }
    Write-Host ''
    $ans = (Read-Host 'Type the numbers for your dock in order, like 3,1,7. Press Enter for common streaming apps that are installed').Trim()
    if ($ans) {
        foreach ($n in ($ans -split ',')) {
            $idx = 0
            if ([int]::TryParse($n.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $pkgs.Count) { $favList += $pkgs[$idx - 1] }
        }
    }
}
Write-Host ("Dock apps: " + $(if ($favList.Count) { $favList -join ', ' } else { '(default streaming list)' }))

# ---------- 5. Build ----------
$src = Join-Path $PSScriptRoot 'launcher'
$b = Join-Path $Data 'build'
if (Test-Path $b) { Remove-Item -Recurse -Force $b }
foreach ($d in 'assets', 'gen', 'classes', 'dex') { New-Item -ItemType Directory -Force -Path (Join-Path $b $d) | Out-Null }

# Flat file names. aapt2 on Windows stores sub-folder entries with a backslash and Android cannot read them.
Get-ChildItem $wallDir -Filter *.jpg | ForEach-Object { Copy-Item $_.FullName (Join-Path $b ('assets\wall_' + $_.Name)) -Force }
$favText = "# Dock apps, one package per line. The TV list can be edited on the TV by holding OK in All apps.`r`n" + ($favList -join "`r`n")
Set-Content -Path (Join-Path $b 'assets\favorites.txt') -Value $favText -Encoding ASCII

Write-Host 'Building...'
Run "$btp\aapt2.exe" @('compile', '--dir', "$src\res", '-o', "$b\res.zip")
Run "$btp\aapt2.exe" @('link', '-o', "$b\base.apk", '-I', $jar, '--manifest', "$src\AndroidManifest.xml",
    '-A', "$b\assets", '--java', "$b\gen", '--min-sdk-version', '21', '--target-sdk-version', '28',
    '--version-code', '1', '--version-name', '1.0', "$b\res.zip")

$srcs = @(Get-ChildItem "$src\java" -Recurse -Filter *.java | ForEach-Object { $_.FullName }) +
        @(Get-ChildItem "$b\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$argFile = Join-Path $b 'javac-args.txt'
($srcs | ForEach-Object { '"' + ($_ -replace '\\', '/') + '"' }) | Set-Content -Path $argFile -Encoding ASCII
Run $javac @('--release', '8', '-encoding', 'UTF-8', '-Xlint:-options', '-cp', $jar, '-d', "$b\classes", "@$argFile")

$classes = @(Get-ChildItem "$b\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName })
Run "$btp\d8.bat" (@('--lib', $jar, '--min-api', '21', '--output', "$b\dex") + $classes)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipf = [IO.Compression.ZipFile]::Open("$b\base.apk", 'Update')
[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipf, "$b\dex\classes.dex", 'classes.dex')
$zipf.Dispose()

Run "$btp\zipalign.exe" @('-f', '4', "$b\base.apk", "$b\aligned.apk")

$ks = Join-Path $Data 'tvhome.keystore'
if (-not (Test-Path $ks)) {
    Run $keytool @('-genkeypair', '-keystore', $ks, '-storepass', 'android', '-keypass', 'android',
        '-alias', 'tvhome', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=TV Home')
}
$apk = Join-Path $Data 'MinimalHome.apk'
Run "$btp\apksigner.bat" @('sign', '--ks', $ks, '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
    '--out', $apk, "$b\aligned.apk")
Write-Host ("Built {0} ({1} MB)" -f $apk, [math]::Round((Get-Item $apk).Length / 1MB, 1))

# ---------- 6. Install and test before making it the default ----------
Write-Host 'Installing on the TV...'
$out = (A install -r $apk 2>&1 | Out-String)
Write-Host $out
if ($out -notmatch 'Success') { throw 'Install failed. Send me the text above.' }

A logcat -c | Out-Null
Sh am start -n "$($script:Pkg)/.HomeActivity" | Out-Null
Start-Sleep -Seconds 10
$null = Shot 'launcher-first-run'
Write-Host 'Launcher log lines:'
Sh "logcat -d -s TVHome:*" | Select-Object -Last 12 | ForEach-Object { Write-Host "  $_" }
$null = Health-Check
if (-not (Ask-YesNo 'Does the TV show the new home screen with a wallpaper and a dock?' $true)) {
    Write-Host 'Not setting it as default. Send me the screenshot. Press HOME on the remote to return to the stock home.'
    Sh am force-stop $script:Pkg | Out-Null
    return
}

# ---------- 7. Make it the default home ----------
function Home-IsOurs {
    $top = (Sh "dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'") -join ' '
    return ($top -match [regex]::Escape($script:Pkg))
}

Sh cmd package set-home-activity "$($script:Pkg)/.HomeActivity" | Out-Null
Sh am start -a android.intent.action.MAIN -c android.intent.category.HOME | Out-Null
Start-Sleep -Seconds 3
Sh input keyevent 4 | Out-Null
Press-Home
$null = Shot 'home-button-result'
$resolved = (Sh cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | Select-Object -Last 1)
Write-Host "Home resolves to: $resolved"

if (-not (Home-IsOurs)) {
    $stock = 'com.google.android.apps.tv.launcherx'
    $stockOn = @(Sh pm list packages -e $stock) -contains "package:$stock"
    Write-Host ''
    Write-Host 'The Home button still opens the stock Google TV home.'
    Write-Host 'Google TV keeps its own home as the default. The fix is to disable the stock home app.'
    Write-Host 'This is reversible. restore.ps1 enables it again. Your new home has All apps and Settings tiles.'
    if ($stockOn -and (Ask-YesNo "Disable $stock ?" $true)) {
        $bk = Get-LatestBackup
        $r = (Sh pm disable-user --user 0 $stock) -join ' '
        Write-Host $r
        Add-Content -Path (Join-Path $bk 'disabled.log') -Value ("{0}`t{1}`t{2}" -f (Get-Date -Format s), 'stock-home', $stock)
        Sh am force-stop $stock | Out-Null
        Start-Sleep -Seconds 2
        Press-Home
        $null = Shot 'after-stock-home-disabled'
        if (-not (Home-IsOurs) -or -not (Ask-YesNo 'Is the new home screen showing after pressing Home?' $true)) {
            Write-Host 'Reverting. Re-enabling the stock home.'
            Sh pm enable --user 0 $stock | Out-Null
            $keep = @(Get-Content (Join-Path $bk 'disabled.log') | Where-Object { $_ -notmatch ("`t" + [regex]::Escape($stock) + '$') })
            [IO.File]::WriteAllLines((Join-Path $bk 'disabled.log'), [string[]]$keep)
            Press-Home
            $null = Shot 'stock-home-reenabled'
        }
    }
}

Write-Host ''
Write-Host 'Done. Use the remote: left and right move the dock, OK opens an app, hold OK on a dock app removes it.'
Write-Host 'Open All apps (the grid tile) and hold OK on any app to add it to the dock.'
Write-Host 'To check status later: .\status.ps1'
Write-Host 'To undo everything: .\restore.ps1'

# Shared helpers. Every other script dot-sources this file.
# Works in Windows PowerShell 5.1 and PowerShell 7.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Continue'

$script:Kit    = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Data   = Join-Path $env:USERPROFILE 'tv-kit-data'
$script:Shots  = Join-Path $script:Data 'screenshots'
$script:Pkg    = 'com.kunj.tvhome'
$script:AdbExe = $null
$script:Target = $null

New-Item -ItemType Directory -Force -Path $script:Data  | Out-Null
New-Item -ItemType Directory -Force -Path $script:Shots | Out-Null

function Ensure-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $script:AdbExe = $cmd.Source; return }
    $local = Join-Path $script:Data 'platform-tools\adb.exe'
    if (-not (Test-Path $local)) {
        Write-Host 'Downloading Android platform-tools from Google...'
        $zip = Join-Path $script:Data 'platform-tools.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $script:Data -Force
        Remove-Item $zip -Force
    }
    $script:AdbExe = $local
}

function Adb-Raw { & $script:AdbExe @args }

function Load-Target {
    Ensure-Adb
    $f = Join-Path $script:Data 'device.txt'
    if (-not (Test-Path $f)) { throw 'No saved TV. Run 1-connect.ps1 first.' }
    $script:Target = (Get-Content $f -Raw).Trim()
}

function Connect-Saved {
    Load-Target
    if ($script:Target -match ':\d+$') { Adb-Raw connect $script:Target | Out-Null }
    $state = (Adb-Raw -s $script:Target get-state 2>&1 | Out-String).Trim()
    if ($state -ne 'device') {
        throw "TV not reachable (state: $state). Check the TV is on, then run 1-connect.ps1 again."
    }
}

# Run adb against the saved TV.
function A { & $script:AdbExe -s $script:Target @args }

# Run a shell command on the TV. Returns trimmed non-empty lines.
function Sh {
    $out = & $script:AdbExe -s $script:Target shell @args 2>&1
    $out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' }
}

function Press-Home {
    A shell input keyevent 3 | Out-Null
    Start-Sleep -Seconds 4
}

function Shot([string]$Label) {
    $safe = ($Label -replace '[^\w-]', '_')
    $file = Join-Path $script:Shots ("{0}-{1}.png" -f (Get-Date -Format 'HHmmss'), $safe)
    A shell screencap -p /sdcard/kit-shot.png | Out-Null
    A pull /sdcard/kit-shot.png $file 2>&1 | Out-Null
    A shell rm /sdcard/kit-shot.png | Out-Null
    if (Test-Path $file) {
        Write-Host "Screenshot saved: $file"
        Start-Process $file
        return $file
    }
    Write-Warning 'Screenshot failed. Protected video can block screen capture.'
    return $null
}

function Health-Check {
    $state = (Adb-Raw -s $script:Target get-state 2>&1 | Out-String).Trim()
    if ($state -ne 'device') { Write-Warning "TV state: $state"; return $false }
    $focus = Sh "dumpsys window | grep -E 'mCurrentFocus'"
    Write-Host "Focus: $($focus -join ' ')"
    if (($focus -join ' ') -match 'Application Not Responding|has stopped|Crash') { return $false }
    return $true
}

function Get-LatestBackup {
    $p = Join-Path $script:Data 'latest-backup.txt'
    if (-not (Test-Path $p)) { throw 'No backup found. Run 2-backup.ps1 first.' }
    $dir = (Get-Content $p -Raw).Trim()
    if (-not (Test-Path $dir)) { throw "Backup folder missing: $dir" }
    return $dir
}

function Ask-YesNo([string]$Prompt, [bool]$Default = $false) {
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $r = (Read-Host "$Prompt $suffix").Trim().ToLower()
    if ($r -eq '') { return $Default }
    return ($r -eq 'y' -or $r -eq 'yes')
}

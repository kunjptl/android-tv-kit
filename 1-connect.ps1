# Step 1. Find the TV on your Wi-Fi and connect over ADB.
. "$PSScriptRoot\common.ps1"
Ensure-Adb

Write-Host ''
Write-Host 'On the TV first:'
Write-Host '  Settings > Device Preferences > About > press OK on Build seven times.'
Write-Host '  Settings > Device Preferences > Developer options > turn on USB debugging.'
Write-Host '  Turn on Network debugging (or ADB debugging over network) if the TV lists it.'
Write-Host '  Keep the TV and this PC on the same Wi-Fi or router.'
Write-Host ''

function Find-Candidates {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '127.*' -and
            $_.InterfaceAlias -notmatch 'vEthernet|WSL|VirtualBox|VMware|Loopback|Bluetooth'
        }
    $found = @()
    foreach ($ip in $ips) {
        $base = ($ip.IPAddress -split '\.')[0..2] -join '.'
        Write-Host "Scanning $base.0/24 for port 5555..."
        $jobs = @{}
        1..254 | ForEach-Object {
            $h = "$base.$_"
            $c = New-Object Net.Sockets.TcpClient
            $jobs[$h] = @{ C = $c; T = $c.ConnectAsync($h, 5555) }
        }
        Start-Sleep -Milliseconds 3000
        foreach ($h in $jobs.Keys) {
            $j = $jobs[$h]
            if ($j.T.IsCompleted -and -not $j.T.IsFaulted -and $j.C.Connected) { $found += $h }
            $j.C.Close()
        }
    }
    return $found
}

$ip = (Read-Host 'TV IP address (press Enter to scan, or type the IP from Settings > Network)').Trim()
$endpoint = $null

if (-not $ip) {
    $cands = @(Find-Candidates)
    if ($cands.Count -eq 0) {
        Write-Host 'No device answered on port 5555.'
        Write-Host 'Check the Network debugging toggle, then type the TV IP below.'
        $ip = (Read-Host 'TV IP address').Trim()
    }
    elseif ($cands.Count -eq 1) {
        $ip = $cands[0]
        Write-Host "Found one candidate: $ip"
    }
    else {
        for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host "  [$($i + 1)] $($cands[$i])" }
        $n = [int](Read-Host 'Pick the number of your TV')
        $ip = $cands[$n - 1]
    }
}

if (-not $ip) { throw 'No IP given.' }

if ($ip -match ':\d+$') { $endpoint = $ip } else { $endpoint = "${ip}:5555" }

if (Ask-YesNo 'Does the TV show a Wireless debugging pairing code (newer Android TV)?' $false) {
    $pairEp = (Read-Host 'Pairing IP:port shown on the TV').Trim()
    $code   = (Read-Host 'Pairing code').Trim()
    Adb-Raw pair $pairEp $code
    $endpoint = (Read-Host 'Connect IP:port shown on the TV (not the pairing port)').Trim()
}

Write-Host "Connecting to $endpoint ..."
Adb-Raw connect $endpoint

Write-Host 'Look at the TV. Accept the "Allow USB debugging?" prompt and tick Always allow.'
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
    $state = (Adb-Raw -s $endpoint get-state 2>&1 | Out-String).Trim()
    if ($state -eq 'device') { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { throw "Could not reach the TV (last state: $state)." }

Set-Content -Path (Join-Path $Data 'device.txt') -Value $endpoint
$script:Target = $endpoint

Write-Host ''
Write-Host 'Connected. Device facts:'
'ro.product.manufacturer', 'ro.product.model', 'ro.build.version.release', 'ro.build.version.sdk' |
    ForEach-Object { '{0} = {1}' -f $_, ((Sh getprop $_) -join '') }
$mem = Sh "grep -E 'MemTotal|MemAvailable' /proc/meminfo"
$mem | ForEach-Object { Write-Host $_ }
Sh "df /data | tail -n 1" | ForEach-Object { Write-Host "Storage: $_" }

Shot 'connected' | Out-Null
Write-Host ''
Write-Host 'Attach the screenshot and the facts above in chat. Next: .\2-backup.ps1'

# Step 4. Download nature wallpapers on this PC (1920 px wide JPEGs from Wikimedia Commons featured pictures).
# The launcher build in step 5 bundles them inside the app, so the TV needs no network or storage permission.
param([int]$Count = 20)

. "$PSScriptRoot\common.ps1"

$dest = Join-Path $Data 'wallpapers'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$ua = @{ 'User-Agent' = 'tv-kit/1.0 (personal home screen project)' }

$cats = @(
    'Featured pictures of landscapes',
    'Featured pictures of mountains',
    'Featured pictures of lakes',
    'Featured pictures of waterfalls',
    'Featured pictures of forests',
    'Featured pictures of beaches'
)

$pool = @()
foreach ($c in $cats) {
    $uri = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=categorymembers' +
           '&gcmtype=file&gcmlimit=60&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1920' +
           '&gcmtitle=' + [uri]::EscapeDataString("Category:$c")
    try {
        $r = Invoke-RestMethod -Uri $uri -Headers $ua
        if ($r.query -and $r.query.pages) {
            foreach ($page in $r.query.pages.PSObject.Properties.Value) {
                $ii = $page.imageinfo | Select-Object -First 1
                if (-not $ii) { continue }
                if ($ii.mime -ne 'image/jpeg') { continue }
                if ($ii.width -lt 1920) { continue }
                $ratio = $ii.width / [double]$ii.height
                if ($ratio -lt 1.3 -or $ratio -gt 2.2) { continue }
                $pool += [pscustomobject]@{ Title = $page.title; Page = $ii.descriptionurl; Url = $ii.thumburl }
            }
        }
        Write-Host "$c : pool now $($pool.Count)"
    } catch {
        Write-Warning "Category '$c' failed: $($_.Exception.Message)"
    }
}

if ($pool.Count -eq 0) { throw 'No images found. Check your internet connection, or drop your own 1920x1080 JPEGs into the wallpapers folder.' }

Get-ChildItem $dest -File -ErrorAction SilentlyContinue | Remove-Item -Force
$pick = $pool | Sort-Object { Get-Random } | Select-Object -First $Count
$credits = @()
$i = 0
foreach ($p in $pick) {
    $i++
    $file = Join-Path $dest ('nature{0:00}.jpg' -f $i)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $p.Url -Headers $ua -OutFile $file
        $kb = [int]((Get-Item $file).Length / 1024)
        Write-Host ("  {0}  {1} KB  {2}" -f (Split-Path $file -Leaf), $kb, $p.Title)
        $credits += ("{0}`t{1}`t{2}" -f (Split-Path $file -Leaf), $p.Title, $p.Page)
    } catch {
        Write-Warning "  skipped $($p.Title): $($_.Exception.Message)"
        if (Test-Path $file) { Remove-Item $file -Force }
    }
}
Set-Content -Path (Join-Path $Data 'wallpaper-credits.txt') -Value $credits

$n = @(Get-ChildItem $dest -Filter *.jpg).Count
Write-Host ''
Write-Host "$n wallpapers saved in $dest"
Write-Host 'Credits and licence pages: wallpaper-credits.txt in the same data folder. Licences vary per picture and personal use is fine.'
Write-Host 'To use your own pictures, put 1920x1080 JPEGs in that wallpapers folder and skip this script.'

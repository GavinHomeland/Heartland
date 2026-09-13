# ============================================================
# KSPrecipFetch.ps1 — measured rainfall from the Kansas Mesonet
#
# Writes daily precipitation totals (INCHES) for the trailing window to a
# small CSV that AirTempGraphGen.lua and RainBuckets.lua read.
#
# WHY THIS EXISTS
# Open-Meteo's past_days values are ARCHIVED FORECASTS, not observations.
# Scored against this gauge network over 60 days, the best_match model
# missed 8 of 12 rain days and under-reported the total by 1.58 in.
# Even ECMWF only gets the total roughly right. A real gauge wins for
# "what actually fell".
#
# WHY A WEIGHTED AVERAGE, NOT JUST THE NEAREST STATION
# Convective cells are smaller than the station spacing here, so any single
# gauge either shares your storm or misses it entirely. Leave-one-out
# cross-validation over 61 days x 7 stations:
#     method     wet-day MAE   wet-day bias   missed rain days
#     nearest       0.233         -0.064            32
#     idw p=1       0.186         -0.122            14
#     idw p=4       0.195         -0.087            17
#     idw p=6       0.205         -0.075            18
# Plain nearest-station has the least systematic under-statement but misses
# twice as many events. Low-power IDW catches events but dilutes local cells
# by averaging in distant zeros.
#
# Default p=6 is the compromise, checked against a real reading: on the
# 2026-09-12/13 overnight cell the Albert gauge caught 0.22 in, and the
# estimates were nearest 0.23, p=8 0.19, p=6 0.18, p=4 0.15 — while p=6 still
# cuts missed events from 32 to 18. Tune with -Power: raise it toward
# nearest-station behaviour (p=8 is nearly that), lower it to smooth more.
#
# UNITS: Mesonet reports PRECIP in MILLIMETRES (values are exact multiples of
# 0.254 mm = 0.01 in, a tipping bucket). Converted to inches here so every
# consumer downstream stays in inches, matching the Open-Meteo feeds.
#
# Today's row is a PARTIAL total: rain so far, through the last closed hour.
# Targets Windows PowerShell 5.1 (what Rainmeter's RunCommand launches).
# ============================================================

param(
    [double]$Lat         = 38.46,
    [double]$Lon         = -99.02,
    [double]$Power       = 6,
    [int]   $Stations    = 5,     # stations to combine
    [int]   $Days        = 8,
    [string]$OutCsv      = '',
    [string]$StatusTxt   = '',
    [string]$FetchLog    = '',
    [string]$MasterLog   = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$enc = [Text.UTF8Encoding]::new($false)
$MM_PER_IN = 25.4

function Write-Status {
    param([string]$Tag, [string]$Msg)
    $line = ('{0} {1} {2}' -f $Tag, (Get-Date -Format s), $Msg)
    if ($StatusTxt) { [IO.File]::WriteAllText($StatusTxt, $line, $enc) }
    foreach ($p in @($FetchLog, $MasterLog)) {
        if ($p) { [IO.File]::AppendAllText($p, $line + "`n", $enc) }
    }
    Write-Output $line
}

function Get-Miles {
    param([double]$La1, [double]$Lo1, [double]$La2, [double]$Lo2)
    $r = [Math]::PI / 180
    $c = [Math]::Sin($La1 * $r) * [Math]::Sin($La2 * $r) +
         [Math]::Cos($La1 * $r) * [Math]::Cos($La2 * $r) * [Math]::Cos(($Lo2 - $Lo1) * $r)
    if ($c -gt 1) { $c = 1 }
    if ($c -lt -1) { $c = -1 }
    return 3958.8 * [Math]::Acos($c)
}

function Invoke-Mesonet {
    param([string]$Url)
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -Headers @{
        'User-Agent' = 'Mozilla/5.0'
        'Accept'     = 'text/csv,*/*'
    }
    # The API answers malformed requests with a plain-text "Error: ..." body, not an HTTP error.
    if ($r.Content -match '^\s*Error:') {
        throw ('Mesonet rejected request: ' + (($r.Content -split "`n")[0]).Trim())
    }
    return $r.Content
}

try {
    $base = 'http://mesonet.k-state.edu/rest/stationdata/'

    # ---- Rank every station by distance (self-maintaining if the network changes)
    $names = Invoke-Mesonet 'http://mesonet.k-state.edu/rest/stationnames/' | ConvertFrom-Csv
    $ranked = $names |
        Where-Object { $_.LATITUDE -and $_.LONGITUDE } |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.NAME
                Dist = Get-Miles $Lat $Lon ([double]$_.LATITUDE) ([double]$_.LONGITUDE)
            }
        } |
        Sort-Object Dist

    $tEnd    = (Get-Date).Date.AddDays(1)
    $tStart  = $tEnd.AddDays(-$Days)
    $t_start = $tStart.ToString('yyyyMMdd') + '000000'
    $t_end   = $tEnd.ToString('yyyyMMdd')   + '000000'

    # ---- Seed the date buckets so quiet days still emit a 0.000 row
    $dates = @()
    for ($i = $Days - 1; $i -ge 0; $i--) { $dates += $tEnd.AddDays(-1 - $i).ToString('yyyy-MM-dd') }

    # ---- Walk outward until we have enough stations that actually report.
    # Several nearby sites (Great Bend, Radium, Rozel) return empty for PRECIP.
    $used = @()
    foreach ($st in $ranked) {
        if ($used.Count -ge $Stations) { break }
        if ($st.Dist -gt 60) { break }
        try {
            $url = $base + '?stn=' + [uri]::EscapeDataString($st.Name) +
                   '&int=day&t_start=' + $t_start + '&t_end=' + $t_end + '&vars=PRECIP'
            $rows = Invoke-Mesonet $url | ConvertFrom-Csv
            $vals = @{}
            foreach ($r in $rows) {
                if (-not $r.TIMESTAMP) { continue }
                $mm = 0.0
                if (-not [double]::TryParse($r.PRECIP, [ref]$mm)) { continue }
                $vals[([datetime]$r.TIMESTAMP).ToString('yyyy-MM-dd')] = $mm / $MM_PER_IN
            }
            if ($vals.Count -lt [Math]::Max(2, $Days - 2)) { continue }   # sparse/offline site
            $used += [pscustomobject]@{ Name = $st.Name; Dist = $st.Dist; Vals = $vals }
        } catch {
            continue   # station unavailable; try the next one out
        }
    }

    if ($used.Count -eq 0) { throw 'No Mesonet station returned usable PRECIP data.' }

    # ---- Inverse-distance-weighted combine, per day.
    # Weights are recomputed per day over only the stations reporting that day,
    # so a single offline site cannot drag the estimate toward zero.
    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('date,precipIn')
    $total = 0.0
    foreach ($d in $dates) {
        $num = 0.0; $den = 0.0
        foreach ($s in $used) {
            if (-not $s.Vals.ContainsKey($d)) { continue }
            $dist = [Math]::Max($s.Dist, 0.5)
            $w = 1.0 / [Math]::Pow($dist, $Power)
            $num += $w * $s.Vals[$d]
            $den += $w
        }
        $v = 0.0
        if ($den -gt 0) { $v = $num / $den }
        $total += $v
        # Double parens required: inside a method call the comma would otherwise be
        # read as an argument separator, starving -f of its second value.
        [void]$sb.AppendLine(('{0},{1:F3}' -f $d, $v))
    }

    [IO.File]::WriteAllText($OutCsv, $sb.ToString(), $enc)

    $desc = ($used | ForEach-Object { '{0}({1:F0}mi)' -f $_.Name, $_.Dist }) -join ' '
    Write-Status 'OK' ("p={0} total={1:F2}in stations={2} | {3}" -f $Power, $total, $used.Count, $desc)
}
catch {
    $msg = ($_.Exception.Message -replace '[\r\n]+', ' ' -replace '[^\x20-\x7E]', '?')
    Write-Status 'ERR' $msg
}

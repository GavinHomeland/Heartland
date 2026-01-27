# ============================
# Build-KS-Soil2in-7DayLowHistory.ps1
# Creates ks_soiltemp_2in_history.csv as:
#   date,tempF
# where tempF is the rolling 7-day minimum of Mesonet daily SOILTMP5MIN (5 cm ≈ 2"),
# converted from °C to °F.
# ============================

param(
  [Parameter(Mandatory=$true)] [string] $StationName,     # e.g. "Larned 6SW"
  [Parameter(Mandatory=$true)] [string] $OutCsvPath,      # e.g. E:\...\ks_soiltemp_2in_history.csv
  [int] $DaysOut = 45,
  [int] $DaysFetch = 60
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$enc = [Text.UTF8Encoding]::new($false)

function CtoF([double] $c) { return ($c * 9.0/5.0) + 32.0 }
function Invar([double] $n) { return $n.ToString([Globalization.CultureInfo]::InvariantCulture) }

# ---- Build Mesonet REST URL
$end   = Get-Date
$start = $end.AddDays(-$DaysFetch)

$t_start = $start.ToString('yyyyMMdd') + '000000'
$t_end   = $end.ToString('yyyyMMdd')   + '235959'

$base = 'https://mesonet.k-state.edu/rest/stationdata/'
$url  = $base + '?stn=' + [uri]::EscapeDataString($StationName) +
        '&int=day' +
        '&t_start=' + $t_start +
        '&t_end=' + $t_end +
        '&vars=SOILTMP5MIN'

Write-Host "Fetching: $url"

# ---- Fetch and parse CSV
$content = (Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{
  'User-Agent'='Mozilla/5.0'
  'Accept'='text/csv,*/*'
}).Content

# Quick sanity check: Mesonet returns error text in-body sometimes
if ($content -match '(?i)\berror\b' -and $content -notmatch 'TIMESTAMP') {
  throw "Mesonet returned an error response: $($content.Trim())"
}

$rows = $content | ConvertFrom-Csv
if (-not $rows -or $rows.Count -lt ($DaysOut + 7)) {
  throw "Too few daily rows returned: $($rows.Count). Increase DaysFetch or verify station."
}

# ---- date => daily minF (dedupe by date)
$map = @{}
foreach ($r in $rows) {
  $ts = $r.TIMESTAMP
  if (-not $ts) { continue }

  $date = $ts.Substring(0,10)  # yyyy-MM-dd

  $cStr = $r.SOILTMP5MIN
  if ($null -eq $cStr -or $cStr -eq '' -or $cStr -match '^(?i)(NA|NAN|null)$') { continue }

  $c = 0.0
  if (-not [double]::TryParse($cStr, [ref]$c)) { continue }

  $map[$date] = CtoF $c
}

$dates = $map.Keys | Sort-Object
if ($dates.Count -lt ($DaysOut + 7)) {
  throw "After filtering, not enough valid days: $($dates.Count)."
}

# ---- Rolling 7-day minimum
$roll = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $dates.Count; $i++) {
  if ($i -lt 6) { continue }

  $min = [double]::PositiveInfinity
  for ($j = $i - 6; $j -le $i; $j++) {
    $v = [double]$map[$dates[$j]]
    if ($v -lt $min) { $min = $v }
  }

  $roll.Add([pscustomobject]@{
    date  = $dates[$i]
    tempF = [Math]::Round($min, 2)
  }) | Out-Null
}

# ---- Keep last DaysOut and write exact CSV format: date,tempF
$out = $roll | Sort-Object date | Select-Object -Last $DaysOut

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('date,tempF') | Out-Null
foreach ($r in $out) {
  $lines.Add(($r.date + ',' + (Invar $r.tempF))) | Out-Null
}

[IO.File]::WriteAllText($OutCsvPath, ($lines -join "`r`n"), $enc)

Write-Host "OK wrote $($out.Count) rows to $OutCsvPath"

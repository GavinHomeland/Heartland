# =====================================================================
# Poll-OpenMeteoModelMeta.ps1
# Purpose:
#   Poll Open-Meteo model metadata endpoints on a fixed interval and log
#   results to a CSV for cadence / settle / correlation analysis.
#
# What it logs (per endpoint, per poll):
#   - availability/init/modification epoch + local timestamps
#   - update interval, temporal resolution, chunk length, data_end_time
#   - ok/http_status/error
#   - changed_avail (1 when last_run_availability_time advanced vs last seen)
#
# Stop: Ctrl+C
# =====================================================================

[CmdletBinding()]
param(
  [int]$IntervalSeconds = 300,  # 5 minutes
  [string]$OutCsv = ".\om_model_meta_log.csv",
  [string]$StateJson = ".\om_model_meta_state.json",
  [switch]$Once
)

# =========================
# Config: Location context
# =========================
$City = "Albert, KS"
$Lat  = 38.35889
$Lon  = -98.40119

# =========================
# Config: Endpoints to poll
# =========================
$Endpoints = @(
  @{ Name = "HRRR Conus 15min"; Url = "https://api.open-meteo.com/data/ncep_hrrr_conus_15min/static/meta.json" },
  @{ Name = "NBM Conus";        Url = "https://api.open-meteo.com/data/ncep_nbm_conus/static/meta.json" },
  @{ Name = "GFS 0.13";         Url = "https://api.open-meteo.com/data/ncep_gfs013/static/meta.json" },
  @{ Name = "GFS 0.25";         Url = "https://api.open-meteo.com/data/ncep_gfs025/static/meta.json" },
  @{ Name = "ECMWF IFS";        Url = "https://api.open-meteo.com/data/ecmwf_ifs/static/meta.json" },
  @{ Name = "ECMWF IFS 0.25 Ensemble"; Url = "https://ensemble-api.open-meteo.com/data/ecmwf_ifs025_ensemble/static/meta.json" }
)

# =========================
# Helpers
# =========================
function To-IsoLocal([object]$epochSeconds) {
  try {
    if ($null -eq $epochSeconds -or $epochSeconds -eq "") { return "" }
    $s = [int64]$epochSeconds
    return [DateTimeOffset]::FromUnixTimeSeconds($s).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
  } catch { return "" }
}

function Ensure-CsvHeader([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    $header = @(
      "polled_at_local",
      "polled_at_utc",
      "city",
      "lat",
      "lon",
      "endpoint_name",
      "url",
      "ok",
      "http_status",
      "changed_avail",
      "err",
      "chunk_time_length",
      "data_end_time",
      "data_end_local",
      "last_run_availability_time",
      "last_run_availability_local",
      "last_run_initialisation_time",
      "last_run_initialisation_local",
      "last_run_modification_time",
      "last_run_modification_local",
      "temporal_resolution_seconds",
      "update_interval_seconds",
      "crs_wkt_len"
    ) -join ","
    [IO.File]::WriteAllText($path, $header + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
  }
}

function CsvEscape([string]$s) {
  if ($null -eq $s) { return "" }
  if ($s -match '[,"\r\n]') { return '"' + ($s -replace '"','""') + '"' }
  return $s
}

function Append-CsvRow([string]$path, [hashtable]$row) {
  $cols = @(
    "polled_at_local","polled_at_utc","city","lat","lon","endpoint_name","url","ok","http_status","changed_avail","err",
    "chunk_time_length","data_end_time","data_end_local",
    "last_run_availability_time","last_run_availability_local",
    "last_run_initialisation_time","last_run_initialisation_local",
    "last_run_modification_time","last_run_modification_local",
    "temporal_resolution_seconds","update_interval_seconds","crs_wkt_len"
  )

  $vals = foreach ($c in $cols) {
    CsvEscape ([string]$row[$c])
  }

  Add-Content -LiteralPath $path -Encoding UTF8 -Value ($vals -join ",")
}

function Load-State([string]$path) {
  if (Test-Path -LiteralPath $path) {
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable) }
    catch { return @{} }
  }
  return @{}
}

function Save-State([string]$path, [hashtable]$state) {
  $json = ($state | ConvertTo-Json -Depth 6)
  [IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

# =========================
# Init
# =========================
Ensure-CsvHeader -path $OutCsv
$state = Load-State -path $StateJson

Write-Host "Logging CSV: $OutCsv"
Write-Host "State JSON:  $StateJson"
Write-Host "Interval:    $IntervalSeconds seconds"
Write-Host "Endpoints:   $($Endpoints.Count)"
Write-Host "Stop with Ctrl+C"
Write-Host ""

# =========================
# Poll loop
# =========================
do {
  $nowLocal = Get-Date
  $nowUtc   = (Get-Date).ToUniversalTime()

  foreach ($ep in $Endpoints) {
    $name = $ep.Name
    $url  = $ep.Url

    $row = @{
      polled_at_local = $nowLocal.ToString("yyyy-MM-dd HH:mm:ss")
      polled_at_utc   = $nowUtc.ToString("yyyy-MM-dd HH:mm:ss")
      city            = $City
      lat             = $Lat
      lon             = $Lon
      endpoint_name   = $name
      url             = $url
      ok              = 0
      http_status     = ""
      changed_avail   = 0
      err             = ""

      chunk_time_length = ""
      data_end_time     = ""
      data_end_local    = ""

      last_run_availability_time  = ""
      last_run_availability_local = ""
      last_run_initialisation_time  = ""
      last_run_initialisation_local = ""
      last_run_modification_time  = ""
      last_run_modification_local = ""

      temporal_resolution_seconds = ""
      update_interval_seconds     = ""
      crs_wkt_len                 = ""
    }

    try {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{
        "User-Agent" = "Mozilla/5.0"
        "Accept"     = "application/json"
      } -TimeoutSec 30

      $row.ok = 1
      $row.http_status = $resp.StatusCode

      $obj = $resp.Content | ConvertFrom-Json

      $row.chunk_time_length = $obj.chunk_time_length
      $row.data_end_time     = $obj.data_end_time
      $row.data_end_local    = To-IsoLocal $obj.data_end_time

      $avail = [int64]$obj.last_run_availability_time
      $init  = [int64]$obj.last_run_initialisation_time
      $mod   = [int64]$obj.last_run_modification_time

      $row.last_run_availability_time  = $avail
      $row.last_run_availability_local = To-IsoLocal $avail
      $row.last_run_initialisation_time  = $init
      $row.last_run_initialisation_local = To-IsoLocal $init
      $row.last_run_modification_time  = $mod
      $row.last_run_modification_local = To-IsoLocal $mod

      $row.temporal_resolution_seconds = $obj.temporal_resolution_seconds
      $row.update_interval_seconds     = $obj.update_interval_seconds

      if ($null -ne $obj.crs_wkt) { $row.crs_wkt_len = ([string]$obj.crs_wkt).Length }

      # Changed detection: availability time advanced vs last seen
      $key = $url  # stable key
      $prevAvail = 0
      if ($state.ContainsKey($key) -and $state[$key].ContainsKey("last_run_availability_time")) {
        $prevAvail = [int64]$state[$key]["last_run_availability_time"]
      }

      if ($avail -gt $prevAvail -and $prevAvail -ne 0) {
        $row.changed_avail = 1
      } else {
        $row.changed_avail = 0
      }

      # Update state
      $state[$key] = @{
        endpoint_name = $name
        last_run_availability_time   = $avail
        last_run_initialisation_time = $init
        last_run_modification_time   = $mod
        last_seen_polled_at_local    = $row.polled_at_local
      }

      Write-Host ("{0}  OK   {1,-24} avail={2}  changed={3}" -f $nowLocal.ToString("HH:mm:ss"), $name, $row.last_run_availability_local, $row.changed_avail)

    } catch {
      $row.ok = 0
      $row.err = $_.Exception.Message
      Write-Host ("{0}  ERR  {1,-24} {2}" -f $nowLocal.ToString("HH:mm:ss"), $name, $row.err)
    }

    Append-CsvRow -path $OutCsv -row $row
  }

  # Persist state after each full round
  Save-State -path $StateJson -state $state

  if (-not $Once) { Start-Sleep -Seconds $IntervalSeconds }
} while (-not $Once)

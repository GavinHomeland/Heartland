# NWSAlertsFetch.ps1
# Fetches active NWS CAP alerts for the given lat/lon.
# Strategy:
#   1. GET /points/lat,lon  → discover forecast zone, county zone, fire weather zone
#   2. GET /alerts/active?zone=zone1,zone2,...  (union with hardcoded NWSZones fallback)
#   3. GET /alerts/active?point=lat,lon  (supplement)
#   Union of steps 2+3 by alert ID, then map events → 27 boolean flags.
#   Falls back to ?area=NWSState if both return nothing.
# Uses Invoke-RestMethod (not Invoke-WebRequest) — IWR silently misparses NWS responses.
# Writes nws_alerts.json. Appends to NWSAlerts_log.txt and Heartland_log.txt.

param(
    [string]$NWSJson,
    [string]$NWSAlertsLog,
    [string]$HeartlandLog,
    [string]$Lat,
    [string]$Lon,
    [string]$NWSState = "KS",
    [string]$NWSZones = ""   # comma-separated zone codes always included (e.g. "KSZ047")
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$enc   = [System.Text.UTF8Encoding]::new($false)
$stamp = Get-Date -Format s
$hdrs  = @{ 'User-Agent' = 'Rainmeter-Heartland/1.0 (weather skin)'; 'Accept' = 'application/geo+json' }

function AppendLog {
    param([string]$path, [string]$msg)
    if ($path -and $path -ne '') {
        [IO.File]::AppendAllText($path, $msg + "`n", $enc)
    }
}

function WriteAlertJson {
    param([hashtable]$flags, [string]$path)
    $order = @(
        'TornadoWarning','TornadoWatch',
        'SevereThunderstormWarning','SevereThunderstormWatch',
        'FlashFloodWarning','FlashFloodWatch',
        'FireWeatherWatch','RedFlagWarning',
        'WinterStormWarning','WinterStormWatch',
        'IceStorm',
        'HighWind','WindAdvisory',
        'ExcessiveHeat','HeatAdvisory',
        'FreezeWarning','DenseFog','DustStorm',
        'FloodWarning','FloodWatch',
        'WinterWeatherAdvisory',
        'WindChillWarning','WindChillAdvisory',
        'FreezeWatch','HardFreezeWarning',
        'AirQualityAlert','DenseSmokeAdvisory'
    )
    $pairs = $order | ForEach-Object { '"' + $_ + '":' + $flags[$_] }
    $json  = '{' + ($pairs -join ',') + '}'
    [IO.File]::WriteAllText($path, $json, $enc)
    return $json
}

$flags = @{
    TornadoWarning            = 0; TornadoWatch              = 0
    SevereThunderstormWarning = 0; SevereThunderstormWatch   = 0
    FlashFloodWarning         = 0; FlashFloodWatch           = 0
    FireWeatherWatch          = 0; RedFlagWarning            = 0
    WinterStormWarning        = 0; WinterStormWatch          = 0
    IceStorm                  = 0
    HighWind                  = 0; WindAdvisory              = 0
    ExcessiveHeat             = 0; HeatAdvisory              = 0
    FreezeWarning             = 0; DenseFog                  = 0; DustStorm             = 0
    FloodWarning              = 0; FloodWatch                = 0
    WinterWeatherAdvisory     = 0
    WindChillWarning          = 0; WindChillAdvisory         = 0
    FreezeWatch               = 0; HardFreezeWarning         = 0
    AirQualityAlert           = 0; DenseSmokeAdvisory        = 0
}

AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | Start Lat=$Lat Lon=$Lon"
AppendLog $HeartlandLog  "$stamp | NWSAlertsFetch | Start Lat=$Lat Lon=$Lon"

function MapEvent {
    param([string]$e, [hashtable]$flags)
    if ($e -match 'Tornado Warning')                                  { $flags['TornadoWarning']            = 1 }
    if ($e -match 'Tornado Watch')                                    { $flags['TornadoWatch']              = 1 }
    if ($e -match 'Severe Thunderstorm Warning')                      { $flags['SevereThunderstormWarning'] = 1 }
    if ($e -match 'Severe Thunderstorm Watch')                        { $flags['SevereThunderstormWatch']   = 1 }
    if ($e -match 'Flash Flood Warning')                              { $flags['FlashFloodWarning']         = 1 }
    if ($e -match 'Flash Flood Watch')                                { $flags['FlashFloodWatch']           = 1 }
    if ($e -match 'Fire Weather Watch')                               { $flags['FireWeatherWatch']          = 1 }
    if ($e -match 'Red Flag Warning')                                 { $flags['RedFlagWarning']            = 1 }
    if ($e -match 'Winter Storm Warning|Blizzard Warning')            { $flags['WinterStormWarning']        = 1 }
    if ($e -match 'Winter Storm Watch')                               { $flags['WinterStormWatch']          = 1 }
    if ($e -match 'Ice Storm')                                        { $flags['IceStorm']                  = 1 }
    if ($e -match 'High Wind Warning')                                { $flags['HighWind']                  = 1 }
    if ($e -match 'Wind Advisory')                                    { $flags['WindAdvisory']              = 1 }
    if ($e -match 'Excessive Heat')                                   { $flags['ExcessiveHeat']             = 1 }
    if ($e -match 'Heat Advisory')                                    { $flags['HeatAdvisory']              = 1 }
    if ($e -match 'Freeze Warning|Frost Advisory')                    { $flags['FreezeWarning']             = 1 }
    if ($e -match 'Dense Fog')                                        { $flags['DenseFog']                  = 1 }
    if ($e -match 'Dust Storm|Blowing Dust')                          { $flags['DustStorm']                 = 1 }
    if ($e -match 'Flood Warning'    -and $e -notmatch 'Flash Flood') { $flags['FloodWarning']              = 1 }
    if ($e -match 'Flood Watch'      -and $e -notmatch 'Flash Flood') { $flags['FloodWatch']                = 1 }
    if ($e -match 'Winter Weather Advisory')                          { $flags['WinterWeatherAdvisory']     = 1 }
    if ($e -match 'Wind Chill Warning')                               { $flags['WindChillWarning']          = 1 }
    if ($e -match 'Wind Chill Advisory')                              { $flags['WindChillAdvisory']         = 1 }
    if ($e -match 'Freeze Watch')                                     { $flags['FreezeWatch']               = 1 }
    if ($e -match 'Hard Freeze Warning')                              { $flags['HardFreezeWarning']         = 1 }
    if ($e -match 'Air Quality Alert')                                { $flags['AirQualityAlert']           = 1 }
    if ($e -match 'Dense Smoke')                                      { $flags['DenseSmokeAdvisory']        = 1 }
}

try {
    # -----------------------------------------------------------------------
    # Step 1: Seed zones from hardcoded NWSZones, then supplement via /points
    # -----------------------------------------------------------------------
    $zones = @()
    if ($NWSZones -and $NWSZones -ne '') {
        foreach ($z in ($NWSZones -split ',')) {
            $z = $z.Trim()
            if ($z -and $zones -notcontains $z) { $zones += $z }
        }
        AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | Seeded zones: $($zones -join ',')"
    }

    try {
        $ptJson = Invoke-RestMethod -Uri "https://api.weather.gov/points/$Lat,$Lon" -Headers $hdrs -TimeoutSec 15
        $props  = $ptJson.properties
        foreach ($url in @($props.county, $props.forecastZone, $props.fireWeatherZone)) {
            if ($url) {
                $code = ($url -split '/')[-1]
                if ($code -and $zones -notcontains $code) { $zones += $code }
            }
        }
        AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | Zones after /points: $($zones -join ',')"
    } catch {
        $zmsg = $_.Exception.Message -replace '[\r\n]+',' '
        AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | /points lookup failed: $zmsg"
    }

    # -----------------------------------------------------------------------
    # Step 2+3: Zone query + point query, union by alert ID
    # -----------------------------------------------------------------------
    $seenIds   = @{}
    $features  = @()
    $eventList = @()

    if ($zones.Count -gt 0) {
        $zJson = Invoke-RestMethod -Uri "https://api.weather.gov/alerts/active?zone=$($zones -join ',')" -Headers $hdrs -TimeoutSec 20
        foreach ($f in $zJson.features) {
            if ($f.id -and -not $seenIds[$f.id]) {
                $seenIds[$f.id] = $true
                $features += $f
            }
        }
        AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | Zone query returned $($zJson.features.Count) features"
    }

    $pJson = Invoke-RestMethod -Uri "https://api.weather.gov/alerts/active?point=$Lat,$Lon" -Headers $hdrs -TimeoutSec 20
    foreach ($f in $pJson.features) {
        if ($f.id -and -not $seenIds[$f.id]) {
            $seenIds[$f.id] = $true
            $features += $f
        }
    }
    AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | Point query returned $($pJson.features.Count) features"

    # State fallback if both returned nothing
    if ($features.Count -eq 0 -and $NWSState -ne '') {
        $sJson = Invoke-RestMethod -Uri "https://api.weather.gov/alerts/active?area=$NWSState" -Headers $hdrs -TimeoutSec 20
        foreach ($f in $sJson.features) {
            if ($f.id -and -not $seenIds[$f.id]) {
                $seenIds[$f.id] = $true
                $features += $f
            }
        }
        AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | State fallback ($NWSState) returned $($sJson.features.Count) features"
    }

    # -----------------------------------------------------------------------
    # Map events → flags
    # -----------------------------------------------------------------------
    foreach ($f in $features) {
        $e = $f.properties.event
        if (-not $e) { continue }
        $eventList += $e
        MapEvent -e $e -flags $flags
    }

    $json   = WriteAlertJson -flags $flags -path $NWSJson
    $active = ($flags.Keys | Where-Object { $flags[$_] -eq 1 }) -join ','
    if (-not $active) { $active = 'none' }
    $events = $eventList -join '; '
    if (-not $events) { $events = '(none)' }

    $line = "$stamp | NWSAlertsFetch | OK total=$($features.Count) active=[$active] events=[$events]"
    AppendLog $NWSAlertsLog $line
    AppendLog $HeartlandLog  $line
    Write-Output $line

} catch {
    $msg  = $_.Exception.Message -replace '[\r\n]+', ' ' -replace '[^\x20-\x7E]', '?'
    $line = "$stamp | NWSAlertsFetch | ERR $msg"
    WriteAlertJson -flags $flags -path $NWSJson | Out-Null
    AppendLog $NWSAlertsLog $line
    AppendLog $HeartlandLog  $line
    Write-Output "NWS FETCH ERROR: $msg"
}

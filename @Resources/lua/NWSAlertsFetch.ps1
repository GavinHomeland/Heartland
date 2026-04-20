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
    [string]$NWSZones  = "",  # comma-separated zone codes always included (e.g. "KSZ047")
    [string]$GeoFilter = ""   # comma-separated towns/counties; if set, alerts whose description
                              # matches none of these terms are skipped
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
    param([string]$e)
    $keys = [System.Collections.Generic.List[string]]::new()
    if ($e -match 'Tornado Warning')                                  { $keys.Add('TornadoWarning') }
    if ($e -match 'Tornado Watch')                                    { $keys.Add('TornadoWatch') }
    if ($e -match 'Severe Thunderstorm Warning')                      { $keys.Add('SevereThunderstormWarning') }
    if ($e -match 'Severe Thunderstorm Watch')                        { $keys.Add('SevereThunderstormWatch') }
    if ($e -match 'Flash Flood Warning')                              { $keys.Add('FlashFloodWarning') }
    if ($e -match 'Flash Flood Watch')                                { $keys.Add('FlashFloodWatch') }
    if ($e -match 'Fire Weather Watch')                               { $keys.Add('FireWeatherWatch') }
    if ($e -match 'Red Flag Warning')                                 { $keys.Add('RedFlagWarning') }
    if ($e -match 'Winter Storm Warning|Blizzard Warning')            { $keys.Add('WinterStormWarning') }
    if ($e -match 'Winter Storm Watch')                               { $keys.Add('WinterStormWatch') }
    if ($e -match 'Ice Storm')                                        { $keys.Add('IceStorm') }
    if ($e -match 'High Wind Warning')                                { $keys.Add('HighWind') }
    if ($e -match 'Wind Advisory')                                    { $keys.Add('WindAdvisory') }
    if ($e -match 'Excessive Heat')                                   { $keys.Add('ExcessiveHeat') }
    if ($e -match 'Heat Advisory')                                    { $keys.Add('HeatAdvisory') }
    if ($e -match 'Freeze Warning|Frost Advisory')                    { $keys.Add('FreezeWarning') }
    if ($e -match 'Dense Fog')                                        { $keys.Add('DenseFog') }
    if ($e -match 'Dust Storm|Blowing Dust')                          { $keys.Add('DustStorm') }
    if ($e -match 'Flood Warning'    -and $e -notmatch 'Flash Flood') { $keys.Add('FloodWarning') }
    if ($e -match 'Flood Watch'      -and $e -notmatch 'Flash Flood') { $keys.Add('FloodWatch') }
    if ($e -match 'Winter Weather Advisory')                          { $keys.Add('WinterWeatherAdvisory') }
    if ($e -match 'Wind Chill Warning')                               { $keys.Add('WindChillWarning') }
    if ($e -match 'Wind Chill Advisory')                              { $keys.Add('WindChillAdvisory') }
    if ($e -match 'Freeze Watch')                                     { $keys.Add('FreezeWatch') }
    if ($e -match 'Hard Freeze Warning')                              { $keys.Add('HardFreezeWarning') }
    if ($e -match 'Air Quality Alert')                                { $keys.Add('AirQualityAlert') }
    if ($e -match 'Dense Smoke')                                      { $keys.Add('DenseSmokeAdvisory') }
    return $keys
}

# Build geo-filter term list (once, before the try block)
$geoTerms = @()
if ($GeoFilter -and $GeoFilter -ne '') {
    foreach ($t in ($GeoFilter -split ',')) {
        $t = $t.Trim()
        if ($t) { $geoTerms += $t }
    }
}

function MatchesGeoFilter {
    param([string]$description, [string]$headline)
    # If no filter configured, everything passes
    if ($geoTerms.Count -eq 0) { return $true }
    # Match against description first, then headline
    $text = ($description + ' ' + $headline).ToLower()
    foreach ($term in $geoTerms) {
        if ($text -match [regex]::Escape($term.ToLower())) { return $true }
    }
    return $false
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
    $details   = @{}

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
    # Map events → flags + collect per-key details (first feature wins)
    # -----------------------------------------------------------------------
    foreach ($f in $features) {
        $e = $f.properties.event
        if (-not $e) { continue }

        # Geographic filter: skip alerts that don't mention a local town/county
        $rawDescForFilter = if ($f.properties.description) { $f.properties.description } else { '' }
        $headlineForFilter = if ($f.properties.headline)    { $f.properties.headline }    else { '' }
        if (-not (MatchesGeoFilter -description $rawDescForFilter -headline $headlineForFilter)) {
            AppendLog $NWSAlertsLog "$stamp | NWSAlertsFetch | GeoFilter skip: $e"
            continue
        }

        $eventList += $e

        $keys = MapEvent -e $e
        foreach ($k in $keys) { $flags[$k] = 1 }

        # Build expiry string: prefer ends over expires
        $expRaw = if ($f.properties.ends) { $f.properties.ends } else { $f.properties.expires }
        $expFmt = ''
        if ($expRaw) {
            try { $expFmt = [DateTimeOffset]::Parse($expRaw).ToLocalTime().ToString("ddd M/d h:mmtt") }
            catch { $expFmt = $expRaw }
        }

        # Full description: collapse intra-paragraph newlines, keep paragraph breaks as \n
        $descJson = ''
        $rawDesc  = $f.properties.description
        if ($rawDesc) {
            $paras = $rawDesc -split '\r?\n\r?\n'
            $formatted = ($paras | ForEach-Object {
                ($_ -replace '[\r\n]+', ' ' -replace '\s+', ' ').Trim()
            } | Where-Object { $_ -ne '' }) -join "`n"
            # Strip chars unsafe for a JSON string value (quotes; backslashes escaped)
            $formatted = $formatted -replace '"', "'"
            $formatted = $formatted -replace '\\', '\\\\'
            if ($formatted.Length -gt 2000) { $formatted = $formatted.Substring(0, 1997) + '...' }
            # Encode actual newlines as JSON \n escape sequences
            $descJson = $formatted.Trim() -replace "`n", '\n'
        }

        $eEsc = $e      -replace '[\\"]', ''
        $xEsc = $expFmt -replace '[\\"]', ''

        foreach ($k in $keys) {
            if (-not $details.ContainsKey($k)) {
                $details[$k] = '{"event":"' + $eEsc + '","exp":"' + $xEsc + '","desc":"' + $descJson + '"}'
            }
        }
    }

    # Write details JSON (empty object if no active alerts)
    $NWSDetailsJson = [IO.Path]::Combine([IO.Path]::GetDirectoryName($NWSJson), 'nws_alert_details.json')
    $detailPairs    = $details.Keys | ForEach-Object { '"' + $_ + '":' + $details[$_] }
    [IO.File]::WriteAllText($NWSDetailsJson, '{' + ($detailPairs -join ',') + '}', $enc)

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

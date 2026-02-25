# ============================
# KSSoilMasterFetch.ps1
# Downloads Mesonet daily soil data and writes:
# - Raw CSV (as downloaded)
# - Master CSV: date,avgF,minF (last MasterDays)
# - Rolling CSV: date,min7F,avg7F (last RollingDays; 7-day window)
# - LastAttemptTxt: OK/ERR/PROBE timestamp + message  (overwrites, single line)
# - FetchLog:       appending per-run log
# - MasterLog:      appending master Heartland log
# ============================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Station,

    [int]$MasterDays = 180,
    [int]$RollingDays = 45,

    [Parameter(Mandatory = $true)]
    [string]$MasterCsv,

    [Parameter(Mandatory = $true)]
    [string]$RollingCsv,

    [string]$RawCsv = "",

    [Parameter(Mandatory = $true)]
    [string]$LastAttemptTxt,

    [string]$FetchLog  = "",   # appending per-file log
    [string]$MasterLog = ""    # appending master Heartland log
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- UTF-8 (no BOM) output
$enc = [System.Text.UTF8Encoding]::new($false)

function Write-TextFileUtf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# Write status (overwrites) and append to both logs
function Write-Status([string]$Status, [string]$Message) {
    $stamp = (Get-Date -Format s)
    $line  = "{0} {1} {2}" -f $Status, $stamp, $Message
    Write-TextFileUtf8NoBom $LastAttemptTxt $line
    if ($FetchLog)  { Add-Content -LiteralPath $FetchLog  -Value $line -Encoding UTF8 }
    if ($MasterLog) { Add-Content -LiteralPath $MasterLog -Value $line -Encoding UTF8 }
}

function Convert-CtoF([double]$C) {
    return ($C * 9.0 / 5.0) + 32.0
}

function Get-DoubleOrNull([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try {
        return [double]::Parse($s, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

# --- Optional "I ran" marker
try {
    $ranPath = Join-Path (Split-Path -Parent $LastAttemptTxt) 'ks_soiltemp_ps_ran.txt'
    Add-Content -LiteralPath $ranPath ("RAN " + (Get-Date -Format s))
} catch { }

# --- PAUSE FLAG -----------------------------------------------------------
try {
    $pausePath = Join-Path (Split-Path -Parent $RollingCsv) 'KSSoil_PAUSE.txt'
    if (Test-Path -LiteralPath $pausePath) {
        Write-Status 'PAUSED' ("Pause flag present: {0}" -f $pausePath)
        exit 0
    }
} catch { }

# --- PROBE: already succeeded today? (safety check; gate should prevent this normally)
$today = Get-Date -Format "yyyy-MM-dd"
if (Test-Path $LastAttemptTxt) {
    $lastContent = Get-Content $LastAttemptTxt -Raw
    if ($lastContent -match "^OK" -and $lastContent -match $today) {
        Write-Status 'PROBE' "Already succeeded today ($today). Skipping fetch."
        Write-Output "PROBE: Already succeeded today. Skipping."
        exit 0
    }
}

# --- Main fetch
try {
    # ---- Compute fetch window
    $needDays  = [Math]::Max($MasterDays, ($RollingDays + 6))
    $fetchDays = $needDays + 7

    $tEnd   = (Get-Date).Date.AddDays(1)
    $tStart = $tEnd.AddDays(-$fetchDays)

    $t_start = $tStart.ToString('yyyyMMdd') + '000000'
    $t_end   = $tEnd.ToString('yyyyMMdd')   + '000000'

    $base = 'http://mesonet.k-state.edu/rest/stationdata/'
    $vars = 'SOILTMP5AVG,SOILTMP5MIN'

    $url = $base + '?stn=' + [uri]::EscapeDataString($Station) +
          '&int=day&t_start=' + $t_start + '&t_end=' + $t_end + '&vars=' + $vars

    # ---- Raw file path default
    if ([string]::IsNullOrWhiteSpace($RawCsv)) {
        $root   = Split-Path -Parent $MasterCsv
        $RawCsv = Join-Path $root 'DownloadFile\ks_soiltemp_2in_raw.csv'
    }

    $rawDir = Split-Path -Parent $RawCsv
    if ($rawDir -and -not (Test-Path -LiteralPath $rawDir)) {
        New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
    }

    # ---- Download raw
    Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $RawCsv -Headers @{
        'User-Agent' = 'Mozilla/5.0'
        'Accept'     = 'text/csv,*/*'
    } | Out-Null

    if (-not (Test-Path -LiteralPath $RawCsv) -or (Get-Item $RawCsv).Length -lt 100) {
        throw "Downloaded CSV is missing or too small."
    }

    $raw = Import-Csv -LiteralPath $RawCsv

    # ---- Normalize rows -> Date, AvgF, MinF
    $rows = $raw |
        Where-Object { $_.TIMESTAMP } |
        ForEach-Object {
            $dt   = [datetime]$_.TIMESTAMP
            $avgC = Get-DoubleOrNull $_.SOILTMP5AVG
            $minC = Get-DoubleOrNull $_.SOILTMP5MIN
            if ($null -eq $avgC -or $null -eq $minC) { return }
            [pscustomobject]@{
                Date = $dt.Date
                AvgF = Convert-CtoF $avgC
                MinF = Convert-CtoF $minC
            }
        } |
        Sort-Object Date

    if (-not $rows -or $rows.Count -lt 10) {
        throw "Not enough parsed rows from CSV."
    }

    # ---- MASTER: last MasterDays rows
    $master = $rows | Select-Object -Last $MasterDays

    $masterLines = New-Object System.Collections.Generic.List[string]
    $masterLines.Add('date,avgF,minF') | Out-Null
    foreach ($r in $master) {
        $masterLines.Add((
            '{0},{1},{2}' -f
            $r.Date.ToString('yyyy-MM-dd'),
            ([math]::Round($r.AvgF,2)).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture),
            ([math]::Round($r.MinF,2)).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
        )) | Out-Null
    }
    Write-TextFileUtf8NoBom $MasterCsv ($masterLines -join "`n")

    # ---- ROLLING: compute 7-day window, then take last RollingDays
    $rollAll = New-Object System.Collections.Generic.List[object]
    for ($i = 6; $i -lt $master.Count; $i++) {
        $win  = $master[($i-6)..$i]
        $min7 = ($win | Measure-Object -Property MinF -Minimum).Minimum
        $avg7 = ($win | Measure-Object -Property AvgF -Average).Average
        $rollAll.Add([pscustomobject]@{
            Date  = $master[$i].Date
            Min7F = [math]::Round($min7, 2)
            Avg7F = [math]::Round($avg7, 2)
        }) | Out-Null
    }

    $roll = $rollAll | Select-Object -Last $RollingDays

    $rollLines = New-Object System.Collections.Generic.List[string]
    $rollLines.Add('date,min7F,avg7F') | Out-Null
    foreach ($r in $roll) {
        $rollLines.Add((
            '{0},{1},{2}' -f
            $r.Date.ToString('yyyy-MM-dd'),
            $r.Min7F.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture),
            $r.Avg7F.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
        )) | Out-Null
    }
    Write-TextFileUtf8NoBom $RollingCsv ($rollLines -join "`n")

    Write-Status 'OK' ("master={0} rolling={1} rows={2}" -f $MasterCsv, $RollingCsv, $rows.Count)
    Write-Output "OK: KSSoilMasterFetch complete. Rows=$($rows.Count)"

} catch {
    $msg = $_.Exception.Message
    $msg = ($msg -replace '[\r\n]+',' ' -replace '[^\x20-\x7E]','?')
    try { Write-Status 'ERR' $msg } catch { }
    throw
}

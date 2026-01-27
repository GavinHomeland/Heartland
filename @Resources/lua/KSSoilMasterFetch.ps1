<#
============================================================
KSSoilDailyBuild.ps1
Kansas Mesonet (stationdata) daily soil temps at 5cm (~2")
- Downloads N days of daily data (avg + min)
- Writes MASTER CSV: date,avgF,minF
- Writes ROLLING CSV: date,min7F,avg7F
  * min7F = rolling 7-day minimum of daily minF
  * avg7F = rolling 7-day average of daily avgF
- Keeps only last RollingDays points in rolling file
- Writes last-attempt/status TXT (optional)

UTF-8 (no BOM).
============================================================
#>
Add-Content -LiteralPath "$PSScriptRoot\..\..\ks_soiltemp_ps_ran.txt" ("RAN " + (Get-Date -Format s))

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Station,

    [int]$MasterDays = 180,
    [int]$RollingDays = 45,

    [Parameter(Mandatory=$true)]
    [string]$MasterCsv,

    [Parameter(Mandatory=$true)]
    [string]$RollingCsv,

    [string]$RawCsv = "",
    [string]$LastAttemptTxt = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $Utf8NoBom

function Ensure-Dir([string]$path){
    $d = [IO.Path]::GetDirectoryName($path)
    if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function CToF([double]$c){ return ($c * 9.0 / 5.0) + 32.0 }

function Write-Status([string]$msg){
    if ([string]::IsNullOrWhiteSpace($LastAttemptTxt)) { return }
    Ensure-Dir $LastAttemptTxt
    [IO.File]::WriteAllText($LastAttemptTxt, $msg + "`r`n", $Utf8NoBom)
}

try {
    Ensure-Dir $MasterCsv
    Ensure-Dir $RollingCsv
    if ($RawCsv) { Ensure-Dir $RawCsv }

    # ---- Build proven Mesonet URL (concat to avoid "$base?stn" interpolation bug)
    $base = 'http://mesonet.k-state.edu/rest/stationdata/'
    $tEnd   = (Get-Date).Date.AddDays(1)  # tomorrow 00:00
    $tStart = $tEnd.AddDays(-[math]::Abs($MasterDays))
    $t_start = $tStart.ToString('yyyyMMdd') + '000000'
    $t_end   = $tEnd.ToString('yyyyMMdd') + '000000'
    $vars = 'SOILTMP5AVG,SOILTMP5MIN'

    $url =
        $base +
        '?stn='     + [uri]::EscapeDataString($Station) +
        '&int=day' +
        '&t_start=' + $t_start +
        '&t_end='   + $t_end +
        '&vars='    + $vars

    Write-Status ("TRY {0} station={1} days={2} url={3}" -f (Get-Date -Format s), $Station, $MasterDays, $url)

    # ---- Download
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{
        'User-Agent' = 'Mozilla/5.0'
        'Accept'     = 'text/csv,*/*'
    }

    $csvText = $resp.Content
    if ([string]::IsNullOrWhiteSpace($csvText) -or $csvText.Length -lt 50) {
        throw "Download returned empty/short content (len=$($csvText.Length))."
    }

    if ($RawCsv) {
        [IO.File]::WriteAllText($RawCsv, $csvText, $Utf8NoBom)
    }

    # ---- Parse CSV to objects
    $rows = $csvText | ConvertFrom-Csv
    if (-not $rows -or $rows.Count -lt 1) {
        throw "CSV parsed to zero rows."
    }

    # ---- MASTER: date,avgF,minF
    $master = foreach ($r in $rows) {
        $ts = [string]$r.TIMESTAMP
        if ([string]::IsNullOrWhiteSpace($ts) -or $ts.Length -lt 10) { continue }

        $date = $ts.Substring(0,10)

        $avgC = $null
        $minC = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$r.SOILTMP5AVG)) { $avgC = [double]$r.SOILTMP5AVG }
        if (-not [string]::IsNullOrWhiteSpace([string]$r.SOILTMP5MIN)) { $minC = [double]$r.SOILTMP5MIN }
        if ($avgC -eq $null -and $minC -eq $null) { continue }

        [pscustomobject]@{
            date = $date
            avgF = if ($avgC -ne $null) { [math]::Round((CToF $avgC), 2) } else { $null }
            minF = if ($minC -ne $null) { [math]::Round((CToF $minC), 2) } else { $null }
        }
    } | Sort-Object date

    if (-not $master -or $master.Count -lt 1) {
        throw "No usable rows after parsing."
    }

    $masterLines = New-Object System.Collections.Generic.List[string]
    $masterLines.Add('date,avgF,minF')
    foreach ($m in $master) {
        $a = if ($null -ne $m.avgF) { '{0:N2}' -f $m.avgF } else { '' }
        $n = if ($null -ne $m.minF) { '{0:N2}' -f $m.minF } else { '' }
        $masterLines.Add(("{0},{1},{2}" -f $m.date, $a, $n))
    }
    [IO.File]::WriteAllText($MasterCsv, ($masterLines -join "`r`n") + "`r`n", $Utf8NoBom)

    # ---- ROLLING: date,min7F,avg7F computed over the trailing 7-day window
    $rollingAll = New-Object System.Collections.Generic.List[object]

    for ($i=6; $i -lt $master.Count; $i++) {
        $window = $master[($i-6)..$i]

        $minWindow = $window | Where-Object { $null -ne $_.minF }
        $avgWindow = $window | Where-Object { $null -ne $_.avgF }

        if (-not $minWindow -or -not $avgWindow) { continue }

        $min7 = ($minWindow | Measure-Object -Property minF -Minimum).Minimum
        $avg7 = ($avgWindow | Measure-Object -Property avgF -Average).Average

        $rollingAll.Add([pscustomobject]@{
            date  = $master[$i].date
            min7F = [math]::Round($min7, 2)
            avg7F = [math]::Round($avg7, 2)
        })
    }

    $rolling = if ($rollingAll.Count -gt $RollingDays) {
        $rollingAll | Select-Object -Last $RollingDays
    } else {
        $rollingAll
    }

    $rollLines = New-Object System.Collections.Generic.List[string]
    $rollLines.Add('date,min7F,avg7F')
    foreach ($r in $rolling) {
        $rollLines.Add(("{0},{1:N2},{2:N2}" -f $r.date, $r.min7F, $r.avg7F))
    }
    [IO.File]::WriteAllText($RollingCsv, ($rollLines -join "`r`n") + "`r`n", $Utf8NoBom)

    $lastDate = if ($rolling.Count -gt 0) { $rolling[-1].date } else { '' }
    Write-Status ("OK {0} station={1} bytes={2} masterRows={3} rollRows={4} last={5}" -f (Get-Date -Format s), $Station, $csvText.Length, $master.Count, $rolling.Count, $lastDate)

    "OK station=$Station bytes=$($csvText.Length) masterRows=$($master.Count) rollRows=$($rolling.Count) last=$lastDate"
}
catch {
    $msg = $_.Exception.Message
    Write-Status ("ERR {0} {1} station={2}" -f (Get-Date -Format s), $msg, $Station)
    throw
}

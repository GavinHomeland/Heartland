; =================
; Heartland Weather.ini 
; Open-Meteo -> PowerShell fetch -> local files -> Rainmeter WebParser parses local files
; Debug-first build (shows *actual* paths / file URLs / status / JSON head on the panel)
; =================

[Rainmeter]
Update=100
AccurateText=1
DynamicWindowSize=0
Debug=2
OnRefreshAction=[!UpdateMeasure MeasureCurPathSlash][!CommandMeasure MeasureOM_FetchPS "Run"]

; =================
; [Metadata]
; NOTE: Rainmeter does NOT expand variables inside [Metadata]. Keep this static.
; =================
[Metadata]
Name=Heartland Weather
Author=Chauncy
Information=Standalone Open-Meteo weather panel for Kansas.
Version=See Panel

; =================
; [Variables] ========================
; =================
[Variables]
; -----------------
; PANEL / LAYOUT
; -----------------
W=620
H=490
Pad=16
Round=14
;Icon Row
IconRowY=280
;Baroms, Humidity Dials
DialRowX=#Pad#
DialRowY=330
DialSpacing=65
; The size of your square PNGs
DialBaseSize=60
; Use these to position the whole row easily
DialStartX=#Pad#
DialStartY=350
DialSpacing=65
SkinVersion=7.2e

; -----------------
; LOCATION (Open-Meteo)
; -----------------
City=Albert, KS
Lat=38.35889
Lon=-98.40119
Timezone=auto

; -----------------
; OPEN-METEO DOT (health indicator)
; -----------------
OMDotColor=255,0,0,230

; -----------------
; WIND ARROW — scaling knobs
; -----------------
WindArrowBaseSize=13
WindArrowScaleFactor=2.0
WindArrowGlobalScale=0.8
; ---------------------

; -----------------
; OPEN-METEO FILE PATHS
; -----------------
OM_JSON=#CURRENTPATH#om.json
OM_STATUS=#CURRENTPATH#om_status.txt
OM_QUERY_TXT=#CURRENTPATH#OM_Query.txt
OM_LastFetch=0

; -----------------
; OPEN-METEO REQUEST BUILDER (edit these chunks)
; -----------------
OM_BASE=https://api.open-meteo.com/v1/forecast
OM_LOC=latitude=#Lat#&longitude=#Lon#
OM_MISC=timezone=#Timezone#&temperature_unit=fahrenheit&wind_speed_unit=mph
OM_HOURLY_PRESS=pressure_msl,surface_pressure
OM_HOURLY=hourly=#OM_HOURLY_PRESS#
OM_PAST=past_days=1
OM_CUR_AIR=temperature_2m,apparent_temperature,relative_humidity_2m,pressure_msl,visibility
OM_CUR_SKY=weather_code
OM_CUR_WIND=wind_speed_10m,wind_direction_10m,wind_gusts_10m
OM_CURRENT=current=#OM_CUR_AIR#,#OM_CUR_SKY#,#OM_CUR_WIND#
OM_DAILY=daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code
OM_QUERY=#OM_LOC#&#OM_MISC#&#OM_CURRENT#&#OM_DAILY#&#OM_HOURLY#&#OM_PAST#
OM_URL=#OM_BASE#?#OM_QUERY#

; Runtime variable populated by [MeasureCurPathSlash]
CurPathSlash=

; -----------------
; KS SOIL TEMP (2") — PS1 PIPELINE
; -----------------
KSSoilStation=Larned 6SW
KSSoilMasterDays=180
KSSoilRollingDays=45
KSSoilRunAfterHour=12

; ===============================
; KS SOIL TEMP (2") — PS1 PIPELINE + UI
; ===============================

; PS1 script path
KSSoilPS1=#@#Lua\KSSoilMasterFetch.ps1

; Output files (written by PS1)
KSSoilMasterCsv=#CURRENTPATH#ks_soiltemp_2in_master.csv
KSSoilRollingCsv=#CURRENTPATH#ks_soiltemp_2in_rolling7day.csv
KSSoilLastAttemptTxt=#CURRENTPATH#ks_soiltemp_2in_last_attempt.txt

; Raw download (optional, kept for debugging / archival)
KSSoilRawName=ks_soiltemp_2in_raw.csv
KSSoilRawCsv=#CURRENTPATH#DownloadFile\#KSSoilRawName#

; Scheduler lock (prevents dupes / supports watchdog)
KSSoilIsRunning=0
KSSoilLockStartMin=0
KSSoilLockTimeoutMin=5

; -----------------
; SOIL DOT (health indicator)
; -----------------
SoilDotColor=255,0,0,150

; -----------------
; SOIL GRAPH (reads rolling CSV: date,min7F,avg7F)
; -----------------
SoilHistCsv=#KSSoilRollingCsv#
SoilLastAttemptFile=#CURRENTPATH#ks_soiltemp_2in_last_attempt.txt

; 2 = min7F, 3 = avg7F
SoilGraphCol=2

; NOTE: requires KSSoilRollingDays to be defined earlier in [Variables]
SoilGraphDays=#KSSoilRollingDays#

SoilGraphBarW=4
SoilGraphBarGap=0
SoilGraphH=100

SoilGraphMinF=25
SoilGraphMaxF=100

; Right-justified inside background padding
SoilGraphX=(#W# - #Pad# - ((#SoilGraphDays# * #SoilGraphBarW#) + ((#SoilGraphDays# - 1) * #SoilGraphBarGap#)))
SoilGraphY=130

GitRepoPath=E:\Documents\Rainmeter\Skins\Heartland
GitPushPS1=#@#lua\GitPush.ps1
GitLastStatus=Git: idle

; =================
; OM DATA
; =================
; This section performs initialization and data retrieval.
; Do not modify this logic.
[MeasureCurPathSlash]
Measure=String
UpdateDivider=-1
String=#CURRENTPATH#
Substitute="\\":"/"
DynamicVariables=1
OnUpdateAction=[!SetVariable CurPathSlash "[MeasureCurPathSlash]"]

; =================
; MeasureOM_FetchPS — uses OM_URL + writes OM_Query.txt + writes om.json in skin folder
; =================
[MeasureOM_FetchPS]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
UpdateDivider=-1
DynamicVariables=1
State=Hide
Parameter=-NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $u='#OM_URL#'; $q='#OM_QUERY_TXT#'; $p='#OM_JSON#'; $s='#OM_STATUS#'; $enc=[Text.UTF8Encoding]::new($false); try { [IO.File]::WriteAllText($q,$u,$enc); $resp=Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{ 'User-Agent'='Mozilla/5.0'; 'Accept'='application/json' }; $j=$resp.Content; [IO.File]::WriteAllText($p,$j,$enc); $head=$j.Substring(0,[Math]::Min(160,$j.Length)); $head=($head -replace '[\r\n]+',' ' -replace '[^\x20-\x7E]','?'); $okJson=$true; try { $null=$j | ConvertFrom-Json } catch { $okJson=$false }; $code=$resp.StatusCode; $ct=$resp.Headers['Content-Type']; $final=''; try { $final=$resp.BaseResponse.ResponseUri.AbsoluteUri } catch { $final='' }; $line=('OK {0} code={1} ct={2} json={3} len={4} jsonPath={5} statusPath={6} finalUrl={7} head={8}' -f (Get-Date -Format s),$code,$ct,$okJson,$j.Length,$p,$s,$final,$head); [IO.File]::WriteAllText($s,$line,$enc); Write-Output $head; } catch { $stamp=(Get-Date -Format s); $msg=$_.Exception.Message; $msg=($msg -replace '[\r\n]+',' ' -replace '[^\x20-\x7E]','?'); $line=('ERR {0} {1} url={2} jsonPath={3} statusPath={4}' -f $stamp,$msg,$u,$p,$s); [IO.File]::WriteAllText($s,$line,$enc); Write-Output ('FETCH ERROR: '+$msg); }"
FinishAction=[!UpdateMeasure MeasureOM_File][!UpdateMeasure MeasureOM_Status][!UpdateMeasure MeasureOM_OkErr][!UpdateMeasureGroup OMParse][!UpdateMeterGroup OM][!CommandMeasure MeasureKSSoil_BuildPS "Run"][!Log "OM_Fetch triggered" "Notice"]

[MeasureOM_Status]
Measure=Plugin
Plugin=WebParser
Group=OMParent
DynamicVariables=1
URL=file:///#CurPathSlash#om_status.txt
RegExp=(?si)\A(.*)\z
StringIndex=1
Download=0
ForceReload=1
CodePage=65001
UpdateDivider=-1
UpdateRate=1

[MeasureOM_File]
Measure=Plugin
Plugin=WebParser
Group=OMParent
DynamicVariables=1
URL=file:///#CurPathSlash#om.json
RegExp=(?si)\A(.*)\z
StringIndex=1
Download=0
ForceReload=1
CodePage=65001
UpdateDivider=-1
UpdateRate=1

[MeasureUptime]
Measure=Calc
UpdateDivider=1
Formula=(MeasureUptime + 1)
DynamicVariables=1

; [MeasureSecondsOfDay]
; Measure=Time
; Format=%H%M%S
; UpdateDivider=1
; DynamicVariables=1

[MeasureMinute]
Measure=Time
Format=%M
UpdateDivider=60

[MeasureAutoFetch]
Measure=Calc
Formula=([MeasureMinute] % 10)
IfCondition=([MeasureAutoFetch] = 0)
IfTrueAction=[!CommandMeasure MeasureOM_FetchPS "Run"]
UpdateDivider=1
DynamicVariables=1

; ============================
; KS SOIL TEMP DAILY CSV PIPELINE (PS1-driven) — minimal + correct
; - Gate: once/day after #KSSoilRunAfterHour#
; - Lock: prevents overlap
; - Watchdog: clears stuck lock (minutes-based, no %s)
; ============================

; Read last attempt date (OK or ERR) from last_attempt.txt -> YYYYMMDD (string)
[MeasureKSSoilLastAttemptYMD]
Measure=Plugin
Plugin=WebParser
DynamicVariables=1
URL=file:///#CurPathSlash#ks_soiltemp_2in_last_attempt.txt
RegExp=(?si)\b(?:OK|ERR)\s+(\d{4}-\d{2}-\d{2})
StringIndex=1
Substitute="-":""
ForceReload=1
CodePage=65001
UpdateDivider=300

; Coerce to numeric (blank -> 0)
[MeasureKSSoilLastAttemptYMDNum]
Measure=Calc
DynamicVariables=1
UpdateDivider=300
Formula=([MeasureKSSoilLastAttemptYMD] + 0)

; Today as YYYYMMDD
[MeasureKSSoilTodayYMD]
Measure=Time
Format=%Y%m%d
UpdateDivider=300

; Time as HHMM
[MeasureKSSoilTimeHM]
Measure=Time
Format=%H%M
UpdateDivider=300

; Lock exposed as numeric (variable -> number)
[MeasureKSSoilLock]
Measure=Calc
DynamicVariables=1
UpdateDivider=60
Formula=(#KSSoilIsRunning# + 0)

; Minutes since midnight (0..1439) for watchdog timing (no epoch)
[MeasureKSSoilHour]
Measure=Time
Format=%H
UpdateDivider=60

[MeasureKSSoilMin]
Measure=Time
Format=%M
UpdateDivider=60

[MeasureKSSoilNowMinOfDay]
Measure=Calc
DynamicVariables=1
UpdateDivider=60
Formula=(([MeasureKSSoilHour] * 60) + [MeasureKSSoilMin])

; Run the PS1 (writes raw/master/rolling/last_attempt)
[MeasureKSSoil_BuildPS]
disabled=0
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
DynamicVariables=1
State=Hide
Timeout=60000
UpdateDivider=-1
Parameter=-NoProfile -ExecutionPolicy Bypass -File "#KSSoilPS1#" -Station "#KSSoilStation#" -MasterDays "#KSSoilMasterDays#" -RollingDays "#KSSoilRollingDays#" -MasterCsv "#KSSoilMasterCsv#" -RollingCsv "#KSSoilRollingCsv#" -RawCsv "#KSSoilRawCsv#" -LastAttemptTxt "#KSSoilLastAttemptTxt#"
FinishAction=[!CommandMeasure MeasureSoilGraphGen "Run()"]

; Gate: after noon AND not attempted today AND not currently running
; NOTE: Use = for comparisons inside Calc formulas.
[MeasureKSSoilGate]
disable=0
Measure=Calc
DynamicVariables=1
UpdateDivider=300
Formula=(( [MeasureKSSoilTimeHM] >= (#KSSoilRunAfterHour#*100) ) * ( [MeasureKSSoilTodayYMD] > [MeasureKSSoilLastAttemptYMDNum] ) * ( [MeasureKSSoilLock] = 0 ) * ( [MeasureUptime] > 600 ))
IfCondition=([MeasureKSSoilGate] = 1)
IfTrueAction=[!SetVariable KSSoilIsRunning 1][!SetVariable KSSoilLockStartMin "[MeasureKSSoilNowMinOfDay]"][!CommandMeasure MeasureKSSoil_BuildPS "Run"]
; Watchdog: if lock stuck longer than timeout minutes, clear it
; Handles midnight rollover safely.

[MeasureKSSoilLockWatchdog]
Measure=Calc
DynamicVariables=1
UpdateDivider=60
; elapsed minutes since lock set (handles midnight rollover)
Formula=(([MeasureKSSoilLock]=1) * (#KSSoilLockStartMin#>0) * ((([MeasureKSSoilNowMinOfDay] >= #KSSoilLockStartMin#) ? ([MeasureKSSoilNowMinOfDay] - #KSSoilLockStartMin#) : ([MeasureKSSoilNowMinOfDay] + 1440 - #KSSoilLockStartMin#)) > #KSSoilLockTimeoutMin#))
IfCondition=([MeasureKSSoilLockWatchdog]=1)
IfTrueAction=[!SetVariable KSSoilIsRunning 0][!SetVariable KSSoilLockStartMin 0][!UpdateMeasure MeasureKSSoilGate]

; ============================
; GIT PUSH (only if changes)
; ============================
[MeasureGitPush]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
State=Hide
UpdateDivider=-1
DynamicVariables=1
Parameter=-NoProfile -ExecutionPolicy Bypass -File "#GitPushPS1#" -RepoPath "#GitRepoPath#" -Message "Heartland refresh"
OutputType=ANSI
FinishAction=[!SetVariable GitLastStatus "[MeasureGitPush]"][!UpdateMeter *][!Redraw]


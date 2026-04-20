; =============================================================================
; alerts_row.inc  - NWS Active Alert icon row
; Included by "Heartland Weather.ini" via @Include=#@#alerts_row.inc
;
; MEASURES: one parent WebParser reads nws_alerts.json; 17 children extract
;           each alert flag (0 or 1).
; METERS:   17 icons at AlertRowY (#AlertRowY# = 420), 54x54px (120% of 45).
;
; TESTING STATE: Hidden=1 on all icons (all visible for inspection).
;   X positions are static sequential (24 + 58*N).
;   Some icons will overflow the skin width -that is expected for testing.
;
; PRODUCTION: Set Hidden=([MeasureAlertXxx] = 0 ? 1 : 0) and replace X with
;   the left-justify formula:
;     X=(24 + 58 * (sum of all preceding MeasureAlertXxx values))
;   This mirrors the technique used in the icon row above.
; =============================================================================

; ---------------------------------------------------------------------------
; PULSE SCRIPT -runs every 100ms (UpdateDivider=1, skin Update=100)
; Reads each MeasureAlertXxx, pulses active icon alphas, triggers sound.
; ---------------------------------------------------------------------------
[MeasureAlertPulse]
Measure=Script
ScriptFile=#@#lua\AlertPulse.lua
UpdateDivider=1
DynamicVariables=1
Group=NWSAlerts

; ---------------------------------------------------------------------------
; SOUND -one-shot low beep (300 Hz, 3 seconds) on new active alert.
; Muted when AlertMuteSound=1 in Variables section.
; ---------------------------------------------------------------------------
[MeasureAlertSoundPS]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
State=Hide
UpdateDivider=-1
Parameter=-NoProfile -Command "[Console]::Beep(880,150); Start-Sleep -Milliseconds 100; [Console]::Beep(880,150); Start-Sleep -Milliseconds 100; [Console]::Beep(880,150)"

; Tornado warning — rapid continuous alarm, no pauses between beeps
[MeasureAlertSoundTornadoPS]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
State=Hide
UpdateDivider=-1
Parameter=-NoProfile -Command "[Console]::Beep(880,80); [Console]::Beep(660,80); [Console]::Beep(880,80); [Console]::Beep(660,80); [Console]::Beep(880,80)"

; ---------------------------------------------------------------------------
; PARENT: reads nws_alerts.json and captures all 17 flags in one regex pass.
; Keys are written in a fixed order by NWSAlertsFetch.ps1.
; ---------------------------------------------------------------------------
[MeasureNWSAlerts_File]
Measure=WebParser
URL=file://#NWS_JSON#
RegExp=(?si)"TornadoWarning":([01]).*?"TornadoWatch":([01]).*?"SevereThunderstormWarning":([01]).*?"SevereThunderstormWatch":([01]).*?"FlashFloodWarning":([01]).*?"FlashFloodWatch":([01]).*?"FireWeatherWatch":([01]).*?"RedFlagWarning":([01]).*?"WinterStormWarning":([01]).*?"WinterStormWatch":([01]).*?"IceStorm":([01]).*?"HighWind":([01]).*?"WindAdvisory":([01]).*?"ExcessiveHeat":([01]).*?"HeatAdvisory":([01]).*?"FreezeWarning":([01]).*?"DenseFog":([01]).*?"DustStorm":([01])
StringIndex=0
UpdateDivider=-1
DynamicVariables=1
Group=NWSAlertsFile

; ---------------------------------------------------------------------------
; CHILDREN: one per alert flag (StringIndex matches capture group order above)
; ---------------------------------------------------------------------------
[MeasureAlertTornadoWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=1
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertTornadoWatch]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=2
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertSevereThunderstormWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=3
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertSevereThunderstormWatch]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=4
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertFlashFloodWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=5
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertFlashFloodWatch]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=6
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertFireWeatherWatch]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=7
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertRedFlagWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=8
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertWinterStormWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=9
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertWinterStormWatch]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=10
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertIceStorm]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=11
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertHighWind]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=12
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertWindAdvisory]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=13
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertExcessiveHeat]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=14
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertHeatAdvisory]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=15
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertFreezeWarning]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=16
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertDenseFog]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=17
UpdateDivider=-1
Group=NWSAlerts

[MeasureAlertDustStorm]
Measure=WebParser
URL=[MeasureNWSAlerts_File]
StringIndex=18
UpdateDivider=-1
Group=NWSAlerts

; ---------------------------------------------------------------------------
; METERS -54x54 icons, sequential X for testing (Hidden=1)
; AlertRowY = 420 (DialStartY 350 + DialBaseSize 60 + 10px gap)
;
; Icon-to-alert mapping:
;   0  TornadoWarning          tornado.png
;   1  TornadoWatch            tornado.png            (same icon; tooltip distinguishes)
;   2  SevereThunderstormWarn  thunderstorms-extreme.png
;   3  SevereThunderstormWatch thunderstorms-day.png
;   4  FlashFloodWarning       extreme-rain.png
;   5  FlashFloodWatch         rain.png
;   6  FireWeather             extreme.png            (closest available; no fire icon)
;   7  WinterStormWarning      extreme-snow.png
;   8  WinterStormWatch        overcast-snow.png
;   9  IceStorm                extreme-sleet.png
;  10  HighWind                wind-alert.png
;  11  WindAdvisory            wind.png
;  12  ExcessiveHeat           sun-hot.png
;  13  HeatAdvisory            thermometer-sun.png
;  14  FreezeWarning           thermometer-snow.png
;  15  DenseFog                fog.png
;  16  DustStorm               dust.png
; ---------------------------------------------------------------------------

[MeterAlertTornadoWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=24
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\tornado_warning.webp
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Tornado Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('TornadoWarning')"]
DynamicVariables=1

[MeterAlertTornadoWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=82
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\tornado_watch.webp
Hidden=1
ToolTipText=Tornado Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('TornadoWatch')"]
DynamicVariables=1

[MeterAlertSevereThunderstormWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=140
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thunderstorms-extreme.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Severe Thunderstorm Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('SevereThunderstormWarning')"]
DynamicVariables=1

[MeterAlertSevereThunderstormWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=198
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thunderstorms-day.png
Hidden=1
ToolTipText=Severe Thunderstorm Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('SevereThunderstormWatch')"]
DynamicVariables=1

[MeterAlertFlashFloodWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=256
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\extreme-rain.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Flash Flood Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FlashFloodWarning')"]
DynamicVariables=1

[MeterAlertFlashFloodWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=314
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\rain.png
Hidden=1
ToolTipText=Flash Flood Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FlashFloodWatch')"]
DynamicVariables=1

[MeterAlertFireWeatherWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=372
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\code-orange.png
Hidden=1
ToolTipText=Fire Weather Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FireWeatherWatch')"]
DynamicVariables=1

[MeterAlertRedFlagWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=430
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\fire_weather_warning.webp
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Red Flag Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('RedFlagWarning')"]
DynamicVariables=1

[MeterAlertWinterStormWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=488
Y=#AlertRowY#
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\extreme-snow.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Winter Storm Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WinterStormWarning')"]
DynamicVariables=1

[MeterAlertWinterStormWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=24
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\overcast-snow.png
Hidden=1
ToolTipText=Winter Storm Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WinterStormWatch')"]
DynamicVariables=1

[MeterAlertIceStorm]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=82
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\ice_warning.webp
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Ice Storm Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('IceStorm')"]
DynamicVariables=1

; Row 2: 9 icons per row, slots 9-17
[MeterAlertHighWind]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=140
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\wind-alert.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=High Wind Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('HighWind')"]
DynamicVariables=1

[MeterAlertWindAdvisory]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=198
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\wind.png
Hidden=1
ToolTipText=Wind Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WindAdvisory')"]
DynamicVariables=1

[MeterAlertExcessiveHeat]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=256
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\sun-hot.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Excessive Heat Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('ExcessiveHeat')"]
DynamicVariables=1

[MeterAlertHeatAdvisory]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=314
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thermometer-sun.png
Hidden=1
ToolTipText=Heat Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('HeatAdvisory')"]
DynamicVariables=1

[MeterAlertFreezeWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=372
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thermometer-snow.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Freeze Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FreezeWarning')"]
DynamicVariables=1

[MeterAlertDenseFog]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=430
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\fog.png
Hidden=1
ToolTipText=Dense Fog Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('DenseFog')"]
DynamicVariables=1

[MeterAlertDustStorm]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=488
Y=(#AlertRowY# + 64)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\dust.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Dust Storm
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('DustStorm')"]
DynamicVariables=1

; ---------------------------------------------------------------------------
; Row 3 — flood / winter advisory / wind chill / hard freeze / air quality / smoke
; ---------------------------------------------------------------------------

[MeterAlertFloodWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=24
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\extreme-day-rain.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Flood Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FloodWarning')"]
DynamicVariables=1

[MeterAlertFloodWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=82
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\overcast-day-rain.png
Hidden=1
ToolTipText=Flood Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FloodWatch')"]
DynamicVariables=1

[MeterAlertWinterWeatherAdvisory]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=140
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\overcast-day-snow.png
Hidden=1
ToolTipText=Winter Weather Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WinterWeatherAdvisory')"]
DynamicVariables=1

[MeterAlertWindChillWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=198
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thermometer-colder.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Wind Chill Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WindChillWarning')"]
DynamicVariables=1

[MeterAlertWindChillAdvisory]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=256
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thermometer-glass.png
Hidden=1
ToolTipText=Wind Chill Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('WindChillAdvisory')"]
DynamicVariables=1

[MeterAlertFreezeWatch]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=314
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\thermometer-colder.png
Hidden=1
ToolTipText=Freeze Watch
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('FreezeWatch')"]
DynamicVariables=1

[MeterAlertHardFreezeWarning]
Meter=Image
Group=NWSAlerts
UpdateDivider=1
X=372
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\snowflake1.png
ImageAlpha=#AlertPulseAlpha#
Hidden=1
ToolTipText=Hard Freeze Warning
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('HardFreezeWarning')"]
DynamicVariables=1

[MeterAlertAirQualityAlert]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=430
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\haze.png
Hidden=1
ToolTipText=Air Quality Alert
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('AirQualityAlert')"]
DynamicVariables=1

[MeterAlertDenseSmokeAdvisory]
Meter=Image
Group=NWSAlerts
UpdateDivider=-1
X=488
Y=(#AlertRowY# + 128)
W=54
H=54
PreserveAspectRatio=1
ImageName=#@#WeatherIcons\extreme-smoke.png
Hidden=1
ToolTipText=Dense Smoke Advisory
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "ShowDetail('DenseSmokeAdvisory')"]
DynamicVariables=1

; ---------------------------------------------------------------------------
; ALERT DETAIL POPUP — shown on icon click; dismissed by close button or
; when alert layout changes. All positioned at runtime by ShowDetail() in Lua.
; Defined last so it renders above icons.
; ---------------------------------------------------------------------------
[MeterAlertDetailBG]
Meter=Shape
Group=AlertDetailPopup
UpdateDivider=-1
X=0
Y=0
Shape=Rectangle 0,0,360,240,6 | StrokeWidth 1 | Stroke Color 255,255,255,50 | Fill Color 12,18,32,238
Hidden=1
DynamicVariables=1

[MeterAlertDetailTitle]
Meter=String
Group=AlertDetailPopup
UpdateDivider=-1
X=12
Y=10
W=278
H=26
FontSize=14
FontWeight=700
FontColor=255,255,255,255
Antialias=1
ClipString=1
Text=
Hidden=1
DynamicVariables=1

[MeterAlertDetailExpiry]
Meter=String
Group=AlertDetailPopup
UpdateDivider=-1
X=12
Y=40
W=318
H=18
FontSize=12
FontWeight=400
FontColor=255,210,90,230
Antialias=1
ClipString=1
Text=
Hidden=1
DynamicVariables=1

[MeterAlertDetailDesc]
Meter=String
Group=AlertDetailPopup
UpdateDivider=-1
X=12
Y=62
W=336
FontSize=12
FontWeight=400
FontColor=215,215,215,255
Antialias=1
Text=
Hidden=1
DynamicVariables=1

[MeterAlertDetailClose]
Meter=String
Group=AlertDetailPopup
UpdateDivider=-1
X=290
Y=8
W=24
H=24
FontSize=11
FontWeight=700
FontColor=255,255,255,200
SolidColor=90,25,25,200
StringAlign=CenterCenter
Antialias=1
Text=x
Hidden=1
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "HideDetail()"]
DynamicVariables=1

; ---------------------------------------------------------------------------
; ACK BUTTON -visible only when active alerts are present and unacknowledged.
; Managed (shown/hidden) by AlertPulse.lua every tick.
; Click calls Acknowledge() in the Lua script, which:
;   - Sets AlertAcknowledged=1
;   - Stops pulse + hides this button immediately
;   - Does NOT prevent icons from showing (just stops the blink + sound)
; ---------------------------------------------------------------------------
[MeterAlertAck]
Meter=String
Group=NWSAlerts
UpdateDivider=-1
X=(#W# / 2 - 74)
Y=((#DialStartY# + #DialBaseSize# + #AlertRowY#) / 2 - 13)
W=148
H=26
FontSize=10
FontWeight=700
FontColor=255,255,255,255
SolidColor=224,13,13,210
StringAlign=CenterCenter
Antialias=1
Text=! ACK ALARM
Hidden=1
LeftMouseUpAction=[!CommandMeasure MeasureAlertPulse "Acknowledge()"]
ToolTipText=Click to acknowledge -silences pulse and alarm sound
DynamicVariables=1

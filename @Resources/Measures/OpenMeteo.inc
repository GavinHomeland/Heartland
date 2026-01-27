; ============================================================
; Heartland - OpenMeteo.inc
; Standalone Open-Meteo provider + a simple debug dump.
; ============================================================
[MeasureOM_Raw]
Measure=Plugin
Plugin=WebParser
Url=https://api.open-meteo.com/v1/forecast?latitude=#OM_Latitude#&longitude=#OM_Longitude#&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,pressure_msl,visibility,wind_speed_10m,wind_direction_10m&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset&timezone=#OM_Timezone#&temperature_unit=#OM_TempUnit#&wind_speed_unit=#OM_WindUnit#
RegExp=(?si)\A(.*)\z
UpdateRate=#OM_UpdateRate#
Download=1
FinishAction=[!UpdateMeasureGroup "OM_Extract"][!UpdateMeterGroup "OM_UI"][!Redraw][!CommandMeasure MeasureOM_Dump "Run"]
DynamicVariables=1
; -------------------------
; Current conditions
; -------------------------
[MeasureOM_Temp]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"temperature_2m"\s*:\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_Humidity]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"relative_humidity_2m"\s*:\s*(\d+)
StringIndex=1
Group=OM_Extract
[MeasureOM_Feels]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"apparent_temperature"\s*:\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_Pressure]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"pressure_msl"\s*:\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_VisibilityM]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"visibility"\s*:\s*(\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_VisibilityMi]
Measure=Calc
Formula=([MeasureOM_VisibilityM] / 1609.344)
DynamicVariables=1
Group=OM_Extract
[MeasureOM_WindSpeed]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"wind_speed_10m"\s*:\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_WindDir]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"wind_direction_10m"\s*:\s*(\d+)
StringIndex=1
Group=OM_Extract
; IMPORTANT: match numeric weather_code from current{} to avoid current_units/daily_units
[MeasureOM_WMOCode]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"current"\s*:\s*\{.*?"weather_code"\s*:\s*(\d+)
StringIndex=1
Group=OM_Extract
[MeasureOM_WindCardIndex]
Measure=Calc
Formula=Floor(((([MeasureOM_WindDir]+11.25) % 360) / 22.5))
DynamicVariables=1
Group=OM_Extract
[MeasureOM_WindCard]
Measure=Calc
Formula=[MeasureOM_WindCardIndex]
Substitute="0":"N","1":"NNE","2":"NE","3":"ENE","4":"E","5":"ESE","6":"SE","7":"SSE","8":"S","9":"SSW","10":"SW","11":"WSW","12":"W","13":"WNW","14":"NW","15":"NNW"
DynamicVariables=1
Group=OM_Extract
; Sunrise / Sunset (today) are in daily arrays
[MeasureOM_Sunrise]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"sunrise"\s*:\s*\[\s*"[^"]*T(\d{2}:\d{2})
StringIndex=1
Group=OM_Extract
[MeasureOM_Sunset]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"sunset"\s*:\s*\[\s*"[^"]*T(\d{2}:\d{2})
StringIndex=1
Group=OM_Extract
; -------------------------
; Daily forecast: grab first 3 days
; -------------------------
[MeasureOM_DailyTime]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"daily"\s*:\s*\{.*?"time"\s*:\s*\[\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"
StringIndex=1
Group=OM_Extract
[MeasureOM_DailyMax]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"temperature_2m_max"\s*:\s*\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_DailyMin]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"temperature_2m_min"\s*:\s*\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)
StringIndex=1
Group=OM_Extract
[MeasureOM_DailyCode]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_Raw]
RegExp=(?si)"daily"\s*:\s*\{.*?"weather_code"\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)
StringIndex=1
Group=OM_Extract
[MeasureOM_D2Date]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_DailyTime]
StringIndex=2
Group=OM_Extract
[MeasureOM_D3Date]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_DailyTime]
StringIndex=3
Group=OM_Extract
[MeasureOM_D2High]
Measure=Calc
Formula=Round([MeasureOM_DailyMax:2])
DynamicVariables=1
Group=OM_Extract
[MeasureOM_D2Low]
Measure=Calc
Formula=Round([MeasureOM_DailyMin:2])
DynamicVariables=1
Group=OM_Extract
[MeasureOM_D3High]
Measure=Calc
Formula=Round([MeasureOM_DailyMax:3])
DynamicVariables=1
Group=OM_Extract
[MeasureOM_D3Low]
Measure=Calc
Formula=Round([MeasureOM_DailyMin:3])
DynamicVariables=1
Group=OM_Extract
[MeasureOM_D2Code]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_DailyCode]
StringIndex=2
Group=OM_Extract
[MeasureOM_D3Code]
Measure=Plugin
Plugin=WebParser
URL=[MeasureOM_DailyCode]
StringIndex=3
Group=OM_Extract
; -------------------------
; Simple dump to a logfile (proves "what the UI is actually seeing")
; Writes to: #@#Logs\Heartland_Debug.txt
; -------------------------
[MeasureOM_Dump]
Measure=Plugin
Plugin=RunCommand
Program=cmd.exe
Parameter=/c echo ---- %date% %time% ---->>"#@#Logs\Heartland_Debug.txt"&echo Temp=[MeasureOM_Temp]>>"#@#Logs\Heartland_Debug.txt"&echo Feels=[MeasureOM_Feels]>>"#@#Logs\Heartland_Debug.txt"&echo Humidity=[MeasureOM_Humidity]>>"#@#Logs\Heartland_Debug.txt"&echo Pressure=[MeasureOM_Pressure]>>"#@#Logs\Heartland_Debug.txt"&echo Vis(m)=[MeasureOM_VisibilityM]>>"#@#Logs\Heartland_Debug.txt"&echo WindSpeed=[MeasureOM_WindSpeed]>>"#@#Logs\Heartland_Debug.txt"&echo WindDir=[MeasureOM_WindDir]>>"#@#Logs\Heartland_Debug.txt"&echo WindCard=[MeasureOM_WindCard]>>"#@#Logs\Heartland_Debug.txt"&echo WMOCode=[MeasureOM_WMOCode]>>"#@#Logs\Heartland_Debug.txt"&echo Sunrise=[MeasureOM_Sunrise]>>"#@#Logs\Heartland_Debug.txt"&echo Sunset=[MeasureOM_Sunset]>>"#@#Logs\Heartland_Debug.txt"&echo D2=[MeasureOM_D2Date] Hi=[MeasureOM_D2High] Lo=[MeasureOM_D2Low] Code=[MeasureOM_D2Code]>>"#@#Logs\Heartland_Debug.txt"&echo D3=[MeasureOM_D3Date] Hi=[MeasureOM_D3High] Lo=[MeasureOM_D3Low] Code=[MeasureOM_D3Code]>>"#@#Logs\Heartland_Debug.txt"&echo.>>"#@#Logs\Heartland_Debug.txt"
State=Hide
UpdateDivider=-1
DynamicVariables=1

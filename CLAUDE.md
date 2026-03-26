# Heartland Weather
## Claude instructions for next run. Maintain status indication of this log.

- [x] Review and test the new chain/logging structure after Rainmeter reload.
- [x] Old status files `ks_soiltemp_2in_last_attempt.txt` and `om_status.txt` deleted (new files confirmed active as of 2026-02-25).

## Claude notes from 2026-02-24 run.

All tasks from the previous instruction block were completed:

### Section ordering (Heartland Weather.ini)
Sections are now ordered in 4 chain steps:
1. **Init** — `MeasureCurPathSlash` + `MeasureStartupTimer` (3s delay on load/refresh)
2. **OM fetch** — `MeasureAutoFetch` → `MeasureOM_FetchPS` → OM parsers → `MeasureOM_OkErr` → `MeterOMDot` → then bangs `MeasureKSSoilGate`
3. **Soil/Mesonet** — `MeasureKSSoilGate` → `MeasureKSSoil_BuildPS` → soil parsers → `MeasureSoil_OkErr` → `MeterSoilDot` → `MeasureSoilGraphGen`
4. **Display** — all meters

### Daisy chain
- OM FinishAction calls `!UpdateMeasure MeasureKSSoilGate` to hand off to soil check.
- Soil PS1 FinishAction calls `MeasureSoilGraphGen "Run()"`.
- SoilGraphGen FinishAction calls `MeasureGitPush "Run"`.
- On startup (3s delay) and on manual refresh via MeterRefresh, both OM and soil are force-run.

### File rename / log structure
| Old file | New file | Purpose |
|---|---|---|
| `om_status.txt` | `om_fetch_status.txt` | OM fetch last-run status (overwritten, single line) |
| `ks_soiltemp_2in_last_attempt.txt` | `soil_fetch_status.txt` | Soil fetch last-run status (overwritten) |
| (new) | `OM_FetchPS_log.txt` | Appending OM fetch history |
| (new) | `KSSoilMasterFetch_log.txt` | Appending soil fetch history |
| (new) | `SoilGraphGen_log.txt` | Appending soil graph run history |
| (new) | `Heartland_log.txt` | Master chronological log (all 3 sources) |
| deleted | `om_model_meta_state.json` | — |
| deleted | `om_model_meta_log.csv` | — |

### PROBE logging (KSSoilMasterFetch.ps1)
When the PS1 is called but soil data was already fetched today, it logs:
`PROBE YYYY-MM-DDTHH:MM:SS Already succeeded today. Skipping fetch.`
to `soil_fetch_status.txt`, `KSSoilMasterFetch_log.txt`, and `Heartland_log.txt`.

### SoilGraphGen.lua — Notice category
To log at Notice level instead of Debug in Rainmeter Lua:
- `print("message")` → logs as **Debug** (default)
- `SKIN:Bang("!Log", "message", "Notice")` → logs as **Notice**

### Status indicator dots — how they work
- `MeterOMDot`: `X=(#W# - #Pad# - 46)` — left dot; driven by `MeasureOM_OkErr`
- `MeterSoilDot`: `X=(#W# - #Pad# - 22)` — right dot; driven by `MeasureSoil_OkErr`
- **Green** (`0,220,0,150`): last fetch returned `OK` — data was successfully fetched and written.
- **Red** (`255,0,0,150`): last fetch returned `ERR` (network/script failure) **or** `PROBE` (gate passed but soil was already fetched today — no new pull occurred).
- ToolTipText on each dot shows the ISO timestamp from the last status line.
- PROBE = safety valve; SoilDot stays red on PROBE by design (no data change occurred).

### Wind tooltip
MeterWindArrow ToolTipText now includes gust line between speed and direction.

### [x] Create Temperature graph — DONE (refinements may continue)
See 2026-02-25 run notes below.

## Claude notes from 2026-02-25 run.

### Air Temp Graph — implemented + refined
New files / measures:
- `@Resources/lua/AirTempGraphGen.lua` — Lua script; called from OM FinishAction and startup timer
- `[MeasureAirTempGraphGen]` — Script measure
- `[MeterAirTempGraph]` + `[MeterAirTempGraphTitle]` — Shape + String meters

Final layout (after refinement pass):
- 22 bars: 14 past daily lows (bars) + today current temp (bar) + 7 forecast (line only)
- barW=8, barGap=1 → 197px wide × 130px tall (1px/degree, -20..110°F)
- Right-justified: same right edge as soil graph (W-Pad=604)
- X = W-Pad-(22×8 + 21×1) = W-Pad-197
- Y = SoilGraphY + SoilGraphH + 65 = 295; title at Y-22=273

Draw order (shapes, back to front):
1. Frame — rounded rect border 255,255,255,90
2. Today indicator — bright vertical line 230,240,255,220 at today's bar center
3. Freeze line — red horizontal at 32°F
4. **Freeze-fill patches** — pale blue 140,190,255,130 fill between freeze line and polyline where temp < 32°F
5. Future day reference lines — grey verticals
6. Bars — fully opaque fill + black stroke 1px
7. Polyline — 2px opaque uniform color = color of dataset minimum

Tooltip: `Hx Low / Current (live currentTemp) / Predicted Low`
Log: `AirTempGraphGen_log.txt` (appending) + master `Heartland_log.txt`

### Moon tooltip (fixed 2026-02-25)
- `MoonPhaseIcon.lua` now always exports `#MoonPhasePct#` and `#MoonNextFull#` at the top of `Update()` — both day and night.
- `MoonNextFull` format changed from `Mar/14` to `Mar14` (no slash).
- MeterMoon ToolTipText: `% phase \n Next full: Mmm## \n Sunrise \n Sunset`

### AirTempGraph tooltip fix (2026-02-25)
- Tooltip `Current:` now correctly shows `currentTemp` (the live reading used for the today bar) instead of today's forecasted daily minimum. Was showing wrong value (~37°F instead of ~64°F).

### Notes file
- `notes/XY2026-02-25.md` — all meters with computed X/Y/W/H as of this date.

### AirTempGraph blank (2026-02-25 debugging session)
Root cause identified: `ClosePath` in freeze-fill Path shape was missing the required `1` argument. Rainmeter stops rendering a Shape meter at the first invalid shape — so only Shape1 (frame) displayed. Fix is `ClosePath 1` (already in the file on disk).

**Important**: The log (`AirTempGraphGen_log.txt`) only showed `Run Start / Run Complete` with no freeze-fill entries because Rainmeter had NOT been reloaded after the fix was applied. Rainmeter loads Lua once at skin load; all those log entries were from the old code. After reload, the fix + logging will both take effect.

### Moon blank icon + MoonNextFull blank (2026-02-25 debugging session)
- **MoonNextFull blank**: `!SetVariable` bangs are queued and fire *after* `!UpdateMeterGroup OM` in FinishAction. So `#MoonNextFull#` is still empty when MeterMoon renders.
- **Fix applied**: `MoonPhaseIcon.lua` now uses `!SetOption MeterMoon ToolTipText` with fully baked-in tooltip text (computed in Lua from raw measure values). Bypass the variable timing issue entirely. `!UpdateMeter MeterMoon` is called after `!SetOption` so the new text takes effect.
- **Moon icon blank / "° C"**: Was caused by `!UpdateMeter MeterMoon` being called inside `Update()` before the tooltip approach was restructured. Now properly ordered: `!SetOption` → `!UpdateMeter`.
- Both `!SetVariable MoonPhasePct` and `!SetVariable MoonNextFull` are still set for backward compatibility.

### All confirmed working (2026-02-25 / continued session)
- [x] AirTempGraph renders: frame, today indicator, freeze line, bars, polyline — all correct
- [x] Freeze-fill patches render correctly using named Path keys
- [x] Moon icon no longer blank
- [x] Moon tooltip: Next Full populates day and night; format `Mar14`; Sunrise/Sunset correct

### Critical Rainmeter Path shape syntax (learned the hard way)
Rainmeter `Path` shapes require the path DATA in a **separate named key** on the meter — NOT inlined in the `Shape=` line:
```ini
; INI pre-declaration:
FreezePatch1=0,0

; Shape= line references the name:
Shape4=Path FreezePatch1 | StrokeWidth 0 | Fill Color 140,190,255,130
```
Then from Lua:
```lua
SKIN:Bang("!SetOption", meterName, "FreezePatch1", "enterX,Y | LineTo x,y | ClosePath 1")
setShape(meterName, shapeIdx, "Path FreezePatch1 | StrokeWidth 0 | Fill Color 140,190,255,130")
```
`ClosePath 1` and `LineTo` are valid segment keywords. The error "Path shape has invalid parameters" was caused by inlining coordinates directly in the `Shape=` line.


## Instructions for Claude (ignore for now)
- [ ] Extend rain indicator bars over the entire air temp graph, one for each day. Past = actual precip, today = Forcast in alpha 180 + actual in alpha 255, future = forecast precip (as is)
    - Use blue for rain, cyan for mix, white for snow
    - Front Z, below only the blue line and freeze fill.
- [ ] On Air Temp, create a grey alpha 180 horizontal line at 72 degrees (z same as the day vertical lines -- in the back) for reference.
- [ ] I extended the bg down by 50. 
    - Move the Air Temp graph and Soil temp graphs down by 50. 
    - Move B2 (rainbucket) down by 50, b1 down by 30, b0 down by 10. Adjust the start and stop points of the raidrops and drips and overflow drips accordingly. 
    - [ ] Modify the OM pull to extract alerts, warnings, watches and the like, if not already pulled. (examples: Fire watch, tornado warning)
        - Create a row below the barometer-humidity row that displays the warnings at 120% the size of the icon row above (windsock, eg).
            - Use appropriate graphics from /WeatherIcons for each alert. Display them in the same hidden-not hidden/left justified manner as the windsock row. 
            - Put the code in an .inc or whatever the professional way would be to create this feature instead of making 100 more lines in the ini. 
            - Initially, make all of the icons visible for inspection. Create appropriate tooltips for each icon. 
- [ ] Mesonet dot indicates red when it should be green on OK probe. It's only red when ERR or other not OK status is detected.

## Completed
- [x] Add lines similar to the freeze line (just a horizontal line) in the *soil graph* at 50, 55 and 60 degrees. Make them green, but 50 opacity is 150, 55 is 160, 60 is 180. Actually... I changed my mind about the color. Make the 50 degree one yellow and the other two green.
- [x] Behind the existing history graph in the AIR TEMPERATURE graph, I'd like to put two more bars (at a lower z). From back to front the graph will be: the vertical index bars as they exist, hi temp for that day (including today), average temp for that day (including current temperature), that fancy below freezing fill that you made (don't mess it up!), then the low temp for that day (history, none for today), the blue line that incorporates the predicted low.
- [x] Limit log files (*log.txt) to 1000 lines 1x per day. — Added rotateLogs() to AirTempGraphGen.lua; fires once/day, trims all 6 log files to 1000 lines.
- [x] Analyze heartland_refs.txt — It is a generated grep index (Measure=/Plugin=/ImageName= lines from the INI). No unique info; safe to delete.
- [x] Soil fetch timing — Multiple runs on 2026-02-24/25 were development session reloads, not a bug. Production: clean single daily run. Changed KSSoilRunAfterHour from 12→8 so it fetches at 8AM (after MESONET posts overnight readings) instead of noon.

### Rainbuckets (Completed)
- [x] There is a 1px gap between the 'water' and the left wall of bucket 0. Rather than widen the water, narrow up the bucket so it's 8 px narrower than the bucket 1 and make the water fit inside edge to edge.  Concurrently, make B1 4 px narrower than B2 and fit the water accordingly. You'll have to narrow up the raindrops a bit to match the top of B0. — B0=48px, B1=56px, B2=60px; water fills edge-to-edge within each bucket; drops confined to B0 X range.
- [x] Raise up extreme.png and lightning-bolt.png by 10 px and the raindrop start accordingly. — Icons: Y=(SoilGraphY-10); DROP_START_Y: 22→12.
- [x] Drips from B0 to B1 should be twice as often, if present. Don't overthink the drips. They are just a constant rate and the animation looks good now except there should be a splash at the top of water in B1 and B2 as well. — B0→B1 dripInterval=12 (vs 25 for B1→B2); splash added on landing.
- [x] In the following data from the .json (I'm assuming that the 'real' OM data will be identical):
    -   "current": { "precipitation": 1.1, "weather_code": 95 },
  "daily": {
    "time": ["2026-03-02","2026-03-03","2026-03-04","2026-03-05","2026-03-06","2026-03-07","2026-03-08"],
    "precipitation_sum": [1.52, 0.50, 0.50, 0.55, 0.10, 0.08, 0.20]
    - The level in B0 is (total rain accumulation for the past hour)-(the amount dripped out into B1)
        - If the bucket is overfull, then the bucket overflows. The animation triggers, but the level in B1 remains the same calculation (below)
    - The level in B1 is (total rain accumulation for the past 24 hours)-(amount dripped out into B2). B1 can also overflow into B2. B0 and B1 are clamped at 100% full (top of the chamfer)
    - The level in B2 is (the total rain accumulation for the past 7 days). It can just step down in level as each day passes... so it's just the last line of the json, summed. 
- [x] Water turning cyan in B0 when overly full — removed OVERFLOW_C; fill always uses FILL_C (blue); clamped at 100%.
- [x] Remove the text below B2 — MeterRainToggle and MeterRainRateLabel removed from INI.
- Reference and take into account the following:
Is there hourly rain accumulation available from OM?

Gemini said
Yes, hourly rain accumulation is available from the Open-Meteo (OM) API, but there is a specific way it is calculated that you should keep in mind for your Rainmeter skin.

1. The Variable: rain vs. precipitation
While OM provides a generic precipitation variable, it also breaks it down into specific types. For your purposes, you likely want one of these two:

rain: Specifically liquid atmospheric water (large-scale precipitation).

precipitation: The total sum of rain + showers + snow.

2. The Logic: "Preceding Hour Sum"
Unlike temperature, which is an instantaneous measurement (e.g., "it is 70° right now"), hourly rain in the OM API is an accumulation value.

Definition: The value provided for a specific timestamp is the sum of the preceding hour.

Example: If the API returns 0.5mm for 14:00, it means 0.5mm of rain fell between 13:00 and 14:00.

3. Convective Rain (Showers)
Since you are in Kansas, much of your rain comes from thunderstorms (convective activity).

The showers variable: OM tracks this separately from rain. If you only pull the rain variable, you might miss the "pop-up" storm accumulation.

Recommended Variable: Use precipitation to get the true hourly total, or pull both rain and showers and add them together in your Rainmeter Calc measure.

4. Special Note for the HRRR Model
Because you are using the HRRR model (the high-resolution model for the US), there is a quirk:

The HRRR is a "convection-allowing" model. It doesn't actually distinguish between "rain" and "showers" in its raw output. In the OM API, when using HRRR, the showers variable will often be 0, and all liquid accumulation will be funneled into the rain variable.

API Call Example
To get the most accurate hourly accumulation for your area, your request should look something like this:
&hourly=precipitation,rain,showers&precipitation_unit=inch
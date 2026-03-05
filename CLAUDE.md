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


## Instructions for Claude
- Add lines similar to the freeze line (just a horizontal line) in the *soil graph* at 50, 55 and 60 degrees. Make them green, but 50 opacity is 150, 55 is 160, 60 is 180. Actually... I changed my mind about the color. Make the 50 degree one yellow and the other two green. 
# Heartland Weather
## Claude instructions for next run. Maintain status indication of this log.

- [ ] Review and test the new chain/logging structure after Rainmeter reload.
- [ ] The `ks_soiltemp_2in_last_attempt.txt` and `om_status.txt` files still exist in the skin root (old status files). Once the new `soil_fetch_status.txt` and `om_fetch_status.txt` are confirmed working, those old files can be removed.

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

### Status indicator dots
- `MeterOMDot`: `X=(#W# - #Pad# - 46)` — left dot
- `MeterSoilDot`: `X=(#W# - #Pad# - 22)` — right dot (24px separation)
- Both: ToolTipText shows last fetch timestamp (no status text; color conveys it)
- SoilDot stays red on PROBE (no pull occurred — consider whether green on PROBE is preferred)
    - Dots are working fine now, I think. Explain how they are supposed to work (red vs green)


### Moon tooltip
MoonPhaseIcon.lua sets `#MoonPhasePct#` (e.g. "41% waxing") and `#MoonNextFull#` (e.g. "Mar/14").
    - Change format to Mar14, no slash. Next full tooltip should populate even in the day.
MeterMoon ToolTipText: `% phase \n Next full: mmm/dd \n Sunrise \n Sunset`

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
- Y = SoilGraphY + SoilGraphH + 35 = 265; title at Y-19=246

Skin expanded: H 490 → 620 (+130px total). Rows shifted +130px from original:
- IconRowY: 280 → 410
- DialRowY: 330 → 460
- DialStartY: 350 → 480
- Hard-coded MeterWind Y: 420 → 550

Draw order (shapes, back to front):
1. Frame — rounded rect border 255,255,255,90
2. Today indicator — bright vertical line 230,240,255,220 at today's bar center
3. Freeze line — red horizontal at 32°F
4–18. Bars — fully opaque fill + black stroke 1px
19+. Polyline — 2px opaque uniform color = color of dataset minimum

Tooltip: `Hx Low / Current / Predicted Low` (absolute mins of past-14, today, future-7)
Log: `AirTempGraphGen_log.txt` (appending) + master `Heartland_log.txt`

### Still to test after Rainmeter reload
- Graph renders correctly (bars, line, frame, freeze line, today indicator)
- Layout: icon row, dials, wind text clear of graph

## Papa notes and instruction for between runs.

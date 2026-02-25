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


### Moon tooltip
MoonPhaseIcon.lua sets `#MoonPhasePct#` (e.g. "41% waxing") and `#MoonNextFull#` (e.g. "Mar/14").
MeterMoon ToolTipText: `% phase \n Next full: mmm/dd \n Sunrise \n Sunset`

### Wind tooltip
MeterWindArrow ToolTipText now includes gust line between speed and direction.

## Papa notes and instruction for between runs.

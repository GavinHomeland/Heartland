# PAPA — Planned And Parked Additions

Future enhancements noted here for later implementation.

---

## Forecast Apparent Temperature (Feels Like)

**Status:** Parked — data not yet fetched.

**What:** Add `apparent_temperature_max` and `apparent_temperature_min` to `OM_DAILY` in the INI so that forecast feels-like highs and lows are available alongside the existing temperature forecast.

**Where to use:**
- Air Temp graph tooltip (show forecast feels-like alongside predicted low)
- Potentially a secondary overlay or line on the air temp graph

**How:**
1. In `Heartland Weather.ini`, append `,apparent_temperature_max,apparent_temperature_min` to the `OM_DAILY` variable (line ~114).
2. In `AirTempGraphGen.lua`, parse the new daily arrays from `om.json` the same way `temperature_2m_min` is parsed.
3. Decide on display: tooltip-only, or a dotted/dashed overlay line on the graph.

**Note:** Current live feels-like is already fetched via `apparent_temperature` in `OM_CUR_AIR` and displayed in `MeterFeels`. This enhancement is forecast-only (days 1–7).

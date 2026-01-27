-- =====================================================================
-- WMOtoBasIcon.lua
-- Maps WMO weather codes to Bas Milius (Meteocons) PNG filenames.
-- Night variants are applied ONLY for WMO 0–2 if MeasureIsNight=1.
-- Fallback: not-available.png
-- =====================================================================

function Initialize()
end

-- Day mapping (WMO -> icon filename)
local Day = {
  [0]  = "clear-day.png",            -- Clear sky
  [1]  = "clear-day.png",            -- Mainly clear
  [2]  = "partly-cloudy-day.png",    -- Partly cloudy
  [3]  = "overcast.png",             -- Overcast

  [45] = "fog.png",                  -- Fog
  [48] = "fog.png",                  -- Depositing rime fog

  [51] = "drizzle.png",              -- Drizzle: light
  [53] = "drizzle.png",              -- Drizzle: moderate
  [55] = "drizzle.png",              -- Drizzle: dense

  [56] = "sleet.png",                -- Freezing drizzle: light
  [57] = "sleet.png",                -- Freezing drizzle: dense

  [61] = "rain.png",                 -- Rain: slight
  [63] = "rain.png",                 -- Rain: moderate
  [65] = "rain.png",                 -- Rain: heavy

  [66] = "sleet.png",                -- Freezing rain: light
  [67] = "sleet.png",                -- Freezing rain: heavy

  [71] = "snow.png",                 -- Snow fall: slight
  [73] = "snow.png",                 -- Snow fall: moderate
  [75] = "snow.png",                 -- Snow fall: heavy

  [77] = "snow.png",                 -- Snow grains

  [80] = "rain.png",                 -- Rain showers: slight
  [81] = "rain.png",                 -- Rain showers: moderate
  [82] = "rain.png",                 -- Rain showers: violent

  [85] = "snow.png",                 -- Snow showers: slight
  [86] = "snow.png",                 -- Snow showers: heavy

  [95] = "thunderstorms.png",        -- Thunderstorm: slight/moderate
  [96] = "thunderstorms.png",        -- Thunderstorm with slight hail
  [99] = "thunderstorms.png"         -- Thunderstorm with heavy hail
}

-- Night overrides for ONLY WMO 0–2 (per your requirement)
local NightOverride = {
  [0] = "clear-night.png",
  [1] = "clear-night.png",
  [2] = "partly-cloudy-night.png"
}

local function getMeasureNumber(name, defaultValue)
  local m = SKIN:GetMeasure(name)
  if not m then return defaultValue end
  local v = tonumber(m:GetValue())
  if v == nil then return defaultValue end
  return v
end

function Update()
  local wmo = getMeasureNumber("MeasureWMOCode", 0)
  local isNight = getMeasureNumber("MeasureIsNight", 0)

  if isNight == 1 and NightOverride[wmo] ~= nil then
    return NightOverride[wmo]
  end

  if Day[wmo] ~= nil then
    return Day[wmo]
  end

  return "not-available.png"
end

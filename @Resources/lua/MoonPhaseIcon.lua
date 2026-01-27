-- =====================================================================
-- MoonPhaseIcon.lua  (now: Day icons by sun times + Moon phases at night)
--
-- Day icon rules (filenames in #@#WeatherIcons\):
--   sunrise.png  = < 30 minutes after sunrise
--   sunset.png   = < 30 minutes after sunset
--   clear-day.png= all other daytime
--
-- Night icon rules:
--   moon phase icon computed locally (no API)
--
-- Inputs (from your INI measures):
--   MeasureSunriseHour, MeasureSunriseMin  (24h)
--   MeasureSunsetHour,  MeasureSunsetMin   (24h)
-- =====================================================================

local TWILIGHT_MINUTES = 45

-- Moon phase math (UTC-based approximation)
local SYNODIC_MONTH = 29.530588853       -- days
local NEW_MOON_JD   = 2451550.1          -- 2000-01-06 18:14 UT (common epoch)

function Initialize()
end

local function getMeasureNumber(name, defaultValue)
  local m = SKIN:GetMeasure(name)
  if not m then return defaultValue end
  local v = tonumber(m:GetValue())
  if v == nil then return defaultValue end
  return v
end

local function julianDateUTC(t)
  local y, m, d = t.year, t.month, t.day
  local hour = t.hour + (t.min / 60) + (t.sec / 3600)

  if m <= 2 then
    y = y - 1
    m = m + 12
  end

  local A = math.floor(y / 100)
  local B = 2 - A + math.floor(A / 4)

  local jd = math.floor(365.25 * (y + 4716))
           + math.floor(30.6001 * (m + 1))
           + d + B - 1524.5
           + (hour / 24)

  return jd
end

local function moonPhaseIcon()
  local t = os.date("!*t") -- UTC
  local jd = julianDateUTC(t)
  local f  = ((jd - NEW_MOON_JD) / SYNODIC_MONTH)
  f = f - math.floor(f) -- 0..1

  -- 8-phase buckets
  if (f < 0.0625) or (f >= 0.9375) then return "moon-new.png" end
  if (f < 0.1875) then return "moon-waxing-crescent.png" end
  if (f < 0.3125) then return "moon-first-quarter.png" end
  if (f < 0.4375) then return "moon-waxing-gibbous.png" end
  if (f < 0.5625) then return "moon-full.png" end
  if (f < 0.6875) then return "moon-waning-gibbous.png" end
  if (f < 0.8125) then return "moon-last-quarter.png" end
  return "moon-waning-crescent.png"
end

function Update()
  -- Local “now”
  local now = os.date("*t") -- local time
  local nowMin = (now.hour * 60) + now.min

  -- Sunrise/sunset from INI (24-hour)
  local srH = getMeasureNumber("MeasureSunriseHour", nil)
  local srM = getMeasureNumber("MeasureSunriseMin",  nil)
  local ssH = getMeasureNumber("MeasureSunsetHour",  nil)
  local ssM = getMeasureNumber("MeasureSunsetMin",   nil)

  -- If we don't have sun times yet, fall back to moon phase (safe)
  if srH == nil or srM == nil or ssH == nil or ssM == nil then
    return moonPhaseIcon()
  end

  local srMin = (srH * 60) + srM
  local ssMin = (ssH * 60) + ssM

  -- Sunrise window (0..30 min after sunrise)
  if nowMin >= srMin and nowMin < (srMin + TWILIGHT_MINUTES) then
    return "sunrise.png"
  end

  -- Sunset window (0..30 min after sunset)
  if nowMin >= ssMin and nowMin < (ssMin + TWILIGHT_MINUTES) then
    return "sunset.png"
  end

  -- Daytime proper
  if nowMin >= srMin and nowMin < ssMin then
    return "clear-day.png"
  end

  -- Nighttime
  return moonPhaseIcon()
end

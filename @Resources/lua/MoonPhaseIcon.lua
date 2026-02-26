-- =====================================================================
-- MoonPhaseIcon.lua  (now: Day icons by sun times + Moon phases at night)
--
-- Day icon rules (filenames in #@#WeatherIcons\):
--   sunrise.png  = < 45 minutes after sunrise
--   sunset.png   = < 45 minutes after sunset
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

-- Convert a Julian Day Number to calendar date string "MmmDD"
local MONTH_ABBR = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}

local function jdToMonDD(jd)
  local Z = math.floor(jd + 0.5)
  local A
  if Z < 2299161 then
    A = Z
  else
    local alpha = math.floor((Z - 1867216.25) / 36524.25)
    A = Z + 1 + alpha - math.floor(alpha / 4)
  end
  local B = A + 1524
  local C = math.floor((B - 122.1) / 365.25)
  local D = math.floor(365.25 * C)
  local E = math.floor((B - D) / 30.6001)
  local day   = B - D - math.floor(30.6001 * E)
  local month = (E < 14) and (E - 1) or (E - 13)
  return MONTH_ABBR[month] .. tostring(day)
end

-- Returns the 8-phase icon filename
local function moonPhaseIcon(f)
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
  -- Compute moon phase (always, regardless of day/night)
  local utc = os.date("!*t")
  local jd  = julianDateUTC(utc)
  local f   = ((jd - NEW_MOON_JD) / SYNODIC_MONTH)
  f = f - math.floor(f) -- 0..1
  local illum      = math.floor((1 - math.cos(2 * math.pi * f)) / 2 * 100 + 0.5)
  local desc       = (f < 0.5) and "waxing" or "waning"
  local daysToFull = ((0.5 - f) % 1) * SYNODIC_MONTH
  local nextFull   = jdToMonDD(jd + daysToFull)

  -- Sunrise/sunset from INI (24-hour) -- read here so tooltip can use them
  local srH = getMeasureNumber("MeasureSunriseHour", nil)
  local srM = getMeasureNumber("MeasureSunriseMin",  nil)
  local ssH = getMeasureNumber("MeasureSunsetHour",  nil)
  local ssM = getMeasureNumber("MeasureSunsetMin",   nil)

  -- Format a 24h hour+min as "H:MM AM/PM"
  local function fmtTime(h, m)
    if not h or not m then return "n/a" end
    local h12  = ((h + 11) % 12) + 1
    local ampm = (h >= 12) and "PM" or "AM"
    return string.format("%d:%02d %s", h12, m, ampm)
  end

  -- Bake full tooltip into the meter via !SetOption so it is not subject to
  -- !SetVariable timing lag (SetVariable queues fire after UpdateMeterGroup OM).
  local tip = string.format("%d%% %s\nNext full: %s\nSunrise: %s\nSunset: %s",
    illum, desc, nextFull, fmtTime(srH, srM), fmtTime(ssH, ssM))
  SKIN:Bang("!SetVariable", "MoonPhasePct", tostring(illum) .. "% " .. desc)
  SKIN:Bang("!SetVariable", "MoonNextFull", nextFull)
  SKIN:Bang("!SetOption",   "MeterMoon", "ToolTipText", tip)
  SKIN:Bang("!UpdateMeter", "MeterMoon")

  -- Determine icon based on local time vs sunrise/sunset windows
  local now    = os.date("*t") -- local time
  local nowMin = (now.hour * 60) + now.min

  if srH == nil or srM == nil or ssH == nil or ssM == nil then
    return moonPhaseIcon(f)
  end

  local srMin = (srH * 60) + srM
  local ssMin = (ssH * 60) + ssM

  -- Sunrise window (0..TWILIGHT_MINUTES min after sunrise)
  if nowMin >= srMin and nowMin < (srMin + TWILIGHT_MINUTES) then
    return "sunrise.png"
  end

  -- Sunset window (0..TWILIGHT_MINUTES min after sunset)
  if nowMin >= ssMin and nowMin < (ssMin + TWILIGHT_MINUTES) then
    return "sunset.png"
  end

  -- Daytime proper
  if nowMin >= srMin and nowMin < ssMin then
    return "clear-day.png"
  end

  -- Nighttime
  return moonPhaseIcon(f)
end

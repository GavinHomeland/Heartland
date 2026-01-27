-- =====================================================================
-- PressureGauges.lua
-- LEFT needle (barometery.png): absolute pressure vs baseline
--   0° = baseline, + = higher, - = lower
--
-- RIGHT needle (barometer.png): 3-hour pressure tendency (rate of change)
--   0° = steady, +90° = rapid rise, -90° = rapid fall
--
-- Reads Open-Meteo hourly pressure_msl from om.json (timezone-local)
-- Sets variables for tooltips + the LEFT needle angle:
--   #PressureActualAngle#
--   #PressureNowHpa#
--   #PressureBaselineHpa#
--   #PressureDeltaBaselineHpa#
--   #PressureDelta3hHpa#
--   #PressureRateHpaHr#
-- Returns: Trend angle in degrees (for RIGHT needle)
-- =====================================================================

-- =========================
-- TUNABLE CONSTANTS
-- =========================
local BASELINE_WINDOW_HOURS = 24     -- baseline = mean of last 24 hourly points
local TREND_WINDOW_HOURS    = 3      -- tendency window
local MAX_ABS_DELTA_HPA     = 25.0   -- [ESTIMATE] clamp abs needle at +/-25 hPa (≈ "big" swings)
local MAX_TREND_DP3H_HPA    = 6.0    -- [ESTIMATE] clamp trend at +/-6 hPa per 3h for full +/-90°

-- =========================
local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function findArrayBlock(objText, key)
  -- finds: "key":[ ... ]
  local pat = '"' .. key .. '"%s*:%s*%[(.-)%]'
  return objText:match(pat)
end

local function parseTimes(block)
  local t = {}
  for s in block:gmatch('"(.-)"') do
    t[#t+1] = s
  end
  return t
end

local function parseNumbers(block)
  local n = {}
  for s in block:gmatch("[-%d%.]+") do
    n[#n+1] = tonumber(s)
  end
  return n
end

local function findIndex(times, target)
  for i = 1, #times do
    if times[i] == target then return i end
  end
  return nil
end

local function setVar(name, value)
  SKIN:Bang('!SetVariable ' .. name .. ' "' .. value .. '"')
end

function Initialize()
  setVar("PressureActualAngle", "0")
  setVar("PressureNowHpa", "NA")
  setVar("PressureBaselineHpa", "NA")
  setVar("PressureDeltaBaselineHpa", "NA")
  setVar("PressureDelta3hHpa", "NA")
  setVar("PressureRateHpaHr", "NA")
end

function Update()
  local jsonPath = SKIN:GetVariable("OM_JSON", "")
  local json = readFile(jsonPath)
  if not json then
    return 0
  end

  -- Extract hourly object text (tolerant of ordering)
  local hourlyObj = json:match('%"hourly%"%s*:%s*%{(.-)%}%s*[,%}]')
  if not hourlyObj then
    return 0
  end

  local tBlock = findArrayBlock(hourlyObj, "time")
  local pBlock = findArrayBlock(hourlyObj, "pressure_msl")
  if not tBlock or not pBlock then
    return 0
  end

  local times = parseTimes(tBlock)
  local pres  = parseNumbers(pBlock)
  if #times == 0 or #pres == 0 then
    return 0
  end

  -- Open-Meteo hourly times are local when timezone=... is used in the request
  local nowHour  = os.date("%Y-%m-%dT%H:00")
  local pastHour = os.date("%Y-%m-%dT%H:00", os.time() - TREND_WINDOW_HOURS * 3600)

  local iNow  = findIndex(times, nowHour) or #times
  local iPast = findIndex(times, pastHour) or (iNow - TREND_WINDOW_HOURS)

  if iNow < 1 or iNow > #pres or iPast < 1 or iPast > #pres then
    return 0
  end

  local pNow  = pres[iNow]
  local pPast = pres[iPast]
  if not pNow or not pPast then
    return 0
  end

  -- Baseline = mean of last BASELINE_WINDOW_HOURS points ending at iNow
  local nBase = BASELINE_WINDOW_HOURS
  local start = iNow - (nBase - 1)
  if start < 1 then start = 1 end

  local sum, cnt = 0, 0
  for i = start, iNow do
    if pres[i] then
      sum = sum + pres[i]
      cnt = cnt + 1
    end
  end

  local baseline = (cnt > 0) and (sum / cnt) or 1013.25

  local dAbs = pNow - baseline               -- hPa
  local dp3  = pNow - pPast                  -- hPa over 3h
  local rate = dp3 / TREND_WINDOW_HOURS      -- hPa/hr

  -- LEFT needle angle: 0° at baseline, +/-90° at +/-MAX_ABS_DELTA_HPA
  local dAbsClamped = clamp(dAbs, -MAX_ABS_DELTA_HPA, MAX_ABS_DELTA_HPA)
  local absAngle = (dAbsClamped / MAX_ABS_DELTA_HPA) * 90.0  -- -90..+90

  -- RIGHT needle angle: 0° steady, +/-90° at +/-MAX_TREND_DP3H_HPA
  local dp3Clamped = clamp(dp3, -MAX_TREND_DP3H_HPA, MAX_TREND_DP3H_HPA)
  local trendAngle = (dp3Clamped / MAX_TREND_DP3H_HPA) * 90.0 -- -90..+90

  -- Export variables for meters/tooltips
  setVar("PressureActualAngle", string.format("%.1f", absAngle))
  setVar("PressureNowHpa", string.format("%.1f", pNow))
  setVar("PressureBaselineHpa", string.format("%.1f", baseline))
  setVar("PressureDeltaBaselineHpa", string.format("%+.1f", dAbs))
  setVar("PressureDelta3hHpa", string.format("%+.1f", dp3))
  setVar("PressureRateHpaHr", string.format("%+.2f", rate))

  return trendAngle
end

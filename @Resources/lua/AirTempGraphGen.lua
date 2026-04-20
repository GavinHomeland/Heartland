-- ============================
-- AirTempGraphGen.lua  (OM JSON -> 2m air temperature low bar+line graph)
-- Called after OM fetch completes; reads om.json directly.
--
-- Layout (22 columns: 14 past + today + 7 future):
--   z=back      : frame border, today indicator (bright), freeze line @ 32°F,
--                 grey reference lines for each future day column
--   z=back+1    : hi bars (temperature_2m_max) for all 22 columns
--   z=mid-back  : avg bars ((max+min)/2; today = currentTemp) for all 22 columns
--   z=mid-back+1: last night's low bar (min hourly temp_2m, 8pm-yesterday..8am-today)
--   z=mid       : freeze-fill patches (blue fill where polyline < 32°F)
--   z=mid-front : low bars (past 14 days only, not today)
--   z=front     : smooth 2px polyline connecting all 22 daily-low points
--
-- Also sets MeterAirTempDayLabels.Text with a Bresenham-spaced day-letter string.
--
-- Line color: single uniform color from minimum value across all 22 points (opaque).
-- Bar color : same gradient, hard break at 32°F (blue|yellow).
-- Color range: -20°F (white) .. 32°F (blue|yellow) .. 110°F (red).
-- Height: 1px/degree (-20..110°F = 130px).
-- Bars clamped to [minF, maxF]; no overflow outside frame.
--
-- Variables read from skin:
--   OM_JSON, W, Pad
--   AirTempGraphBarW, AirTempGraphBarGap, AirTempGraphH
--   AirTempGraphMinF, AirTempGraphMaxF
--   AirTempGraphLog, HeartlandLog
-- ============================

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function interpStops(stops, tempF)
  if tempF <= stops[1].t then return stops[1].r, stops[1].g, stops[1].b end
  local last = stops[#stops]
  if tempF >= last.t then return last.r, last.g, last.b end
  for i = 1, #stops - 1 do
    local a, b = stops[i], stops[i + 1]
    if tempF >= a.t and tempF <= b.t then
      local span = b.t - a.t
      local f    = (span == 0) and 0 or ((tempF - a.t) / span)
      return math.floor(lerp(a.r, b.r, f) + 0.5),
             math.floor(lerp(a.g, b.g, f) + 0.5),
             math.floor(lerp(a.b, b.b, f) + 0.5)
    end
  end
  return last.r, last.g, last.b
end

local function rgba(r, g, b, a)
  r = clamp(r,0,255); g = clamp(g,0,255); b = clamp(b,0,255); a = clamp(a,0,255)
  return string.format("%d,%d,%d,%d", r, g, b, a)
end

local function setShape(meterName, idx, shapeDef)
  if idx == 1 then
    SKIN:Bang("!SetOption", meterName, "Shape", shapeDef)
  else
    SKIN:Bang("!SetOption", meterName, "Shape" .. idx, shapeDef)
  end
end

local function appendLog(path, msg)
  if not path or path == "" then return end
  local f = io.open(path, "a")
  if f then f:write(msg .. "\n"); f:close() end
end

-- Wind speed color stops (mph): still→white, breeze→green, windy→yellow, max→red
local WIND_STOPS = {
  { t=  0, r=255, g=255, b=255 },  -- still: white
  { t= 15, r=  0, g=210, b=  0 },  -- light breeze: green
  { t= 25, r=255, g=220, b=  0 },  -- windy: yellow
  { t= 50, r=255, g= 40, b= 40 },  -- severe: red
}

-- Color stops: hard break at 32°F, range -20..110°F
local AIR_STOPS = {
  { t=-20, r=255, g=255, b=255 },
  { t=  0, r=180, g=210, b=255 },
  { t= 32, r=  0, g= 30, b=255 },  -- cold side at 32°F = blue
  { t= 32, r=255, g=220, b=  0 },  -- warm side at 32°F = yellow (hard break)
  { t= 36, r=255, g=220, b=  0 },
  { t= 45, r=  0, g=200, b=  0 },
  { t= 62, r=  0, g=200, b=  0 },
  { t= 75, r=255, g=165, b=  0 },
  { t= 86, r=255, g= 90, b=  0 },
  { t=110, r=255, g= 40, b= 40 },
}

-- Day-letter abbreviations: wday 1=Sun..7=Sat → "N M T W H F S"
local DAY_LETTERS = { [1]="N", [2]="M", [3]="T", [4]="W", [5]="H", [6]="F", [7]="S" }

-- ============================================================
-- LOG ROTATION (once per day; trims all log files to 1000 lines)
-- ============================================================
local lastRotateDay = ""

local function rotateLogFile(path, maxLines)
  if not path or path == "" then return end
  local f = io.open(path, "r")
  if not f then return end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  if #lines <= maxLines then return end
  local f2 = io.open(path, "w")
  if not f2 then return end
  for i = #lines - maxLines + 1, #lines do
    f2:write(lines[i] .. "\n")
  end
  f2:close()
end

local function rotateLogs()
  local today = os.date("%Y-%m-%d")
  if lastRotateDay == today then return end
  lastRotateDay = today
  rotateLogFile(SKIN:GetVariable("HeartlandLog",       ""), 1000)
  rotateLogFile(SKIN:GetVariable("AirTempGraphLog",    ""), 1000)
  rotateLogFile(SKIN:GetVariable("SoilGraphLog",       ""), 1000)
  rotateLogFile(SKIN:GetVariable("RainBucketsLog",     ""), 1000)
  rotateLogFile(SKIN:GetVariable("OM_FetchLog",        ""), 1000)
  rotateLogFile(SKIN:GetVariable("KSSoilFetchLog",     ""), 1000)
  rotateLogFile(SKIN:GetVariable("NWSAlerts_Log",      ""), 1000)
end

function Run()
  rotateLogs()
  local meterName = "MeterAirTempGraph"
  local logPath   = SKIN:GetVariable("AirTempGraphLog", "")
  local masterLog = SKIN:GetVariable("HeartlandLog", "")
  local startMsg  = os.date("%Y-%m-%d %H:%M:%S") .. " | AirTempGraphGen | Run Start"
  appendLog(logPath, startMsg)
  appendLog(masterLog, startMsg)

  -- Parameters
  local omJsonPath = SKIN:GetVariable("OM_JSON", "")
  local barW       = tonumber(SKIN:GetVariable("AirTempGraphBarW",  "8"))   or 8
  local barGap     = tonumber(SKIN:GetVariable("AirTempGraphBarGap", "1"))  or 1
  local graphH     = tonumber(SKIN:GetVariable("AirTempGraphH",    "150"))  or 150
  local maxF       = tonumber(SKIN:GetVariable("AirTempGraphMaxF",  "110")) or 110
  local pastDays   = 14
  local futureDays = 7
  local totalBars  = pastDays + 1 + futureDays  -- 22
  local graphW     = totalBars * barW + math.max(0, totalBars - 1) * barGap  -- 197
  local minF, rangeF = -20, 130  -- placeholders; overridden after data parse

  -- Read om.json
  local jsonContent = ""
  if omJsonPath ~= "" then
    local f = io.open(omJsonPath, "r")
    if f then jsonContent = f:read("*all"); f:close() end
  end
  if jsonContent == "" then
    local e = os.date("%Y-%m-%d %H:%M:%S") .. " | AirTempGraphGen | ERROR: om.json not readable"
    appendLog(logPath, e); appendLog(masterLog, e)
    return
  end

  -- Parse daily.temperature_2m_min
  local allMins = {}
  local minsStr = jsonContent:match('"temperature_2m_min"%s*:%s*%[([^%]]+)%]')
  if minsStr then
    for v in minsStr:gmatch("(-?%d+%.?%d*)") do allMins[#allMins + 1] = tonumber(v) end
  end

  -- Parse daily.temperature_2m_max
  local allMaxs = {}
  local maxsStr = jsonContent:match('"temperature_2m_max"%s*:%s*%[([^%]]+)%]')
  if maxsStr then
    for v in maxsStr:gmatch("(-?%d+%.?%d*)") do allMaxs[#allMaxs + 1] = tonumber(v) end
  end

  -- Parse daily.precipitation_sum (inches, per OM_MISC precipitation_unit=inch)
  local dailyPrecip = {}
  local precipStr = jsonContent:match('"precipitation_sum"%s*:%s*%[([^%]]+)%]')
  if precipStr then
    for v in precipStr:gmatch("([%d%.]+)") do dailyPrecip[#dailyPrecip + 1] = tonumber(v) or 0 end
  end

  -- Parse hourly.temperature_2m: find min in 8pm-yesterday .. 8am-today window
  local lastNightLow = nil
  do
    local hStart = jsonContent:find('"hourly"%s*:')
    if hStart then
      local hBlock    = jsonContent:sub(hStart)
      local hTimesStr = hBlock:match('"time"%s*:%s*%[([^%]]+)%]')
      local hTempsStr = hBlock:match('"temperature_2m"%s*:%s*%[([^%]]+)%]')
      if hTimesStr and hTempsStr then
        local hTimes, hTemps = {}, {}
        for ts   in hTimesStr:gmatch('"([^"]+)"')    do hTimes[#hTimes+1] = ts            end
        for tv   in hTempsStr:gmatch("(-?%d+%.?%d*)") do hTemps[#hTemps+1] = tonumber(tv) end
        local nowT = os.date("*t")
        local t8am = os.time({year=nowT.year, month=nowT.month, day=nowT.day,
                               hour=8, min=0, sec=0, isdst=nowT.isdst})
        local t8pm = t8am - 12 * 3600  -- 8pm yesterday
        for k, ts in ipairs(hTimes) do
          local temp = hTemps[k]
          if temp then
            local yr, mo, dy, hr = ts:match("(%d+)-(%d+)-(%d+)T(%d+):")
            if yr then
              local tt = os.time({year=tonumber(yr), month=tonumber(mo), day=tonumber(dy),
                                   hour=tonumber(hr), min=0, sec=0, isdst=nowT.isdst})
              if tt >= t8pm and tt <= t8am then
                if not lastNightLow or temp < lastNightLow then lastNightLow = temp end
              end
            end
          end
        end
      end
    end
  end

  -- Sum hourly.precipitation from midnight today up to current hour
  local todayFallenIn = 0
  do
    local hStart = jsonContent:find('"hourly"%s*:')
    if hStart then
      local hBlock     = jsonContent:sub(hStart)
      local hTimesStr  = hBlock:match('"time"%s*:%s*%[([^%]]+)%]')
      local hPrecipStr = hBlock:match('"precipitation"%s*:%s*%[([^%]]+)%]')
      if hTimesStr and hPrecipStr then
        local hTimes, hPrecips = {}, {}
        for ts in hTimesStr:gmatch('"([^"]+)"')      do hTimes[#hTimes+1]   = ts            end
        for pv in hPrecipStr:gmatch("([%d%.]+)")     do hPrecips[#hPrecips+1] = tonumber(pv) or 0 end
        local nowT      = os.date("*t")
        local midnightT = os.time({year=nowT.year, month=nowT.month, day=nowT.day,
                                    hour=0, min=0, sec=0, isdst=nowT.isdst})
        local nowEpoch  = os.time()
        for k, ts in ipairs(hTimes) do
          local yr, mo, dy, hr = ts:match("(%d+)-(%d+)-(%d+)T(%d+):")
          if yr then
            local tt = os.time({year=tonumber(yr), month=tonumber(mo), day=tonumber(dy),
                                 hour=tonumber(hr), min=0, sec=0, isdst=nowT.isdst})
            if tt >= midnightT and tt <= nowEpoch then
              todayFallenIn = todayFallenIn + (hPrecips[k] or 0)
            end
          end
        end
      end
    end
  end

  -- Find today's 1-based index in daily.time
  local today      = os.date("%Y-%m-%d")
  local todayIdx   = nil
  local dailyStart = jsonContent:find('"daily"%s*:')
  if dailyStart then
    local rest     = jsonContent:sub(dailyStart)
    local timesStr = rest:match('"time"%s*:%s*%[([^%]]+)%]')
    if timesStr then
      local i = 0
      for dateStr in timesStr:gmatch('"([%d%-]+)"') do
        i = i + 1
        if dateStr == today then todayIdx = i; break end
      end
    end
  end
  if not todayIdx then todayIdx = pastDays + 1 end

  -- Parse daily.wind_speed_10m_max and wind_gusts_10m_max
  local allWindSpeeds, allWindGusts = {}, {}
  local windSpeedStr = jsonContent:match('"wind_speed_10m_max"%s*:%s*%[([^%]]+)%]')
  if windSpeedStr then
    for v in windSpeedStr:gmatch("([%d%.]+)") do allWindSpeeds[#allWindSpeeds+1] = tonumber(v) or 0 end
  end
  local windGustStr = jsonContent:match('"wind_gusts_10m_max"%s*:%s*%[([^%]]+)%]')
  if windGustStr then
    for v in windGustStr:gmatch("([%d%.]+)") do allWindGusts[#allWindGusts+1] = tonumber(v) or 0 end
  end

  -- Parse current conditions from om_hrrr.json (HRRR: real-time, hourly updates)
  -- Falls back to om.json current block if HRRR file unavailable.
  local currentTemp, currentWindSpeed, currentWindGust, currentWindDir = nil, nil, nil, nil
  do
    local hrrrPath = SKIN:GetVariable("OM_HRRR_JSON", "")
    local hrrrContent = ""
    if hrrrPath ~= "" then
      local f = io.open(hrrrPath, "r")
      if f then hrrrContent = f:read("*all"); f:close() end
    end
    local src = (hrrrContent ~= "") and hrrrContent or jsonContent
    local curStart = src:find('"current"%s*:')
    if curStart then
      local curBlock = src:sub(curStart):match('%b{}')
      if curBlock then
        currentTemp      = tonumber(curBlock:match('"temperature_2m"%s*:%s*(-?%d+%.?%d*)'))
        currentWindSpeed = tonumber(curBlock:match('"wind_speed_10m"%s*:%s*(-?%d+%.?%d*)'))
        currentWindGust  = tonumber(curBlock:match('"wind_gusts_10m"%s*:%s*(-?%d+%.?%d*)'))
        currentWindDir   = tonumber(curBlock:match('"wind_direction_10m"%s*:%s*(-?%d+%.?%d*)'))
      end
    end
  end

  -- Build 22-point array (0-based): daily lows, nil if missing
  local points = {}
  for i = 0, totalBars - 1 do
    points[i] = allMins[(todayIdx - pastDays) + i]
  end

  -- Build hi and avg 22-point arrays (avg = (max+min)/2; today avg = currentTemp)
  local hiPoints  = {}
  local avgPoints = {}
  for i = 0, totalBars - 1 do
    local offset = (todayIdx - pastDays) + i
    local lo = points[i]
    local hi = allMaxs[offset]
    hiPoints[i] = hi
    if i == pastDays and currentTemp then
      avgPoints[i] = currentTemp
    elseif lo and hi then
      avgPoints[i] = (lo + hi) / 2
    else
      avgPoints[i] = lo or hi
    end
  end

  -- Dynamic floor: lowest value across all mins + current, padded 10°F, rounded down to 5°F
  local dataMin = nil
  for i = 0, totalBars - 1 do
    local v = points[i]
    if v and (not dataMin or v < dataMin) then dataMin = v end
  end
  if currentTemp and (not dataMin or currentTemp < dataMin) then dataMin = currentTemp end
  local minF
  if dataMin then
    minF = math.floor((dataMin - 20) / 5) * 5
  else
    minF = tonumber(SKIN:GetVariable("AirTempGraphMinF", "-20")) or -20
  end
  local rangeF = (maxF - minF <= 0) and 1 or (maxF - minF)

  -- Helpers
  local function tempToY(t)
    return math.floor(graphH - ((clamp(t, minF, maxF) - minF) / rangeF) * graphH + 0.5)
  end
  local function barLeftX(i)   return i * (barW + barGap) end
  local function barCenterX(i) return barLeftX(i) + math.floor(barW / 2) end

  -- ===== Build shapes =====
  local shapeIdx = 1

  -- Shape 1 (frame): visible rounded border; also sets meter bounding box
  setShape(meterName, shapeIdx,
    string.format("Rectangle 0,0,%d,%d,4 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color 255,255,255,90",
      graphW, graphH))
  shapeIdx = shapeIdx + 1

  -- Shape 2 (today indicator, z=back): bright vertical line, stops at top of hi bar
  local todayCX = barCenterX(pastDays)
  do
    local hiV = hiPoints[pastDays]
    local lineEnd = graphH
    if hiV then
      local h = math.floor(((clamp(hiV, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      lineEnd = graphH - h
    end
    setShape(meterName, shapeIdx,
      string.format("Line %d,0,%d,%d | StrokeWidth 1 | Stroke Color 230,240,255,220",
        todayCX, todayCX, lineEnd))
  end
  shapeIdx = shapeIdx + 1

  -- freezeY/warnY computed here; lines drawn at forefront (shapes 119, 123) below
  local freezeY = math.floor(graphH - (((32 - minF) / rangeF) * graphH) + 0.5)
  local warnY   = math.floor(graphH - (((34 - minF) / rangeF) * graphH) + 0.5)

  -- Shape (wind zero reference line, z=back): grey horizontal at 0 mph, today→end
  do
    local windBandH = graphH / 3.0
    local zeroY     = math.floor(windBandH + 10 + 0.5)
    local startX    = barLeftX(pastDays)
    setShape(meterName, shapeIdx,
      string.format("Line %d,%d,%d,%d | StrokeWidth 1 | Stroke Color 140,140,140,180",
        startX, zeroY, graphW, zeroY))
    shapeIdx = shapeIdx + 1
  end

  -- Shapes (future day reference lines, z=back): grey vertical, stops at top of hi bar
  for i = pastDays + 1, totalBars - 1 do
    local cx = barCenterX(i)
    local hiV = hiPoints[i]
    local lineEnd = graphH
    if hiV then
      local h = math.floor(((clamp(hiV, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      lineEnd = graphH - h
    end
    setShape(meterName, shapeIdx,
      string.format("Line %d,0,%d,%d | StrokeWidth 1 | Stroke Color 120,120,120,100",
        cx, cx, lineEnd))
    shapeIdx = shapeIdx + 1
  end

  -- Shapes (hi bars, z=back+1): daily high for all 22 columns
  for i = 0, totalBars - 1 do
    local v = hiPoints[i]
    if v then
      local h = math.floor(((clamp(v, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      if h < 1 then h = 1 end
      local r, g, b = interpStops(AIR_STOPS, v)
      local alpha = (i > pastDays) and 85 or 120
      setShape(meterName, shapeIdx,
        string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
          barLeftX(i), graphH - h, barW, h, rgba(r, g, b, alpha)))
      shapeIdx = shapeIdx + 1
    end
  end

  -- Shapes (avg bars, z=mid-back): (max+min)/2; today = currentTemp; all 22 columns
  for i = 0, totalBars - 1 do
    local v = avgPoints[i]
    if v then
      local h = math.floor(((clamp(v, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      if h < 1 then h = 1 end
      local r, g, b = interpStops(AIR_STOPS, v)
      local alpha = (i == pastDays) and 255 or (i > pastDays and 61 or 100)
      setShape(meterName, shapeIdx,
        string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
          barLeftX(i), graphH - h, barW, h, rgba(r, g, b, alpha)))
      shapeIdx = shapeIdx + 1
    end
  end

  -- Shape (last night's low, z=mid-back+1): min hourly temp_2m in 8pm-yesterday..8am-today
  do
    local v = lastNightLow
    if v then
      local h = math.floor(((clamp(v, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      if h < 1 then h = 1 end
      local r, g, b = interpStops(AIR_STOPS, v)
      setShape(meterName, shapeIdx,
        string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 1 | Stroke Color 0,0,0,150",
          barLeftX(pastDays), graphH - h, barW, h, rgba(r, g, b, 200)))
      shapeIdx = shapeIdx + 1
    end
  end

  -- Shapes (freeze-fill, z=mid): blue fill where polyline < 34°F (warn line)
  -- Rainmeter Path shapes require the path data in a SEPARATE named key on the meter.
  -- FreezePatch1..3 are pre-declared in the INI so Rainmeter recognises them.
  local patchNum = 0
  local pts = {}
  for i = 0, totalBars - 1 do
    local v = points[i]
    if v then pts[#pts + 1] = { x = barCenterX(i), y = tempToY(v), v = v }
    else       pts[#pts + 1] = false
    end
  end
  local j = 1
  while j <= #pts do
    local p = pts[j]
    if p and p.v < 34 then
      -- Entry: interpolate crossing with warn line from the previous point
      local enterX
      if j > 1 and pts[j-1] and pts[j-1].v >= 34 then
        local pr = pts[j-1]
        local t  = (34 - pr.v) / (p.v - pr.v)
        enterX = math.floor(pr.x + (p.x - pr.x) * t + 0.5)
      else
        enterX = p.x
      end
      -- Collect consecutive below-warn points
      local seg = {}
      while j <= #pts and pts[j] and pts[j].v < 34 do
        seg[#seg + 1] = pts[j]; j = j + 1
      end
      -- Exit: interpolate crossing back up
      local exitX
      if j <= #pts and pts[j] and pts[j].v >= 34 then
        local pr = seg[#seg]; local cu = pts[j]
        local t  = (34 - pr.v) / (cu.v - pr.v)
        exitX = math.floor(pr.x + (cu.x - pr.x) * t + 0.5)
      else
        exitX = seg[#seg].x
      end
      patchNum = patchNum + 1
      if patchNum <= 3 then
        -- Build path definition string for the named key
        local pathParts = { string.format("%d,%d", enterX, warnY) }
        for _, pt in ipairs(seg) do
          pathParts[#pathParts + 1] = string.format("LineTo %d,%d", pt.x, pt.y)
        end
        pathParts[#pathParts + 1] = string.format("LineTo %d,%d", exitX, warnY)
        pathParts[#pathParts + 1] = "ClosePath 1"
        local pathName = "FreezePatch" .. patchNum
        SKIN:Bang("!SetOption", meterName, pathName, table.concat(pathParts, " | "))
        -- shape drawn at forefront (shapes 120-122) below
      end
    else
      j = j + 1
    end
  end

  -- Shapes (low bars, z=mid-front): past 14 days daily low only (not today)
  for i = 0, pastDays - 1 do
    local v = points[i]
    if v then
      local h = math.floor(((clamp(v, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      if h < 1 then h = 1 end
      local r, g, b = interpStops(AIR_STOPS, v)
      setShape(meterName, shapeIdx,
        string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 1 | Stroke Color 0,0,0,150",
          barLeftX(i), graphH - h, barW, h, rgba(r, g, b, 200)))
      shapeIdx = shapeIdx + 1
    end
  end

  -- Find minimum value across all 22 line points for uniform line color
  local lineMinVal = nil
  for i = 0, totalBars - 1 do
    local v = points[i]
    if v and (not lineMinVal or v < lineMinVal) then lineMinVal = v end
  end
  local lineR, lineG, lineB = 200, 200, 200
  if lineMinVal then lineR, lineG, lineB = interpStops(AIR_STOPS, lineMinVal) end
  local lineColor = rgba(lineR, lineG, lineB, 255)

  -- Shapes (z=front): 2px polyline across all 22 daily-low points
  local prevX, prevY = nil, nil
  for i = 0, totalBars - 1 do
    local v = points[i]
    if v then
      local cx, cy = barCenterX(i), tempToY(v)
      if prevX then
        setShape(meterName, shapeIdx,
          string.format("Line %d,%d,%d,%d | StrokeWidth 2 | Stroke Color %s",
            prevX, prevY, cx, cy, lineColor))
        shapeIdx = shapeIdx + 1
      end
      prevX, prevY = cx, cy
    else
      prevX, prevY = nil, nil
    end
  end

  -- Cleanup leftover shapes (pre-declared up to 122 in INI)
  local maxShapes = 132
  local blank = "Line 0,0,0,0 | StrokeWidth 0"
  for j = shapeIdx, maxShapes do setShape(meterName, j, blank) end

  -- Shapes 111-118: precipitation bars (today + 7 forecast; forefront z)
  -- Scale: 2.0 in = full height; clamped at freeze line.
  -- Today (j=0): split bar — fallen (alpha 255) below, remaining forecast (alpha 140) above.
  local maxPrecipH = graphH - freezeY
  for j = 0, futureDays do
    local si = 111 + j
    local dailyIdx = todayIdx + j
    local precipIn = dailyPrecip[dailyIdx] or 0
    local barI = pastDays + j
    local bx = barI * (barW + barGap)
    if j == 0 then
      -- Today: split into fallen (solid) + remaining forecast (translucent)
      local fallen    = clamp(todayFallenIn, 0, precipIn)
      local remaining = math.max(0, precipIn - fallen)
      local hFallen   = math.floor(math.min(fallen    / 1.0, 1.0) * maxPrecipH + 0.5)
      local hRemain   = math.floor(math.min(remaining / 1.0, 1.0) * maxPrecipH + 0.5)
      if fallen    > 0.005 and hFallen  < 3 then hFallen  = 3 end
      if remaining > 0.005 and hRemain  < 3 then hRemain  = 3 end
      local hTotal = hFallen + hRemain
      -- Draw fallen portion (bottom): blue alpha 255
      if hFallen >= 1 then
        SKIN:Bang("!SetOption", meterName, "Shape" .. si, string.format(
          "Rectangle %d,%d,%d,%d | Fill Color 40,100,200,255 | StrokeWidth 0",
          bx, graphH - hFallen, barW, hFallen))
      else
        SKIN:Bang("!SetOption", meterName, "Shape" .. si, blank)
      end
      -- Draw remaining forecast portion (above fallen): cyan alpha 255
      if hRemain >= 1 then
        SKIN:Bang("!SetOption", meterName, "Shape131", string.format(
          "Rectangle %d,%d,%d,%d | Fill Color 0,200,220,255 | StrokeWidth 0",
          bx, graphH - hTotal, barW, hRemain))
      else
        SKIN:Bang("!SetOption", meterName, "Shape131", blank)
      end
    else
      local h = math.floor(math.min(precipIn / 1.0, 1.0) * maxPrecipH + 0.5)
      if precipIn > 0.005 and h < 3 then h = 3 end
      if h >= 1 then
        SKIN:Bang("!SetOption", meterName, "Shape" .. si, string.format(
          "Rectangle %d,%d,%d,%d | Fill Color 40,100,200,255 | StrokeWidth 0",
          bx, graphH - h, barW, h))
      else
        SKIN:Bang("!SetOption", meterName, "Shape" .. si, blank)
      end
    end
  end

  -- Shape 119: freeze line (forefront)
  setShape(meterName, 119, string.format("Line 0,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,0,0,255",
    freezeY, graphW, freezeY))

  -- Shapes 120-122: freeze-fill patches (forefront)
  for p = 1, 3 do
    if p <= patchNum then
      setShape(meterName, 119 + p, string.format(
        "Path FreezePatch%d | StrokeWidth 0 | Fill Color 255,0,0,255", p))
    else
      setShape(meterName, 119 + p, blank)
    end
  end

  -- Shape 123: yellow warning line at 34°F (forefront)
  setShape(meterName, 123, string.format("Line 0,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,220,0,210",
    warnY, graphW, warnY))

  -- Shapes 124-130: wind forecast polyline (today → +7), 7 segments
  -- Y=0 (top of graph) = MAX_WIND; rises up to graphH/3 at calm.
  -- Color: white; alpha = clamp(100 + avg_gust_mph_of_segment, 100, 200).
  -- Drawn at forefront z, above all other shapes.
  do
    local MAX_WIND = 50.0
    local windBandH = graphH / 3.0

    local function windToY(spd)
      local t = clamp(spd, 0, MAX_WIND) / MAX_WIND
      return math.floor((1 - t) * (windBandH + 10) + 0.5)
    end

    -- Build 8 points: today (i=pastDays) through today+7 (i=pastDays+futureDays)
    local wPts = {}
    for i = 0, futureDays do
      local barI   = pastDays + i
      local offset = (todayIdx - pastDays) + barI  -- 1-based into daily arrays
      local spd    = allWindSpeeds[offset] or 0
      local gst    = allWindGusts[offset]  or 0
      -- Today: average steady + gusts for both position and color
      if i == 0 then
        if currentWindSpeed and currentWindGust then
          spd = (currentWindSpeed + currentWindGust) / 2
        elseif currentWindSpeed then
          spd = currentWindSpeed
        end
        if currentWindGust then gst = currentWindGust end
      end
      wPts[i] = { x = barCenterX(barI), y = windToY(spd), spd = spd, gust = gst }
    end

    local windLog = string.format("WindLine pts: ")
    for i = 0, futureDays do
      if wPts[i] then
        windLog = windLog .. string.format("[%d x=%d y=%d g=%.1f] ", i, wPts[i].x, wPts[i].y, wPts[i].gust)
      end
    end
    appendLog(logPath, os.date("%Y-%m-%d %H:%M:%S") .. " | AirTempGraphGen | " .. windLog)

    -- Export next 3 days' wind forecast + pre-bake stable tooltip on overlay meter
    local DAY_ABBR    = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}
    local CARDINALS   = {"N","NE","E","SE","S","SW","W","NW"}
    local function cardinalFromDeg(d)
      return CARDINALS[math.floor((d % 360 + 22.5) / 45) % 8 + 1]
    end
    for i = 1, 3 do
      if wPts[i] then
        local t   = os.time() + i * 86400
        local dow = os.date("*t", t).wday
        SKIN:Bang("!SetVariable", "WindFcstDay" .. i, DAY_ABBR[dow])
        SKIN:Bang("!SetVariable", "WindFcstSpd" .. i, string.format("%.0f", wPts[i].spd))
        SKIN:Bang("!SetVariable", "WindFcstGst" .. i, string.format("%.0f", wPts[i].gust))
      end
    end
    -- Compose pre-baked tooltip (set once per OM fetch on stable overlay meter)
    local tipSpd = currentWindSpeed and string.format("%.0f", currentWindSpeed) or "?"
    local tipGst = currentWindGust  and string.format("%.0f", currentWindGust)  or "?"
    local tipDir = currentWindDir   and string.format(" %s (%d\176)", cardinalFromDeg(currentWindDir), math.floor(currentWindDir)) or ""
    local windTip = string.format("Wind: %s mph%s  Gusts: %s mph", tipSpd, tipDir, tipGst)
    for i = 1, 3 do
      if wPts[i] then
        local t   = os.time() + i * 86400
        local dow = os.date("*t", t).wday
        windTip = windTip .. string.format("\n%s: %.0f-%.0f mph", DAY_ABBR[dow], wPts[i].spd, wPts[i].gust)
      end
    end
    SKIN:Bang("!SetOption",  "MeterWindArrowTip", "ToolTipText", windTip)
    SKIN:Bang("!UpdateMeter","MeterWindArrowTip")

    -- Draw 7 segments (i to i+1); color varies by avg speed (still→white, breeze→green, windy→yellow, max→red)
    for i = 0, futureDays - 1 do
      local p0, p1 = wPts[i], wPts[i + 1]
      if p0 and p1 then
        local avgSpd  = (p0.spd + p1.spd) / 2
        local wr, wg, wb = interpStops(WIND_STOPS, avgSpd)
        setShape(meterName, 124 + i, string.format(
          "Line %d,%d,%d,%d | StrokeWidth 2 | Stroke Color %d,%d,%d,220",
          p0.x, p0.y, p1.x, p1.y, wr, wg, wb))
      else
        setShape(meterName, 124 + i, blank)
      end
    end

    -- Shape 132: today sustained→gust range cap (2px vertical whisker, colored by gust speed)
    if currentWindSpeed and currentWindGust and currentWindGust > currentWindSpeed then
      local ySpd = windToY(currentWindSpeed)
      local yGst = windToY(currentWindGust)
      local cx   = barCenterX(pastDays)
      local gr, gg, gb = interpStops(WIND_STOPS, currentWindGust)
      setShape(meterName, 132, string.format(
        "Line %d,%d,%d,%d | StrokeWidth 2 | Stroke Color %d,%d,%d,220",
        cx, yGst, cx, ySpd, gr, gg, gb))
    else
      setShape(meterName, 132, blank)
    end
  end

  -- ===== Day-label meters: today + every-other future day =====
  -- Each meter is individually positioned at the bar center X in the ini.
  -- barCenterX(i) = i*9 + 4  (barW=8, barGap=1)
  local labelMeterMap = {
    { barIdx = pastDays,     meter = "MeterAirTempDayLabelToday" },
    { barIdx = pastDays + 1, meter = "MeterAirTempDayLabelF1"   },
    { barIdx = pastDays + 3, meter = "MeterAirTempDayLabelF3"   },
    { barIdx = pastDays + 5, meter = "MeterAirTempDayLabelF5"   },
    { barIdx = pastDays + 7, meter = "MeterAirTempDayLabelF7"   },
  }
  for _, entry in ipairs(labelMeterMap) do
    local daysOffset = entry.barIdx - pastDays
    local t   = os.time() + daysOffset * 86400
    local dow = os.date("*t", t).wday
    local letter = DAY_LETTERS[dow] or "?"
    SKIN:Bang("!SetOption", entry.meter, "Text", letter)
    SKIN:Bang("!UpdateMeter", entry.meter)
  end

  -- ===== Tooltip =====
  local hxMin = nil
  for i = 0, pastDays - 1 do
    local v = points[i]
    if v and (not hxMin or v < hxMin) then hxMin = v end
  end
  local futureMin = nil
  for i = pastDays + 1, totalBars - 1 do
    local v = points[i]
    if v and (not futureMin or v < futureMin) then futureMin = v end
  end
  -- currentTemp is the live reading used for the today bar; fall back to today's daily min
  local currentDisplay = currentTemp or points[pastDays]
  local tip = string.format(
    "Today High: %s\176F\nHx Low: %s\176F\nLast Night Low: %s\176F\nCurrent: %s\176F\nPredicted Low: %s\176F",
    hiPoints[pastDays] and string.format("%.1f", hiPoints[pastDays]) or "n/a",
    hxMin          and string.format("%.1f", hxMin)          or "n/a",
    lastNightLow   and string.format("%.1f", lastNightLow)   or "n/a",
    currentDisplay and string.format("%.1f", currentDisplay) or "n/a",
    futureMin      and string.format("%.1f", futureMin)      or "n/a"
  )
  SKIN:Bang("!SetOption", meterName, "ToolTipText", tip)
  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")

  local endMsg = os.date("%Y-%m-%d %H:%M:%S") .. " | AirTempGraphGen | Run Complete"
  appendLog(logPath, endMsg)
  appendLog(masterLog, endMsg)
  SKIN:Bang("!Log", "--- AirTempGraphGen: Run Complete ---", "Notice")
end

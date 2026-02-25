-- ============================
-- AirTempGraphGen.lua  (OM JSON -> 2m air temperature low bar+line graph)
-- Called after OM fetch completes; reads om.json directly.
--
-- Layout (22 columns: 14 past + today + 7 future):
--   z=back  : frame border, today indicator (bright), freeze line @ 32°F,
--             grey reference lines for each future day column
--   z=mid   : bars for past 14 days (daily low) + today (current air temp)
--   z=front : smooth 2px polyline connecting all 22 daily-low points
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

function Run()
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
  local graphH     = tonumber(SKIN:GetVariable("AirTempGraphH",    "130"))  or 130
  local minF       = tonumber(SKIN:GetVariable("AirTempGraphMinF",  "-20")) or -20
  local maxF       = tonumber(SKIN:GetVariable("AirTempGraphMaxF",  "110")) or 110
  local pastDays   = 14
  local futureDays = 7
  local totalBars  = pastDays + 1 + futureDays  -- 22
  local rangeF     = (maxF - minF <= 0) and 1 or (maxF - minF)
  local graphW     = totalBars * barW + math.max(0, totalBars - 1) * barGap  -- 197

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

  -- Parse current.temperature_2m
  local currentTemp = nil
  local curStart = jsonContent:find('"current"%s*:')
  if curStart then
    local curBlock = jsonContent:sub(curStart):match('%b{}')
    if curBlock then
      currentTemp = tonumber(curBlock:match('"temperature_2m"%s*:%s*(-?%d+%.?%d*)'))
    end
  end

  -- Build 22-point array (0-based): daily lows, nil if missing
  local points = {}
  for i = 0, totalBars - 1 do
    points[i] = allMins[(todayIdx - pastDays) + i]
  end

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

  -- Shape 2 (today indicator, z=back): bright vertical line
  local todayCX = barCenterX(pastDays)
  setShape(meterName, shapeIdx,
    string.format("Line %d,0,%d,%d | StrokeWidth 1 | Stroke Color 230,240,255,220",
      todayCX, todayCX, graphH))
  shapeIdx = shapeIdx + 1

  -- Shape 3 (freeze line, z=back): red horizontal at 32°F
  local freezeY = math.floor(graphH - (((32 - minF) / rangeF) * graphH) + 0.5)
  setShape(meterName, shapeIdx,
    string.format("Line 0,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,0,0,210",
      freezeY, graphW, freezeY))
  shapeIdx = shapeIdx + 1

  -- Shapes 4-10 (future day reference lines, z=back): grey vertical at each future day center
  for i = pastDays + 1, totalBars - 1 do
    local cx = barCenterX(i)
    setShape(meterName, shapeIdx,
      string.format("Line %d,0,%d,%d | StrokeWidth 1 | Stroke Color 120,120,120,150",
        cx, cx, graphH))
    shapeIdx = shapeIdx + 1
  end

  -- Shapes (z=mid): bars for positions 0..pastDays (past 14 + today)
  for i = 0, pastDays do
    local tempForBar
    if i == pastDays and currentTemp then
      tempForBar = currentTemp
    else
      tempForBar = points[i]
    end
    if tempForBar then
      local h = math.floor(((clamp(tempForBar, minF, maxF) - minF) / rangeF) * graphH + 0.5)
      if h < 1 then h = 1 end
      local r, g, b = interpStops(AIR_STOPS, tempForBar)
      local alpha = (i == pastDays) and 255 or 200
      setShape(meterName, shapeIdx,
        string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 1 | Stroke Color 0,0,0,150",
          barLeftX(i), graphH - h, barW, h, rgba(r, g, b, alpha)))
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

  -- Cleanup leftover shapes
  local maxShapes = totalBars * 3 + 20
  for j = shapeIdx, maxShapes do setShape(meterName, j, "") end

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
  local todayLow  = points[pastDays]
  local futureMin = nil
  for i = pastDays + 1, totalBars - 1 do
    local v = points[i]
    if v and (not futureMin or v < futureMin) then futureMin = v end
  end
  local tip = string.format(
    "Hx Low: %s\176F\nCurrent: %s\176F\nPredicted Low: %s\176F",
    hxMin     and string.format("%.1f", hxMin)     or "n/a",
    todayLow  and string.format("%.1f", todayLow)  or "n/a",
    futureMin and string.format("%.1f", futureMin) or "n/a"
  )
  SKIN:Bang("!SetOption", meterName, "ToolTipText", tip)
  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")

  local endMsg = os.date("%Y-%m-%d %H:%M:%S") .. " | AirTempGraphGen | Run Complete"
  appendLog(logPath, endMsg)
  appendLog(masterLog, endMsg)
  SKIN:Bang("!Log", "--- AirTempGraphGen: Run Complete ---", "Notice")
end

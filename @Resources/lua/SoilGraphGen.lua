-- ============================
-- SoilGraphGen.lua (Rolling CSV -> dual-series Shape bars)
-- NOTE: Do not alter graph drawing code or soil data structure without checking first.
-- CSV format (rolling): date,min7F,avg7F
--
-- Draw order (back -> front):
--   1) Frame
--   2) Avg7F bars (back)
--   3) Min7F bars (front)
--   4) Freeze line @ 32°F (red, on top)
--
-- Variables read from skin:
--   SoilHistCsv          : rolling CSV path
--   SoilGraphDays        : number of trailing rows to graph
--   SoilGraphBarW        : bar width
--   SoilGraphBarGap      : gap between bars
--   SoilGraphH           : graph height in pixels
--   SoilGraphMinF        : Y-axis floor (we force <= 20°F for this graph)
--   SoilGraphMaxF        : Y-axis ceiling (we force >= 90°F)
--   SoilGraphMinPalette  : "Heat" (default), "Same", or "ColdClamp"
--
-- Requested behavior:
-- - Y-axis should extend to 20°F, but bar *height* clamps at 25°F (no shorter than 25°F).
-- - Color has a hard break at freezing:
--     warm side at 32°F = YELLOW
--     cold side at 32°F = BLUE
--   then BLUE gradients to WHITE as it approaches 25°F.
-- - Hard clamp for colors: <=25°F and >=90°F.
-- ============================

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitCSV(line)
  local t = {}
  for chunk in (line .. ","):gmatch("(.-),") do
    t[#t + 1] = trim(chunk)
  end
  return t
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function isHeader(fields)
  if #fields < 3 then return true end
  local f1 = (fields[1] or ""):upper()
  if f1 == "DATE" or f1 == "TIMESTAMP" then return true end
  local v2 = tonumber(fields[2] or "")
  local v3 = tonumber(fields[3] or "")
  return (v2 == nil) and (v3 == nil)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function interpStops(stops, tempF)
  if tempF <= stops[1].t then
    return stops[1].r, stops[1].g, stops[1].b
  end
  local last = stops[#stops]
  if tempF >= last.t then
    return last.r, last.g, last.b
  end

  for i = 1, (#stops - 1) do
    local a = stops[i]
    local b = stops[i + 1]
    if tempF >= a.t and tempF <= b.t then
      local span = (b.t - a.t)
      local f = (span == 0) and 0 or ((tempF - a.t) / span)
      local r = lerp(a.r, b.r, f)
      local g = lerp(a.g, b.g, f)
      local bb = lerp(a.b, b.b, f)
      return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(bb + 0.5)
    end
  end

  return last.r, last.g, last.b
end

local function rgba(r, g, b, a)
  r = clamp(r, 0, 255); g = clamp(g, 0, 255); b = clamp(b, 0, 255); a = clamp(a, 0, 255)
  return string.format("%d,%d,%d,%d", r, g, b, a)
end

-- FREEZE BREAK DESIGN:
-- 25°F = WHITE
-- 32°F (cold side) = BLUE
-- 32°F (warm side) = YELLOW  (duplicate t=32 makes an abrupt color jump)

-- Avg palette: WHITE (25) -> BLUE (32-) | YELLOW (32+) -> GREEN -> ORANGE -> RED
local AVG_STOPS = {
  { t=25, r=255, g=255, b=255 },  -- 25°F = white (cold floor for colors)
  { t=32, r=0,   g=30,  b=255 },  -- cold side at 32°F = blue
  { t=32, r=255, g=220, b=0   },  -- warm side at 32°F = yellow (abrupt jump)
  { t=36, r=255, g=220, b=0   },  -- hold yellow briefly
  { t=45, r=0,   g=200, b=0   },  -- ramp to green by mid-40s
  { t=62, r=0,   g=200, b=0   },  -- keep green through low 60s
  { t=75, r=255, g=165, b=0   },
  { t=86, r=255, g=90,  b=0   },
  { t=90, r=255, g=40,  b=40  },
}


-- Min palette (Heat): slightly darker green than AVG, still reaches orange/red
local MIN_STOPS_HEAT = {
  { t=25, r=255, g=255, b=255 },
  { t=32, r=0,   g=30,  b=255 },
  { t=32, r=255, g=220, b=0   },
  { t=36, r=255, g=220, b=0   },
  { t=45, r=0,   g=180, b=0   },  -- slightly darker green than AVG
  { t=62, r=0,   g=180, b=0   },
  { t=75, r=255, g=165, b=0   },
  { t=86, r=255, g=90,  b=0   },
  { t=90, r=255, g=40,  b=40  },
}


-- Min palette (ColdClamp): emphasizes cold risk; warm mins stay green
local MIN_STOPS_COLDCLAMP = {
  { t=25, r=255, g=255, b=255 },
  { t=32, r=0,   g=30,  b=255 },
  { t=32, r=255, g=220, b=0   },
  { t=36, r=255, g=220, b=0   },
  { t=45, r=0,   g=200, b=0   },
  { t=90, r=0,   g=200, b=0   },
}


local function setShape(meterName, idx, shapeDef)
  if idx == 1 then
    SKIN:Bang("!SetOption", meterName, "Shape", shapeDef)
  else
    SKIN:Bang("!SetOption", meterName, "Shape" .. idx, shapeDef)
  end
end

-- Append a line to a log file
local function appendLog(path, msg)
  if not path or path == "" then return end
  local f = io.open(path, "a")
  if f then f:write(msg .. "\n"); f:close() end
end

function Run()
  local meterName = "MeterSoilGraph"
  local logPath    = SKIN:GetVariable("SoilGraphLog", "")
  local masterLog  = SKIN:GetVariable("HeartlandLog", "")
  local startMsg   = os.date("%Y-%m-%d %H:%M:%S") .. " | SoilGraphGen | Run Start"
  appendLog(logPath, startMsg)
  appendLog(masterLog, startMsg)
  --print("--- SoilGraph: Run Start ---")

  -- 1. Load Paths
  local file             = SKIN:GetVariable("SoilHistCsv", "")
  local lastAttemptFile  = SKIN:GetVariable("SoilLastAttemptFile", "")
  --print("CSV Path: " .. file)
  --print("Log Path: " .. lastAttemptFile)

  -- 2. Variables
  local days     = tonumber(SKIN:GetVariable("SoilGraphDays", "45")) or 45
  local barW     = tonumber(SKIN:GetVariable("SoilGraphBarW", "2")) or 2
  local barGap   = tonumber(SKIN:GetVariable("SoilGraphBarGap", "0")) or 0
  local graphH   = tonumber(SKIN:GetVariable("SoilGraphH", "65")) or 65
  local minF_in  = tonumber(SKIN:GetVariable("SoilGraphMinF", "20")) or 20
  local maxF_in  = tonumber(SKIN:GetVariable("SoilGraphMaxF", "90")) or 90

  -- 3. Extract Timestamp from Log
local lastUpdatedStr = "n/a"
  local frameColor = "255,255,255,90" 
  
  local fhLog = io.open(lastAttemptFile, "r")
  if fhLog then
    local content = fhLog:read("*all")
    -- Matches the PowerShell format: OK YYYY-MM-DDTHH:MM:SS
    local year, month, day, hour, min, sec = content:match("OK%s+(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    
    if year then
      -- Calculate Age for Frame Color logic
      local lastTime = os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
      local diffHours = os.difftime(os.time(), lastTime) / 3600

      -- Jan 31 @ 15:13 format
      local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
      lastUpdatedStr = string.format("%s %d @ %02d:%02d", months[tonumber(month)], tonumber(day), hour, min)
      
      -- Alert logic
      if diffHours >= 26 then frameColor = "255,0,0,200"    -- Red
      elseif diffHours >= 24 then frameColor = "255,255,0,200"  -- Yellow
      end
    end
    fhLog:close()
  end
  -- 4. Read CSV
  local rows = {}
  local fhCsv = io.open(file, "r")
  if fhCsv then
    local lineCount = 0
    for line in fhCsv:lines() do
      lineCount = lineCount + 1
      line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" then
        local fields = splitCSV(line)
        if not isHeader(fields) then
          local vMin = tonumber(fields[2] or "")
          local vAvg = tonumber(fields[3] or "")
          if vMin or vAvg then
            rows[#rows + 1] = { min7 = vMin, avg7 = vAvg }
          end
        end
      end
    end
    fhCsv:close()
    --print("CSV Processing: Read " .. lineCount .. " lines, kept " .. #rows .. " data rows.")
  else
    --print("Error: Could not open CSV file.")
  end

  -- 5. Graph Limits
  if #rows > days then
    local sliced = {}
    for i = (#rows - days + 1), #rows do sliced[#sliced + 1] = rows[i] end
    rows = sliced
  end
  local n = #rows
  local graphW = (n > 0) and ((n * barW) + ((n - 1) * barGap)) or 1
  --print("Graphing " .. n .. " bars. Width: " .. graphW .. "px")

  -- 6. Shapes
  local idx = 1
  local minF = (minF_in > 20) and 20 or minF_in
  local maxF = (maxF_in < 90) and 90 or maxF_in
  local rangeF = (maxF - minF <= 0) and 1 or (maxF - minF)

-- Frame
  local frame = string.format("Rectangle 0,0,%d,%d,4 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color %s", graphW, graphH, frameColor)
  setShape(meterName, idx, frame)
  idx = idx + 1

  -- Current Reading Bar (rightmost position, drawn FIRST so it's behind avg/min)
  local currentTemp = nil
  local masterPath = SKIN:GetVariable("KSSoilMasterCsv", "")
  if masterPath ~= "" then
    local mf = io.open(masterPath, "r")
    if mf then
      local lastLine = nil
      for line in mf:lines() do
        line = trim(line)
        if line ~= "" and not line:match("^date,") then
          lastLine = line
        end
      end
      mf:close()
      
      if lastLine then
        local fields = splitCSV(lastLine)
        currentTemp = tonumber(fields[2] or "")
      end
    end
  end

  if currentTemp then
    local h = math.floor(((clamp(currentTemp, 25, maxF) - minF) / rangeF) * graphH + 0.5)
    local r, g, b = interpStops(AVG_STOPS, clamp(currentTemp, 25, 90))
    -- Position at the rightmost rolling bar position (n-1)
    local xPos = (n - 1) * (barW + barGap)
    setShape(meterName, idx, string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 1 | Stroke Color 100,100,100,100", xPos, graphH-h, barW, h, rgba(r,g,b,255)))
    idx = idx + 1
  end

  -- Bars (avg/min will draw on top of current bar)
  for i = 1, n do
    -- Avg Bar
    if rows[i].avg7 then
      local h = math.floor(((clamp(rows[i].avg7, 25, maxF) - minF) / rangeF) * graphH + 0.5)
      local r, g, b = interpStops(AVG_STOPS, clamp(rows[i].avg7, 25, 90))
      setShape(meterName, idx, string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0", (i-1)*(barW+barGap), graphH-h, barW, h, rgba(r,g,b,110)))
      idx = idx + 1
    end
    -- Min Bar
    if rows[i].min7 then
      local h = math.floor(((clamp(rows[i].min7, 25, maxF) - minF) / rangeF) * graphH + 0.5)
      local r, g, b = interpStops(MIN_STOPS_HEAT, clamp(rows[i].min7, 25, 90))
      setShape(meterName, idx, string.format("Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 1 | Stroke Color 0,0,0,70", (i-1)*(barW+barGap), graphH-h, barW, h, rgba(r,g,b,200)))
      idx = idx + 1
    end
  end
  -- Freeze Line
  local freezeY = math.floor(graphH - (((32 - minF) / rangeF) * graphH) + 0.5)
  setShape(meterName, idx, string.format("Line 0,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,0,0,210", freezeY, graphW, freezeY))
  --print("Final Shape Index: " .. idx)

  -- Cleanup
  local maxShapes = (2 * days) + 15
  for j = idx + 1, maxShapes do setShape(meterName, j, "") end

-- Tooltip
local last = rows[n] or {}

-- Read current temp from master CSV (last entry)
local currentTemp = "n/a"
local masterPath = SKIN:GetVariable("KSSoilMasterCsv", "")
if masterPath ~= "" then
  local mf = io.open(masterPath, "r")
  if mf then
    local lastLine = nil
    for line in mf:lines() do
      line = trim(line)
      if line ~= "" and not line:match("^date,") then
        lastLine = line
      end
    end
    mf:close()
    
    if lastLine then
      local fields = splitCSV(lastLine)
      local avgF = tonumber(fields[2] or "")
      if avgF then
        currentTemp = string.format("%.1f", avgF)
      end
    end
  end
end

local tip = string.format(
  "Albert, KS soil (2\") - 7 day readings\n%s - Current: %s\176F\navg: %s\176F    min: %s\176F",
  lastUpdatedStr,
  currentTemp,
  (last.avg7 and string.format("%.1f", last.avg7) or "n/a"),
  (last.min7 and string.format("%.1f", last.min7) or "n/a")
)
  -- Final update to Rainmeter
  SKIN:Bang("!SetOption", meterName, "ToolTipText", tip)
  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")

  local endMsg = os.date("%Y-%m-%d %H:%M:%S") .. " | SoilGraphGen | Run Complete"
  appendLog(logPath, endMsg)
  appendLog(masterLog, endMsg)
  SKIN:Bang("!Log", "--- SoilGraphGen: Run Complete ---", "Notice")
end -- This closes the function Run()
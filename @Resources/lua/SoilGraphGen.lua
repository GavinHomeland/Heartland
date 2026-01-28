-- ============================
-- SoilGraphGen.lua (Rolling CSV -> dual-series Shape bars)
-- Target CSV format: date,min7F,avg7F
--
-- Draw order (back -> front):
--   1) Frame
--   2) 32°F freeze line (red)
--   3) Avg7F bars (back, muted)
--   4) Min7F bars (front, stronger + optional cold palette)
--
-- Variables read from skin:
--   SoilHistCsv       : rolling CSV path
--   SoilGraphDays     : number of trailing rows to graph
--   SoilGraphBarW     : bar width
--   SoilGraphBarGap   : gap between bars
--   SoilGraphH        : graph height in pixels
--   SoilGraphMinF     : nominal floor (will be forced <= 25)
--   SoilGraphMaxF     : nominal ceiling (will be forced >= 90)
--   SoilGraphMinPalette : "Cold" (default) or "Same"
--
-- Writes shapes into: [MeterSoilGraph]
-- ============================

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitCSV(line)
  local t = {}
  -- Simple CSV split (no quoted commas needed for our files)
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
  -- We expect numeric in col2/col3 (min7F/avg7F). If both aren't numeric, treat as junk/header.
  local v2 = tonumber(fields[2] or "")
  local v3 = tonumber(fields[3] or "")
  if (v2 == nil) and (v3 == nil) then return true end
  return false
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

  -- Fallback (should never hit)
  return last.r, last.g, last.b
end

local function rgba(r, g, b, a)
  -- clamp channels just in case
  r = clamp(r, 0, 255); g = clamp(g, 0, 255); b = clamp(b, 0, 255); a = clamp(a, 0, 255)
  return string.format("%d,%d,%d,%d", r, g, b, a)
end

-- Avg palette: blue -> white(32F) -> yellow -> green -> red (hot)
local AVG_STOPS = {
  { t=25, r=0,   g=60,  b=180 },
  { t=29, r=0,   g=130, b=255 },
  { t=32, r=255, g=255, b=255 }, -- freezing anchor
  { t=40, r=255, g=220, b=0   },
  { t=62, r=0,   g=200, b=0   },
  { t=75, r=255, g=165, b=0   },
  { t=86, r=255, g=90,  b=0   },
  { t=90, r=255, g=40,  b=40  },
}

-- Min palette (default): cold-emphasis, stays green when warm (no "hot red" for minimums)
local MIN_STOPS_COLD = {
  { t=25, r=0,   g=60,  b=180 },
  { t=29, r=0,   g=130, b=255 },
  { t=32, r=255, g=255, b=255 }, -- freezing anchor
  { t=40, r=255, g=220, b=0   },
  { t=55, r=0,   g=200, b=0   },
  { t=90, r=0,   g=200, b=0   }, -- clamp warm minimums to green
}

local function setShape(meterName, idx, shapeDef)
  if idx == 1 then
    SKIN:Bang("!SetOption", meterName, "Shape", shapeDef)
  else
    SKIN:Bang("!SetOption", meterName, "Shape" .. idx, shapeDef)
  end
end

function Run()
  local meterName = "MeterSoilGraph"

  local file       = SKIN:GetVariable("SoilHistCsv", "")
  local days       = tonumber(SKIN:GetVariable("SoilGraphDays", "45")) or 45
  local barW       = tonumber(SKIN:GetVariable("SoilGraphBarW", "2")) or 2
  local barGap     = tonumber(SKIN:GetVariable("SoilGraphBarGap", "0")) or 0
  local graphH     = tonumber(SKIN:GetVariable("SoilGraphH", "65")) or 65

  local minF_in    = tonumber(SKIN:GetVariable("SoilGraphMinF", "25")) or 25
  local maxF_in    = tonumber(SKIN:GetVariable("SoilGraphMaxF", "90")) or 90

  -- Hard floor/ceiling enforcement requested:
  --   floor must be <= 25, ceiling must be >= 90
  local minF = (minF_in > 25) and 25 or minF_in
  local maxF = (maxF_in < 90) and 90 or maxF_in

  local rangeF = maxF - minF
  if rangeF == 0 then rangeF = 1 end

  local minPalette = (SKIN:GetVariable("SoilGraphMinPalette", "Cold") or "Cold"):upper()
  local MIN_STOPS = (minPalette == "SAME") and AVG_STOPS or MIN_STOPS_COLD

  -- Read rows: date,min7F,avg7F
  local rows = {}
  local fh = io.open(file, "r")
  if fh then
    for line in fh:lines() do
      line = line:gsub("^\239\187\191", "") -- strip UTF-8 BOM if present
      line = trim(line)
      if line ~= "" then
        local fields = splitCSV(line)
        if not isHeader(fields) then
          local d   = fields[1] or ""
          local vMin = tonumber(fields[2] or "")
          local vAvg = tonumber(fields[3] or "")
          if (vMin ~= nil) or (vAvg ~= nil) then
            rows[#rows + 1] = { date = d, min7 = vMin, avg7 = vAvg }
          end
        end
      end
    end
    fh:close()
  end

  -- Keep only last N rows
  if #rows > days then
    local start = #rows - days + 1
    local sliced = {}
    for i = start, #rows do sliced[#sliced + 1] = rows[i] end
    rows = sliced
  end

  local n = #rows
  local graphW = (n > 0) and ((n * barW) + ((n - 1) * barGap)) or 1
  -- Build shapes in draw order (later shapes draw on top)
  local idx = 1

  -- 1) Frame
  local frame = string.format(
    "Rectangle 0,0,%d,%d,4 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color 255,255,255,90",
    graphW, graphH
  )
  setShape(meterName, idx, frame)
  idx = idx + 1

  -- Colors / styles
  local avgAlpha = 110
  local minAlpha = 210
  local minStroke = " | StrokeWidth 1 | Stroke Color 0,0,0,70"

  -- 2) Avg bars (back)
  for i = 1, n do
    local v = rows[i].avg7
    if v ~= nil then
      v = clamp(v, 25, 90) -- hard clamp for color meaning
      local vv = clamp(v, minF, maxF) -- clamp for height scaling
      local frac = (vv - minF) / rangeF
      local h = math.floor((frac * graphH) + 0.5)
      if h < 1 then h = 1 end
      if h > graphH then h = graphH end

      local x = (i - 1) * (barW + barGap)
      local y = graphH - h

      local r, g, b = interpStops(AVG_STOPS, v)
      local color = rgba(r, g, b, avgAlpha)

      local bar = string.format(
        "Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
        x, y, barW, h, color
      )
      setShape(meterName, idx, bar)
      idx = idx + 1
    end
  end

  -- 3) Min bars (front)
  for i = 1, n do
    local v = rows[i].min7
    if v ~= nil then
      v = clamp(v, 25, 90) -- hard clamp for color meaning
      local vv = clamp(v, minF, maxF) -- clamp for height scaling
      local frac = (vv - minF) / rangeF
      local h = math.floor((frac * graphH) + 0.5)
      if h < 1 then h = 1 end
      if h > graphH then h = graphH end

      local x = (i - 1) * (barW + barGap)
      local y = graphH - h

      local r, g, b = interpStops(MIN_STOPS, v)
      local color = rgba(r, g, b, minAlpha)

      local bar = string.format(
        "Rectangle %d,%d,%d,%d,0 | Fill Color %s%s",
        x, y, barW, h, color, minStroke
      )
      setShape(meterName, idx, bar)
      idx = idx + 1
    end
  end

  -- 4) Freeze line @ 32°F (red) — drawn last so it sits on top
  local freezeF = 32.0
  local freezeClamped = clamp(freezeF, minF, maxF)
  local freezeFrac = (freezeClamped - minF) / rangeF
  local freezeY = math.floor((graphH - (freezeFrac * graphH)) + 0.5)
  local freezeLine = string.format(
    "Line 0,%d,%d,%d | StrokeWidth 1 | Stroke Color 255,0,0,210",
    freezeY, graphW, freezeY
  )
  setShape(meterName, idx, freezeLine)
  idx = idx + 1

  -- Blank any leftover shapes (prevents stale artifacts when row count shrinks)
  local maxShapes = (2 * days) + 10
  for j = idx, maxShapes do
    setShape(meterName, j, "")
  end


  -- Tooltip: show latest values
  if n > 0 then
    local last = rows[n]
    local vMin = last.min7
    local vAvg = last.avg7
    local date = last.date or ""
    local pal = (minPalette == "SAME") and "Same" or "Cold"
    local tip = string.format(
      "Albert, KS soil (2\") — Freeze line: 32°F\n%s\navg7F: %s°F   min7F: %s°F\nMin palette: %s",
      date,
      (vAvg and string.format("%.1f", vAvg) or "n/a"),
      (vMin and string.format("%.1f", vMin) or "n/a"),
      pal
    )
    SKIN:Bang("!SetOption", meterName, "ToolTipText", tip)
  else
    SKIN:Bang("!SetOption", meterName, "ToolTipText", "Soil graph: no data parsed (check rolling CSV format: date,min7F,avg7F)")
  end

  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")
end

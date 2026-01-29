-- ============================
-- SoilGraphGen.lua (Rolling CSV -> dual-series Shape bars)
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

function Run()
  local meterName = "MeterSoilGraph"

  local file     = SKIN:GetVariable("SoilHistCsv", "")
  local days     = tonumber(SKIN:GetVariable("SoilGraphDays", "45")) or 45
  local barW     = tonumber(SKIN:GetVariable("SoilGraphBarW", "2")) or 2
  local barGap   = tonumber(SKIN:GetVariable("SoilGraphBarGap", "0")) or 0
  local graphH   = tonumber(SKIN:GetVariable("SoilGraphH", "65")) or 65

  local minF_in  = tonumber(SKIN:GetVariable("SoilGraphMinF", "20")) or 20
  local maxF_in  = tonumber(SKIN:GetVariable("SoilGraphMaxF", "90")) or 90

  -- Y-axis: force <=20°F, >=90°F
  local minF = (minF_in > 20) and 20 or minF_in
  local maxF = (maxF_in < 90) and 90 or maxF_in
  local rangeF = maxF - minF
  if rangeF == 0 then rangeF = 1 end

  -- Height clamp threshold (requested): bars never represent below 25°F
  local heightFloorF = 25

  local pal = (SKIN:GetVariable("SoilGraphMinPalette", "Heat") or "Heat"):upper()
  local MIN_STOPS = MIN_STOPS_HEAT
  if pal == "SAME" then
    MIN_STOPS = AVG_STOPS
  elseif pal == "COLDCLAMP" then
    MIN_STOPS = MIN_STOPS_COLDCLAMP
  end

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
          local d    = fields[1] or ""
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

  -- Styles
  local avgAlpha = 110
  local minAlpha = 200
  local minStroke = " | StrokeWidth 1 | Stroke Color 0,0,0,70"

  -- 2) Avg bars (back)
  for i = 1, n do
    local v = rows[i].avg7
    if v ~= nil then
      local vColor = clamp(v, 25, 90)
      local vHeight = clamp(v, heightFloorF, maxF)

      local frac = (vHeight - minF) / rangeF
      local h = math.floor((frac * graphH) + 0.5)
      if h < 1 then h = 1 end
      if h > graphH then h = graphH end

      local x = (i - 1) * (barW + barGap)
      local y = graphH - h

      local r, g, b = interpStops(AVG_STOPS, vColor)
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
      local vColor = clamp(v, 25, 90)
      local vHeight = clamp(v, heightFloorF, maxF)

      local frac = (vHeight - minF) / rangeF
      local h = math.floor((frac * graphH) + 0.5)
      if h < 1 then h = 1 end
      if h > graphH then h = graphH end

      local x = (i - 1) * (barW + barGap)
      local y = graphH - h

      local r, g, b = interpStops(MIN_STOPS, vColor)
      local color = rgba(r, g, b, minAlpha)

      local bar = string.format(
        "Rectangle %d,%d,%d,%d,0 | Fill Color %s%s",
        x, y, barW, h, color, minStroke
      )
      setShape(meterName, idx, bar)
      idx = idx + 1
    end
  end

  -- 4) Freeze line @ 32°F (red, on top) — positioned on the 20..max scale
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

  -- Blank any leftover shapes
  local maxShapes = (2 * days) + 12
  for j = idx, maxShapes do
    setShape(meterName, j, "")
  end

  -- Tooltip
  if n > 0 then
    local last = rows[n]
    local vMin = last.min7
    local vAvg = last.avg7
    local date = last.date or ""
    local palName = (pal == "SAME") and "Same" or ((pal == "COLDCLAMP") and "ColdClamp" or "Heat")
    local tip = string.format(
      "Albert, KS soil (2\") — Freeze line: 32°F\n%s\navg7F: %s°F   min7F: %s°F\nMin palette: %s\nY scale: %d–%d°F (bar floor: %d°F)",
      date,
      (vAvg and string.format("%.1f", vAvg) or "n/a"),
      (vMin and string.format("%.1f", vMin) or "n/a"),
      palName,
      minF, maxF, heightFloorF
    )
    SKIN:Bang("!SetOption", meterName, "ToolTipText", tip)
  else
    SKIN:Bang("!SetOption", meterName, "ToolTipText", "Soil graph: no data parsed (need rolling CSV: date,min7F,avg7F)")
  end

  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")
end

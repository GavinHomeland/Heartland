-- =========================
-- SoilGraphGen.lua (LIVE SHAPES, NO INCLUDE FILE)
-- Called from Rainmeter with: [!CommandMeasure MeasureSoilGraphGen "Run()"]
-- =========================

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function round(x)
  return math.floor(x + 0.5)
end

-- Gradient stops:
-- <=32°F: icy blue
-- 40°F: pale blue
-- 50°F: green
-- 60°F: yellow
-- >=70°F: orange/pink
local function colorForTemp(t)
  local r, g, b

  if t <= 32 then
    r, g, b = 120, 200, 255

  elseif t < 40 then
    local u = (t - 32) / 8
    r = lerp(120, 200, u)
    g = lerp(200, 235, u)
    b = 255

  elseif t < 50 then
    local u = (t - 40) / 10
    r = lerp(200, 80,  u)
    g = lerp(235, 255, u)
    b = lerp(255, 80,  u)

  elseif t < 60 then
    local u = (t - 50) / 10
    r = lerp(80,  255, u)
    g = lerp(255, 235, u)
    b = lerp(80,  0,   u)

  elseif t < 70 then
    local u = (t - 60) / 10
    r = 255
    g = lerp(235, 120, u)
    b = lerp(0,   80,  u)

  else
    r, g, b = 255, 120, 80
  end

  return string.format("%d,%d,%d,255", round(r), round(g), round(b))
end

local function readTemps(csvPath)
  local temps = {}
  local f = io.open(csvPath, "r")
  if not f then return temps end

  for line in f:lines() do
    line = trim(line)
    if line ~= "" then
      -- Accept "date,value" OR just "value"
      local _, b = line:match("^([^,]+),([^,]+)$")
      local tempStr = b or line
      local t = tonumber(tempStr)
      if t then temps[#temps + 1] = t end
    end
  end

  f:close()
  return temps
end

local lastShapeCount = 0

local function setShape(meterName, idx, shapeStr)
  local opt = (idx == 1) and "Shape" or ("Shape" .. tostring(idx))
  SKIN:Bang("!SetOption", meterName, opt, shapeStr)
end

local function clearShape(meterName, idx)
  local opt = (idx == 1) and "Shape" or ("Shape" .. tostring(idx))
  SKIN:Bang("!SetOption", meterName, opt, "")
end

-- ==========================================
-- SoilGraphGen.lua — Replace Run() (LOGGING + 32°F LINE)
-- ==========================================
function Run()
  local meterName = "MeterSoilGraph"

  -- Defensive init (in case globals got nuked / renamed)
  if type(lastShapeCount) ~= "number" then lastShapeCount = 0 end

  local csvPath = SKIN:ReplaceVariables("#SoilHistCsv#")

  local days   = tonumber(SKIN:ReplaceVariables("#SoilGraphDays#")) or 45
  local barW   = tonumber(SKIN:ReplaceVariables("#SoilGraphBarW#")) or 2
  local gap    = tonumber(SKIN:ReplaceVariables("#SoilGraphBarGap#")) or 0
  local minF   = tonumber(SKIN:ReplaceVariables("#SoilGraphMinF#")) or 20
  local maxF   = tonumber(SKIN:ReplaceVariables("#SoilGraphMaxF#")) or 65
  local graphH = tonumber(SKIN:ReplaceVariables("#SoilGraphH#")) or 56

  local width = (days * barW) + ((days - 1) * gap)

  -- LOG: basic config
  -- SKIN:Bang('!Log', ('SoilGraph Run(): csv="%s" days=%d min=%g max=%g H=%d W=%d')
  --  :format(csvPath, days, minF, maxF, graphH, width), 'Notice')

 local temps = readTemps(csvPath)
 -- SKIN:Bang('!Log', ('SoilGraph readTemps(): count=%d'):format(#temps), 'Notice')

  local start = math.max(1, #temps - days + 1)

  -- Start building shapes
  local shapeIdx = 1

  -- Frame = Shape1
  setShape(meterName, shapeIdx,
    string.format(
      "Rectangle 0,0,%d,%d,4 | StrokeWidth 1 | Stroke Color 255,255,255,150 | Fill Color 0,0,0,0",
      width, graphH
    )
  )

  -- If temps are empty, stop here (you'll see it in the log)
  if #temps == 0 then
    SKIN:Bang('!Log', 'SoilGraph: NO TEMPS PARSED -> only frame drawn', 'Error')
    SKIN:Bang("!UpdateMeter", meterName)
    SKIN:Bang("!Redraw")
    return
  end

  -- Bars (Shape2..)
  for i = 0, (days - 1) do
    local t = temps[start + i] or minF

    local tt = clamp(t, minF, maxF)
    local frac = (tt - minF) / (maxF - minF)
    local h = round(frac * graphH)

    local x = i * (barW + gap)
    local y = graphH - h
    local col = colorForTemp(t)

    shapeIdx = shapeIdx + 1
    setShape(meterName, shapeIdx,
      string.format(
        "Rectangle %d,%d,%d,%d,0 | StrokeWidth 0 | Fill Color %s",
        x, y, barW, h, col
      )
    )
  end

  -- 32°F reference line (draw LAST so it stays visible)
  local refF = 32
  if refF >= minF and refF <= maxF then
    local fracRef = (refF - minF) / (maxF - minF)
    local yRef = graphH - round(fracRef * graphH)

    shapeIdx = shapeIdx + 1
    setShape(meterName, shapeIdx,
      string.format(
        "Rectangle 0,%d,%d,1,0 | StrokeWidth 0 | Fill Color 255,0,0,170",
        yRef, width
      )
    )
  end

  -- Clear leftovers
  for i = (shapeIdx + 1), lastShapeCount do
    clearShape(meterName, i)
  end
  lastShapeCount = shapeIdx

  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")

  SKIN:Bang('!Log', ('SoilGraph: drew shapes 1..%d (cleared to %d)'):format(shapeIdx, lastShapeCount), 'Notice')
end

-- ============================
-- SoilGraphGen.lua (CSV -> Shape bars)
-- Supports rolling CSV: date,min7F,avg7F
-- Uses variables:
--   SoilHistCsv, SoilGraphDays, SoilGraphCol, SoilGraphBarW, SoilGraphBarGap,
--   SoilGraphH, SoilGraphMinF, SoilGraphMaxF
-- Writes shapes into: [MeterSoilGraph]
-- ============================

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitCSV(line)
  local t = {}
  -- Simple CSV split (no quoted commas needed for our files)
  local field = ""
  for chunk in (line .. ","):gmatch("(.-),") do
    t[#t + 1] = trim(chunk)
  end
  return t
end

local function isHeader(fields)
  if #fields < 2 then return true end
  local f1 = (fields[1] or ""):upper()
  if f1 == "DATE" or f1 == "TIMESTAMP" then return true end
  -- If the value column isn't numeric, treat as header/junk
  return false
end

function Run()
  local meterName = "MeterSoilGraph"

  local file     = SKIN:GetVariable("SoilHistCsv", "")
  local days     = tonumber(SKIN:GetVariable("SoilGraphDays", "45")) or 45
  local col      = tonumber(SKIN:GetVariable("SoilGraphCol", "2")) or 2

  local barW     = tonumber(SKIN:GetVariable("SoilGraphBarW", "2")) or 2
  local barGap   = tonumber(SKIN:GetVariable("SoilGraphBarGap", "0")) or 0
  local graphH   = tonumber(SKIN:GetVariable("SoilGraphH", "65")) or 65

  local minF     = tonumber(SKIN:GetVariable("SoilGraphMinF", "25")) or 25
  local maxF     = tonumber(SKIN:GetVariable("SoilGraphMaxF", "65")) or 65
  local rangeF   = maxF - minF
  if rangeF == 0 then rangeF = 1 end

  -- Read values
  local temps = {}

  local fh = io.open(file, "r")
  if fh then
    for line in fh:lines() do
      -- strip UTF-8 BOM if present
      line = line:gsub("^\239\187\191", "")
      line = trim(line)

      if line ~= "" then
        local fields = splitCSV(line)

        -- Skip header-like lines
        if not isHeader(fields) then
          local v = tonumber(fields[col] or "")
          if v then temps[#temps + 1] = v end
        end
      end
    end
    fh:close()
  end

  -- Keep only last N points
  if #temps > days then
    local start = #temps - days + 1
    local sliced = {}
    for i = start, #temps do sliced[#sliced + 1] = temps[i] end
    temps = sliced
  end

  -- Clear / rebuild shapes
  -- Shape meter uses: Shape, Shape2, Shape3...
  -- We'll always build a frame + N bars, and blank out leftovers up to 'days'.
  local graphW = (#temps > 0) and ((#temps * barW) + ((#temps - 1) * barGap)) or 1

  local frame = string.format(
    "Rectangle 0,0,%d,%d,4 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color 255,255,255,90",
    graphW, graphH
  )
  SKIN:Bang("!SetOption", meterName, "Shape", frame)

  local barColor = "0,220,0,150"

  for i = 1, #temps do
    local v = temps[i]
    if v < minF then v = minF end
    if v > maxF then v = maxF end

    local frac = (v - minF) / rangeF
    local h = math.floor((frac * graphH) + 0.5)
    if h < 1 then h = 1 end
    if h > graphH then h = graphH end

    local x = (i - 1) * (barW + barGap)
    local y = graphH - h

    local bar = string.format(
      "Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
      x, y, barW, h, barColor
    )
    SKIN:Bang("!SetOption", meterName, "Shape" .. (i + 1), bar)
  end

  -- Blank unused shapes up to the configured max days (prevents stale bars)
  for i = (#temps + 2), (days + 2) do
    SKIN:Bang("!SetOption", meterName, "Shape" .. i, "")
  end

  -- Tooltip: show latest value + which col we graphed
  if #temps > 0 then
    local latest = temps[#temps]
    SKIN:Bang("!SetOption", meterName, "ToolTipText", string.format('Soil graph (col %d). Latest: %.1f°F', col, latest))
  else
    SKIN:Bang("!SetOption", meterName, "ToolTipText", "Soil graph: no data parsed (check rolling CSV + SoilGraphCol)")
  end

  SKIN:Bang("!UpdateMeter", meterName)
  SKIN:Bang("!Redraw")
end

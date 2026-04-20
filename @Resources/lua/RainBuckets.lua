-- RainBuckets.lua
-- 3 stacked animated rain buckets, each narrower than the one below.
-- Shape meter layout:
--   Shape 1     : invisible base anchor
--   Shapes 2-4  : fill rectangles (behind structure)
--   Shapes 5-26 : structure lines (chamfers, walls, bottoms, nipples)
--   Shapes 27-28: drip blobs (B0→B1, B1→B2)
--   Shapes 29-36: raindrops (8 slots)
--   Shapes 37-40: overflow side drips (B1 left/right, B2 left/right)
--   Shapes 41-54: overflow side drips (B0 L/R, B1 L/R extra, B2 L/R extra; 3 drops/side)

-- ============================================================
-- CONSTANTS
-- ============================================================
local METER        = "MeterRainBuckets"
local OM_JSON      = ""
local OM_HRRR_JSON = ""
local LOG_PATH     = ""
local MASTER_LOG   = ""

-- Layout (meter coords; meter Y = SoilGraphY = 130)
local W          = 60
local ICON_H     = 47    -- Y=0..47: icon area
local ICON_GAP   = 8     -- Y=47..55: gap
local B0_TOP     = ICON_H + ICON_GAP  -- 55
local BUCKET_H   = 64
local GAP_H      = 24
local NIPPLE_H   = 5
local NIPPLE_GAP = 4     -- total gap at bucket bottom (2px each side of CX)
local B0_BOT     = B0_TOP + BUCKET_H   -- 119
local B1_TOP     = B0_BOT + GAP_H      -- 143
local B1_BOT     = B1_TOP + BUCKET_H   -- 207
local B2_TOP     = B1_BOT + GAP_H      -- 231
local B2_BOT     = B2_TOP + BUCKET_H   -- 295
local NIP0_TIP   = B0_BOT + NIPPLE_H   -- 124
local NIP1_TIP   = B1_BOT + NIPPLE_H   -- 212
local CX         = W / 2               -- 30 (nipple center, same for all buckets)

-- Bucket widths and X offsets (centered; each bucket narrower than the one below)
local B2_W = W            -- 60
local B1_W = W - 4        -- 56
local B0_W = B1_W - 8     -- 48
local B2_X = 0
local B1_X = (W - B1_W) / 2   -- 2
local B0_X = (W - B0_W) / 2   -- 6

-- Fill scales
local RATE_FULL   = 1.0   -- inches/past-hour → full bucket 0
local DAILY_FULL  = 2.5   -- inches → full bucket 1
local WEEKLY_FULL = 4.0   -- inches → full bucket 2

-- Colors
local STROKE_C    = "160,210,255,200"
local FILL_C      = "80,160,255,180"
local DROP_BASE_A = 180   -- raindrop base alpha (±50 random)

-- Drain physics per 100ms tick
local DRAIN0_PER_TICK = 1.0 / 18000         -- full→empty in 30 min
local DECAY1_K        = 5.33e-6             -- bucket 1: reaches ~1% after 24h
local DECAY2_K        = 2.3e-7              -- bucket 2: half-life ~3.5 days

-- Animation state
local disp0, disp1, disp2 = 0.0, 0.0, 0.0
local isRaining      = true
local testRate       = 0.15
local isThunderstorm = false
local thunderCode    = 0    -- WMO: 95=standard, 96=hail, 99=severe
local lightningOn      = false
local lightningTick    = 0
local lightningCooldown = math.random(50, 200)

-- Raindrop state (8 slots)
local NUM_DROPS = 8
local drops = {}
for i = 1, NUM_DROPS do
  drops[i] = { x=0, y=-1, speed=0, alpha=180, active=false, spawnIn=0,
               splashing=false, splashTick=0, splashY=0 }
end

-- Drip blob state (2 slots: B0→B1 and B1→B2)
-- dripInterval: ticks between drips (B0→B1 is twice as frequent)
local drip = {
  { y=NIP0_TIP, active=false, cooldown=0, srcDisp=function() return disp0 end,
    startY=NIP0_TIP, shapeIdx=27, dripInterval=12,
    splashing=false, splashTick=0, splashY=0 },
  { y=NIP1_TIP, active=false, cooldown=0, srcDisp=function() return disp1 end,
    startY=NIP1_TIP, shapeIdx=28, dripInterval=25,
    splashing=false, splashTick=0, splashY=0 },
}

-- Overflow side drips: 3 staggered drops per side (6 sides = 18 shape slots)
-- Side index mapping: 1-2=B0, 3-4=B1, 5-6=B2
-- Shapes per side: B0-L={41,43,44}, B0-R={42,45,46},
--                  B1-L={37,47,48}, B1-R={38,49,50},
--                  B2-L={39,51,52}, B2-R={40,53,54}
local OVERFLOW_DROP_LEN = 20  -- px below rim for B2 (no target bucket)
local N_OVERFLOW = 3          -- drops per side
local overflowSide = {
  { wallX=B0_X-4,      topY=B0_TOP, shapes={41,43,44} },  -- B0 left
  { wallX=B0_X+B0_W+1, topY=B0_TOP, shapes={42,45,46} },  -- B0 right
  { wallX=B1_X-1,      topY=B1_TOP, shapes={37,47,48} },  -- B1 left
  { wallX=B1_X+B1_W,   topY=B1_TOP, shapes={38,49,50} },  -- B1 right
  { wallX=0,           topY=B2_TOP, shapes={39,51,52} },   -- B2 left
  { wallX=B2_W-2,      topY=B2_TOP, shapes={40,53,54} },   -- B2 right
}
-- Drop slots initialized in Initialize() after math.randomseed

-- ============================================================
-- HELPERS
-- ============================================================
local function setShape(idx, def)
  if idx == 1 then
    SKIN:Bang("!SetOption", METER, "Shape", def)
  else
    SKIN:Bang("!SetOption", METER, "Shape" .. idx, def)
  end
end

local function appendLog(path, msg)
  if path and path ~= "" then
    local f = io.open(path, "a")
    if f then f:write(msg .. "\n"); f:close() end
  end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function mathrand(lo, hi)
  return lo + math.random() * (hi - lo)
end

-- ============================================================
-- STRUCTURE DRAWING
-- ============================================================
local function drawStructure()
  local sc = STROKE_C
  local si  = 5  -- start shape index for structure

  local function line(x1, y1, x2, y2)
    setShape(si, string.format(
      "Line %d,%d,%d,%d | StrokeWidth 2 | Stroke Color %s", x1, y1, x2, y2, sc))
    si = si + 1
  end

  -- bx = left edge X, bw = bucket width; chamfer flares 3px outward
  local function drawBucketWithNipple(y1, y2, bx, bw)
    local ng = NIPPLE_GAP / 2  -- 2
    line(bx-3, y1, bx,       y1+2)          -- left chamfer (outward flare)
    line(bx+bw+2, y1, bx+bw-1, y1+2)        -- right chamfer (outward flare)
    line(bx,     y1+2, bx,     y2)           -- left wall
    line(bx+bw-1, y1+2, bx+bw-1, y2)        -- right wall
    line(bx,     y2, CX-ng, y2)              -- bottom left
    line(CX+ng,  y2, bx+bw-1, y2)           -- bottom right
    line(CX-ng,  y2, CX, y2+NIPPLE_H)       -- nipple left
    line(CX+ng,  y2, CX, y2+NIPPLE_H)       -- nipple right
  end

  local function drawBucketNoNipple(y1, y2, bx, bw)
    line(bx-3, y1, bx,       y1+2)           -- left chamfer (outward flare)
    line(bx+bw+2, y1, bx+bw-1, y1+2)         -- right chamfer (outward flare)
    line(bx,     y1+2, bx,     y2)            -- left wall
    line(bx+bw-1, y1+2, bx+bw-1, y2)         -- right wall
    line(bx,     y2, bx+bw-1, y2)             -- full bottom (no nipple)
  end

  drawBucketWithNipple(B0_TOP, B0_BOT, B0_X, B0_W)  -- 8 shapes → si 5..12
  drawBucketWithNipple(B1_TOP, B1_BOT, B1_X, B1_W)  -- 8 shapes → si 13..20
  drawBucketNoNipple(B2_TOP, B2_BOT, B2_X, B2_W)    -- 5 shapes → si 21..25

  -- Clear unused structure slots
  for i = si, 26 do
    setShape(i, "Line 0,0,0,0 | StrokeWidth 0")
  end
end

-- ============================================================
-- FILL DRAWING
-- ============================================================
-- Fill is clamped at 100% (no overflow fill extension above rim).
-- Overflow is indicated by side drip animation only.
local function drawFill(shapeIdx, y1, y2, disp, bx, bw)
  local d = clamp(disp, 0, 1.0)
  if d < 0.005 then
    setShape(shapeIdx, "Rectangle 0,0,1,1 | Fill Color 0,0,0,0 | StrokeWidth 0")
    return
  end
  local bucketH = y2 - y1
  local fillH   = math.max(2, math.floor(d * bucketH + 0.5))
  local fillTop = y2 - fillH
  setShape(shapeIdx, string.format(
    "Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
    bx, fillTop, bw, fillH, FILL_C))
end

local function updateFills()
  drawFill(2, B0_TOP, B0_BOT, disp0, B0_X, B0_W)
  drawFill(3, B1_TOP, B1_BOT, disp1, B1_X, B1_W)
  drawFill(4, B2_TOP, B2_BOT, disp2, B2_X, B2_W)
end

-- ============================================================
-- RAINDROP ANIMATION
-- ============================================================
local function intensityToParams(rate)
  if rate >= 1.0 then return 8, 8
  elseif rate >= 0.31 then return 6, 6
  elseif rate >= 0.11 then return 4, 4
  elseif rate >= 0.01 then return 2, 4
  else return 1, 2
  end
end

local DROP_START_Y = 12  -- within icon area (icon raised 10px, covers ~y=-10..37)

local function spawnDrop(slot, speed, fillStopY, stagger)
  local startY = DROP_START_Y
  if stagger then
    local travel = math.max(0, fillStopY - DROP_START_Y - 5)
    startY = DROP_START_Y + math.floor(mathrand(0, travel))
  end
  -- Drops confined to B0 width
  drops[slot].x         = math.floor(mathrand(B0_X + 2, B0_X + B0_W - 3))
  drops[slot].y         = startY
  drops[slot].speed     = speed
  drops[slot].alpha     = math.floor(clamp(DROP_BASE_A + mathrand(-50, 50), 50, 255))
  drops[slot].stopY     = fillStopY
  drops[slot].active    = true
  drops[slot].splashing = false
  drops[slot].spawnIn   = 0
end

local function advanceDrops()
  local numActive, speed = intensityToParams(testRate)
  local fillStopY = B0_BOT - math.floor(clamp(disp0, 0, 1.0) * BUCKET_H)
  fillStopY = clamp(fillStopY, B0_TOP, B0_BOT)

  for i = 1, NUM_DROPS do
    local d = drops[i]
    if d.active then
      d.y = d.y + d.speed
      if d.y >= d.stopY then
        d.active     = false
        d.splashing  = true
        d.splashTick = 2
        d.splashY    = d.stopY
        d.spawnIn    = math.random(0, 2)
      end
    elseif d.splashing then
      d.splashTick = d.splashTick - 1
      if d.splashTick <= 0 then
        d.splashing = false
        if i <= numActive then spawnDrop(i, speed, fillStopY) end
      end
    else
      if i <= numActive then
        if d.spawnIn > 0 then
          d.spawnIn = d.spawnIn - 1
        else
          spawnDrop(i, speed, fillStopY)
        end
      end
    end
  end
end

local function updateDropShapes()
  for i = 1, NUM_DROPS do
    local d = drops[i]
    local si = 28 + i  -- shapes 29..36
    if d.active and isRaining then
      setShape(si, string.format(
        "Rectangle %d,%d,1,4,0 | Fill Color 160,210,255,%d | StrokeWidth 0",
        d.x, d.y, d.alpha))
    elseif d.splashing and isRaining then
      local splashAlpha = math.floor(d.splashTick * 55)
      local splashW = (5 - d.splashTick) * 2 + 2
      local splashX = clamp(d.x - splashW / 2, B0_X + 1, B0_X + B0_W - splashW - 1)
      setShape(si, string.format(
        "Rectangle %d,%d,%d,1,0 | Fill Color 200,230,255,%d | StrokeWidth 0",
        splashX, d.splashY, splashW, splashAlpha))
    else
      setShape(si, "Rectangle 0,0,1,1 | Fill Color 0,0,0,0 | StrokeWidth 0")
    end
  end
end

-- ============================================================
-- DRIP BLOB ANIMATION (B0→B1, B1→B2)
-- ============================================================
local function advanceDrips()
  for _, bl in ipairs(drip) do
    local src = bl.srcDisp()

    -- Handle splash countdown independently of src
    if bl.splashing then
      bl.splashTick = bl.splashTick - 1
      if bl.splashTick <= 0 then
        bl.splashing = false
        bl.cooldown  = bl.dripInterval
      end
    elseif src > 0 then
      -- Dynamic endY: stop at current water surface of the target bucket
      local waterH, dynEndY
      if bl.startY == NIP0_TIP then   -- B0 → B1
        waterH  = math.min(disp1, 1.0) * BUCKET_H
        dynEndY = clamp(B1_BOT - math.floor(waterH), B1_TOP, B1_BOT)
      else                            -- B1 → B2
        waterH  = math.min(disp2, 1.0) * BUCKET_H
        dynEndY = clamp(B2_BOT - math.floor(waterH), B2_TOP, B2_BOT)
      end

      local blobSpeed = (thunderCode == 96 or thunderCode == 99) and 6 or 4
      if bl.active then
        bl.y = bl.y + blobSpeed
        if bl.y >= dynEndY then
          bl.active    = false
          bl.splashing = true
          bl.splashTick = 2
          bl.splashY   = dynEndY
        end
      else
        if bl.cooldown > 0 then
          bl.cooldown = bl.cooldown - 1
        else
          if dynEndY > bl.startY + 2 then
            bl.y      = bl.startY
            bl.active = true
          end
        end
      end
    else
      bl.active    = false
      bl.splashing = false
      bl.cooldown  = 0
    end
  end
end

local function updateDripShapes()
  local isHail = (thunderCode == 96 or thunderCode == 99)
  local blobW  = isHail and 4 or 2
  local blobH  = isHail and 5 or 3
  local blobC  = isHail and "255,255,255,220" or STROKE_C
  for _, bl in ipairs(drip) do
    if bl.active then
      setShape(bl.shapeIdx, string.format(
        "Rectangle %d,%d,%d,%d,0 | Fill Color %s | StrokeWidth 0",
        CX - math.floor(blobW / 2), bl.y, blobW, blobH, blobC))
    elseif bl.splashing then
      -- Splash at water surface: expanding horizontal bar, fading out
      local alpha  = bl.splashTick * 65     -- 195 → 130 → 65
      local sw     = (4 - bl.splashTick) * 2 + 4  -- 4 → 6 → 8px
      local sx     = clamp(CX - math.floor(sw / 2), 1, W - sw - 1)
      setShape(bl.shapeIdx, string.format(
        "Rectangle %d,%d,%d,1,0 | Fill Color 200,230,255,%d | StrokeWidth 0",
        sx, bl.splashY, sw, alpha))
    else
      setShape(bl.shapeIdx, "Rectangle 0,0,1,1 | Fill Color 0,0,0,0 | StrokeWidth 0")
    end
  end
end

-- ============================================================
-- OVERFLOW SIDE DRIPS
-- ============================================================
local function advanceOverflowDrips()
  for i, side in ipairs(overflowSide) do
    local isOverflow, dynEndY
    if i <= 2 then
      isOverflow = (disp0 > 1.0)
      local waterH = math.min(disp1, 1.0) * BUCKET_H
      dynEndY = clamp(B1_BOT - math.floor(waterH), B1_TOP, B1_BOT)
    elseif i <= 4 then
      isOverflow = (disp1 > 1.0)
      local waterH = math.min(disp2, 1.0) * BUCKET_H
      dynEndY = clamp(B2_BOT - math.floor(waterH), B2_TOP, B2_BOT)
    else
      isOverflow = (disp2 > 1.0)
      dynEndY = side.topY + OVERFLOW_DROP_LEN
    end
    for _, drop in ipairs(side.drops) do
      if isOverflow then
        if drop.active then
          drop.y = drop.y + 4
          if drop.y >= dynEndY then
            drop.active   = false
            drop.cooldown = 0
          end
        else
          if drop.cooldown > 0 then
            drop.cooldown = drop.cooldown - 1
          else
            drop.y      = side.topY
            drop.active = true
          end
        end
      else
        drop.active   = false
        drop.cooldown = 0
      end
    end
  end
end

local function updateOverflowDripShapes()
  for _, side in ipairs(overflowSide) do
    for k, drop in ipairs(side.drops) do
      local shapeIdx = side.shapes[k]
      if drop.active then
        setShape(shapeIdx, string.format(
          "Rectangle %d,%d,2,3,0 | Fill Color %s | StrokeWidth 0",
          side.wallX, drop.y, STROKE_C))
      else
        setShape(shapeIdx, "Rectangle 0,0,1,1 | Fill Color 0,0,0,0 | StrokeWidth 0")
      end
    end
  end
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function Initialize()
  OM_JSON      = SKIN:GetVariable("OM_JSON", "")
  OM_HRRR_JSON = SKIN:GetVariable("OM_HRRR_JSON", "")
  LOG_PATH     = SKIN:GetVariable("RainBucketsLog")
  MASTER_LOG   = SKIN:GetVariable("HeartlandLog")
  math.randomseed(os.time())

  -- Initialize overflow drop slots with random start delays
  for _, side in ipairs(overflowSide) do
    side.drops = {}
    for k = 1, N_OVERFLOW do
      side.drops[k] = { y=side.topY, active=false, cooldown=math.random(0, 25) }
    end
  end

  -- Start empty; Run() will populate from om.json after OM fetch
  disp0 = 0.0
  disp1 = 0.0
  disp2 = 0.0
  isRaining = false

  SKIN:Bang("!HideMeter", "MeterRainIcon")
  SKIN:Bang("!HideMeter", "MeterLightningBolt")

  drawStructure()
  updateFills()
  updateDropShapes()
  updateDripShapes()
  updateOverflowDripShapes()
  SKIN:Bang("!UpdateMeter", METER)
  SKIN:Bang("!Redraw")
  local msg = os.date("%Y-%m-%d %H:%M:%S") .. " | RainBuckets | Initialize"
  appendLog(LOG_PATH, msg)
  appendLog(MASTER_LOG, msg)
end

-- ============================================================
-- UPDATE  (called every 100ms)
-- ============================================================
function Update()
  -- Skip entirely only when there is truly nothing to animate or drain
  local anyWater    = (disp0 > 0) or (disp1 > 0) or (disp2 > 0)
  local anyOverflow = (disp0 > 1.0) or (disp1 > 1.0) or (disp2 > 1.0)
  if not isRaining and not isThunderstorm and not anyWater and not anyOverflow then
    return ""
  end

  -- Lightning flash
  if isThunderstorm then
    if lightningOn then
      lightningTick = lightningTick - 1
      if lightningTick <= 0 then
        lightningOn       = false
        lightningCooldown = math.random(50, 200)
        SKIN:Bang("!HideMeter", "MeterLightningBolt")
        SKIN:Bang("!UpdateMeter", "MeterLightningBolt")
      end
    else
      lightningCooldown = lightningCooldown - 1
      if lightningCooldown <= 0 then
        lightningOn   = true
        lightningTick = math.random(1, 3)
        SKIN:Bang("!ShowMeter", "MeterLightningBolt")
        SKIN:Bang("!UpdateMeter", "MeterLightningBolt")
      end
    end
  elseif lightningOn then
    lightningOn = false
    SKIN:Bang("!HideMeter", "MeterLightningBolt")
    SKIN:Bang("!UpdateMeter", "MeterLightningBolt")
  end

  -- Drain physics
  if disp0 > 0 then
    disp0 = math.max(0, disp0 - DRAIN0_PER_TICK)
  end
  if disp1 > 0 then
    disp1 = math.max(0, disp1 * (1 - DECAY1_K))
    if disp1 < 0.001 then disp1 = 0 end
  end
  if disp2 > 0 then
    disp2 = disp2 * (1 - DECAY2_K)
    if disp2 < 0.001 then disp2 = 0 end
  end

  -- Animation
  if isRaining then advanceDrops() end
  advanceDrips()
  advanceOverflowDrips()

  -- Update shapes
  updateFills()
  updateDropShapes()
  updateDripShapes()
  updateOverflowDripShapes()

  SKIN:Bang("!UpdateMeter", METER)
  SKIN:Bang("!Redraw")
end

-- ============================================================
-- RUN  (called by OM FinishAction when new data arrives)
-- ============================================================
function Run()
  local startMsg = os.date("%Y-%m-%d %H:%M:%S") .. " | RainBuckets | Run Start"
  appendLog(LOG_PATH, startMsg)
  appendLog(MASTER_LOG, startMsg)

  -- Read forecast data from om.json (ECMWF: daily sums, weather codes)
  local jsonPath = OM_JSON
  local f = io.open(jsonPath, "r")
  if not f then
    local errMsg = os.date("%Y-%m-%d %H:%M:%S") .. " | RainBuckets | ERR cannot open " .. jsonPath
    appendLog(LOG_PATH, errMsg)
    appendLog(MASTER_LOG, errMsg)
    return
  end
  local json = f:read("*a")
  f:close()

  -- B0: current.precipitation = past-hour accumulation (inches)
  local curPrecip = tonumber(json:match('"current"%s*:%s*%{[^}]*"precipitation"%s*:%s*([%d%.]+)')) or 0
  disp0 = curPrecip / RATE_FULL

  -- isRaining: true when past-hour precipitation is non-trivial
  local wasRaining = isRaining
  isRaining = (curPrecip > 0.005)
  testRate  = curPrecip

  -- Rain just stopped: reset all drop slots so nothing lingers mid-air
  if wasRaining and not isRaining then
    for i = 1, NUM_DROPS do
      drops[i].active   = false
      drops[i].splashing = false
    end
    updateDropShapes()
  end

  -- Show/hide rain icon
  if isRaining then
    SKIN:Bang("!ShowMeter", "MeterRainIcon")
    SKIN:Bang("!UpdateMeter", "MeterRainIcon")
  else
    SKIN:Bang("!HideMeter", "MeterRainIcon")
    SKIN:Bang("!UpdateMeter", "MeterRainIcon")
  end

  -- Parse weather_code for thunderstorm / icon selection
  local wmoCode = tonumber(json:match('"current"%s*:%s*%{[^}]*"weather_code"%s*:%s*(%d+)')) or 0
  isThunderstorm = (wmoCode == 95 or wmoCode == 96 or wmoCode == 99)
  thunderCode = wmoCode

  local boltIcon = (wmoCode == 99) and "#@#WeatherIcons\\code-red.png"
                                    or  "#@#WeatherIcons\\lightning-bolt.png"
  SKIN:Bang("!SetOption", "MeterLightningBolt", "ImageName", boltIcon)
  SKIN:Bang("!UpdateMeter", "MeterLightningBolt")
  if not isThunderstorm then
    lightningOn = false
    SKIN:Bang("!HideMeter", "MeterLightningBolt")
    SKIN:Bang("!UpdateMeter", "MeterLightningBolt")
  end

  -- Parse daily time + precipitation arrays (anchor to "daily" block to avoid hourly "time" match)
  local dailyBlock   = json:match('"daily"%s*:%s*(%b{})')
  local dailyTimeStr = dailyBlock and dailyBlock:match('"time"%s*:%s*%[([^%]]+)%]')
  local dailySumStr  = json:match('"precipitation_sum"%s*:%s*%[([^%]]+)%]')
  local dailyTimes, dailySums = {}, {}
  if dailyTimeStr then
    for t in dailyTimeStr:gmatch('"([^"]+)"') do dailyTimes[#dailyTimes+1] = t end
  end
  if dailySumStr then
    for v in dailySumStr:gmatch("([%d%.]+)") do dailySums[#dailySums+1] = tonumber(v) or 0 end
  end

  -- Find today's index in the time array
  local todayStr  = os.date("%Y-%m-%d")
  local todayIdx  = #dailyTimes  -- fallback: last entry
  for i, t in ipairs(dailyTimes) do
    if t == todayStr then todayIdx = i; break end
  end

  -- B1: today's accumulated precipitation
  disp1 = (dailySums[todayIdx] or 0) / DAILY_FULL

  -- B2: past 7 days (today and 6 prior)
  local weekSum = 0
  for i = math.max(1, todayIdx - 6), todayIdx do
    weekSum = weekSum + (dailySums[i] or 0)
  end
  disp2 = weekSum / WEEKLY_FULL

  drawStructure()
  updateFills()
  SKIN:Bang("!UpdateMeter", METER)
  SKIN:Bang("!Redraw")

  local endMsg = os.date("%Y-%m-%d %H:%M:%S") ..
    string.format(" | RainBuckets | Run Complete precip=%.3f disp0=%.2f disp1=%.2f disp2=%.2f",
      curPrecip, disp0, disp1, disp2)
  appendLog(LOG_PATH, endMsg)
  appendLog(MASTER_LOG, endMsg)
end

-- ============================================================
-- DASHBOARD CONTROLS (callable via !CommandMeasure)
-- ============================================================
function ToggleRain()
  isRaining = not isRaining
  SKIN:Bang("!SetVariable", "TestRainIsRaining", isRaining and "1" or "0")
end

local RATE_CYCLE = { 0.005, 0.05, 0.15, 0.50, 1.20 }
function CycleRate()
  local cur  = testRate
  local next = RATE_CYCLE[1]
  for i, r in ipairs(RATE_CYCLE) do
    if math.abs(cur - r) < 0.001 then
      next = RATE_CYCLE[(i % #RATE_CYCLE) + 1]
      break
    end
  end
  testRate = next
  SKIN:Bang("!SetVariable", "TestRainRate", string.format("%.3f", next))
end

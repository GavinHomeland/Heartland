-- ============================================================
-- AlertPulse.lua  —  Visual pulse + alert sound + ack button
-- Called via [MeasureAlertPulse] in alerts_row.inc (UpdateDivider=1, 100ms)
--
-- Reads nws_alerts.json directly — no WebParser measure dependency.
--
-- Pulse rules:
--   warn=true  icons: all pulse together when any warning is active+unacked.
--   warn=false icons: full alpha (255), no pulse.
--
-- Layout: icons left-justify per row; Lua sets Hidden/X/Y via !SetOption.
--   Layout only re-evaluated when flag fingerprint changes.
--
-- ACK button: appears when any alert is active + unacknowledged.
--   Click → Acknowledge() silences pulse + sound, hides button.
--   Re-arms when alerts clear and a new batch appears.
-- ============================================================

-- Single source of truth: all 18 alerts, ordered for left-justify layout
local ALL_PAIRS = {
    -- Row 1 (Y = AlertRowY)
    { key="TornadoWarning",            t="MeterAlertTornadoWarning",            row=1, warn=true  },
    { key="TornadoWatch",              t="MeterAlertTornadoWatch",              row=1, warn=false },
    { key="SevereThunderstormWarning", t="MeterAlertSevereThunderstormWarning", row=1, warn=true  },
    { key="SevereThunderstormWatch",   t="MeterAlertSevereThunderstormWatch",   row=1, warn=false },
    { key="FlashFloodWarning",         t="MeterAlertFlashFloodWarning",         row=1, warn=true  },
    { key="FlashFloodWatch",           t="MeterAlertFlashFloodWatch",           row=1, warn=false },
    { key="FireWeatherWatch",          t="MeterAlertFireWeatherWatch",          row=1, warn=false },
    { key="RedFlagWarning",            t="MeterAlertRedFlagWarning",            row=1, warn=true  },
    { key="WinterStormWarning",        t="MeterAlertWinterStormWarning",        row=1, warn=true  },
    -- Row 2 (Y = AlertRowY + 64)
    { key="WinterStormWatch",          t="MeterAlertWinterStormWatch",          row=2, warn=false },
    { key="IceStorm",                  t="MeterAlertIceStorm",                  row=2, warn=true  },
    { key="HighWind",                  t="MeterAlertHighWind",                  row=2, warn=true  },
    { key="WindAdvisory",              t="MeterAlertWindAdvisory",              row=2, warn=false },
    { key="ExcessiveHeat",             t="MeterAlertExcessiveHeat",             row=2, warn=true  },
    { key="HeatAdvisory",             t="MeterAlertHeatAdvisory",              row=2, warn=false },
    { key="FreezeWarning",             t="MeterAlertFreezeWarning",             row=2, warn=true  },
    { key="DenseFog",                  t="MeterAlertDenseFog",                  row=2, warn=false },
    { key="DustStorm",                 t="MeterAlertDustStorm",                 row=2, warn=true  },
    -- Row 3 (Y = AlertRowY + 128)
    { key="FloodWarning",              t="MeterAlertFloodWarning",              row=3, warn=true  },
    { key="FloodWatch",                t="MeterAlertFloodWatch",                row=3, warn=false },
    { key="WinterWeatherAdvisory",     t="MeterAlertWinterWeatherAdvisory",     row=3, warn=false },
    { key="WindChillWarning",          t="MeterAlertWindChillWarning",          row=3, warn=true  },
    { key="WindChillAdvisory",         t="MeterAlertWindChillAdvisory",         row=3, warn=false },
    { key="FreezeWatch",               t="MeterAlertFreezeWatch",               row=3, warn=false },
    { key="HardFreezeWarning",         t="MeterAlertHardFreezeWarning",         row=3, warn=true  },
    { key="AirQualityAlert",           t="MeterAlertAirQualityAlert",           row=3, warn=false },
    { key="DenseSmokeAdvisory",        t="MeterAlertDenseSmokeAdvisory",        row=3, warn=false },
}

local ACK_METER    = "MeterAlertAck"
local ICON_STEP    = 75   -- px per icon slot (54px icon + 21px gap, 8 icons fills W-Pad exactly)
local ICON_ORIGIN  = 24   -- left edge of first icon
local ICONS_PER_ROW = 8  -- icons before wrapping to next row
local ROW2_OFFSET  = 64   -- row 2 Y offset from AlertRowY
local ROW3_OFFSET  = 128  -- row 3 Y offset from AlertRowY
local BASE_H       = 441  -- SoilGraphY(130) + B2_BOT(295) + Pad(16); no alerts

-- Module-level state
local tick          = 0
local acknowledged  = false
local lastSoundTick = -300   -- fire immediately on first detection
local prevActive    = false
local currentH      = 0       -- last H sent; 0 = unset
local prevFlagSig   = ""      -- fingerprint of last known flags
local lastAlpha     = -1      -- last alpha sent; skip setAlpha when unchanged
local lastAckHidden = nil     -- last ACK button state; skip bang when unchanged
local cachedFlags   = {}      -- flags from last JSON read
local lastJsonTick  = -100    -- force read on first tick

local SOUND_INTERVAL         = 150  -- normal alarm interval (150 × 200ms = 30 s)
local TORNADO_WARN_INTERVAL  = 5    -- tornado warning interval (5 × 200ms = 1 s)
local TICK_STEP              = math.pi / 10  -- 10 ticks/half-cycle ≈ 2 s full cycle

local function pulseAlpha()
    return math.floor(math.abs(math.sin(tick * TICK_STEP)) * 195 + 60 + 0.5)
end

-- Read nws_alerts.json directly; returns table of key→bool
local function readFlags()
    local path = SKIN:GetVariable("NWS_JSON") or ""
    if path == "" then return {} end
    local f = io.open(path, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    local flags = {}
    for key, val in content:gmatch('"(%w+)":([01])') do
        flags[key] = (val == "1")
    end
    return flags
end

local function flagSig(flags)
    local t = {}
    for _, p in ipairs(ALL_PAIRS) do
        t[#t+1] = flags[p.key] and "1" or "0"
    end
    return table.concat(t)
end

local function setHidden(meter, hidden)
    SKIN:Bang("!SetOption",  meter, "Hidden", hidden and "1" or "0")
    SKIN:Bang("!UpdateMeter", meter)
end

local function setAlpha(meter, alpha)
    SKIN:Bang("!SetOption",  meter, "ImageAlpha", tostring(alpha))
    SKIN:Bang("!UpdateMeter", meter)
end

-- Pack active icons sequentially: row 1 fills first, then row 2, then row 3.
-- Only called when flags actually change.
local function updateLayout(flags)
    local alertRowY = tonumber(SKIN:GetVariable("AlertRowY") or "470")
    local slot = 0
    for _, p in ipairs(ALL_PAIRS) do
        if flags[p.key] then
            local rowIdx = math.floor(slot / ICONS_PER_ROW)  -- 0, 1, 2
            local colIdx = slot % ICONS_PER_ROW
            local x = ICON_ORIGIN + colIdx * ICON_STEP
            local y = alertRowY + rowIdx * ROW2_OFFSET
            SKIN:Bang("!SetOption", p.t, "X",      tostring(x))
            SKIN:Bang("!SetOption", p.t, "Y",      tostring(y))
            SKIN:Bang("!SetOption", p.t, "Hidden", "0")
            SKIN:Bang("!UpdateMeter", p.t)
            slot = slot + 1
        else
            SKIN:Bang("!SetOption", p.t, "Hidden", "1")
            SKIN:Bang("!UpdateMeter", p.t)
        end
    end
end

-- Called by ACK button: [!CommandMeasure MeasureAlertPulse "Acknowledge()"]
function Acknowledge()
    acknowledged  = true
    lastSoundTick = tick
    SKIN:Bang("!SetVariable", "AlertAcknowledged", "1")
    setHidden(ACK_METER, true)
    for _, p in ipairs(ALL_PAIRS) do
        if p.warn then setAlpha(p.t, 255) end
    end
    SKIN:Bang("!Redraw")
    SKIN:Bang("!Log", "AlertPulse: acknowledged by user", "Notice")
end

function Update()
    tick = tick + 1

    -- Read JSON at ~1/min (every 300 ticks = 60 s at 200 ms base rate)
    if tick - lastJsonTick >= 300 then
        cachedFlags  = readFlags()
        lastJsonTick = tick
    end
    local flags = cachedFlags

    -- Scan active flags
    local anyWarn, anyAlert = false, false
    local activeCount = 0
    for _, p in ipairs(ALL_PAIRS) do
        if flags[p.key] then
            anyAlert = true
            activeCount = activeCount + 1
            if p.warn then anyWarn = true end
        end
    end
    local row1 = activeCount >= 1
    local row2 = activeCount > ICONS_PER_ROW
    local row3 = activeCount > ICONS_PER_ROW * 2

    -- Fresh activation: clear ack, arm sound
    if anyAlert and not prevActive then
        acknowledged  = false
        lastSoundTick = tick - SOUND_INTERVAL
        SKIN:Bang("!SetVariable", "AlertAcknowledged", "0")
        SKIN:Bang("!Log", "AlertPulse: new active alerts detected", "Notice")
    end

    -- All-clear: reset arm so next activation fires immediately
    if not anyAlert and prevActive then
        lastSoundTick = tick - SOUND_INTERVAL
        SKIN:Bang("!Log", "AlertPulse: all alerts cleared", "Notice")
    end

    prevActive = anyAlert

    -- Sound: tiered by severity
    local tornadoWarn  = flags["TornadoWarning"] == true
    local tornadoWatch = flags["TornadoWatch"]   == true
    local muted = SKIN:GetVariable("AlertMuteSound") or "0"
    if not acknowledged then
        if tornadoWarn and (tick - lastSoundTick >= TORNADO_WARN_INTERVAL) then
            -- Tornado warning: rapid alternating alarm every 1 s
            if muted ~= "1" then
                SKIN:Bang("!CommandMeasure", "MeasureAlertSoundTornadoPS", "Run")
            end
            lastSoundTick = tick
        elseif (anyWarn or tornadoWatch) and (tick - lastSoundTick >= SOUND_INTERVAL) then
            -- Normal alerts + tornado watch: triple beep every 30 s
            if muted ~= "1" then
                SKIN:Bang("!CommandMeasure", "MeasureAlertSoundPS", "Run")
                SKIN:Bang("!Log", "AlertPulse: sound triggered (tick=" .. tick .. ")", "Notice")
            else
                SKIN:Bang("!Log", "AlertPulse: sound suppressed (AlertMuteSound=1)", "Notice")
            end
            lastSoundTick = tick
        end
    end

    local needRedraw = false

    -- ACK button visibility — only bang when state changes
    local ackHidden = not (anyAlert and not acknowledged)
    if ackHidden ~= lastAckHidden then
        lastAckHidden = ackHidden
        setHidden(ACK_METER, ackHidden)
        needRedraw = true
    end

    -- Layout — only when flags change
    local sig = flagSig(flags)
    if sig ~= prevFlagSig then
        prevFlagSig = sig
        updateLayout(flags)
        needRedraw = true
    end

    -- Alpha pulse — only bang when alpha value changes
    local alpha = (anyWarn and not acknowledged) and pulseAlpha() or 255
    if alpha ~= lastAlpha then
        lastAlpha  = alpha
        for _, p in ipairs(ALL_PAIRS) do
            if flags[p.key] then
                setAlpha(p.t, p.warn and alpha or 255)
            end
        end
        needRedraw = true
    end

    -- Dynamic skin height
    local alertRowY = tonumber(SKIN:GetVariable("AlertRowY") or "470")
    local pad       = tonumber(SKIN:GetVariable("Pad") or "16")
    local newH
    if row3 then
        newH = alertRowY + ROW3_OFFSET + 54 + pad
    elseif row2 then
        newH = alertRowY + ROW2_OFFSET + 54 + pad
    elseif row1 then
        newH = alertRowY + 54 + pad
    else
        newH = BASE_H
    end
    if newH ~= currentH then
        currentH = newH
        SKIN:Bang("!SetVariable", "H", tostring(newH))
        SKIN:Bang("!UpdateMeter", "MeterBackground")
        needRedraw = true
    end

    if needRedraw then SKIN:Bang("!Redraw") end
    return ""
end

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

local POPUP_W = 360
local POPUP_METERS = {
    "MeterAlertDetailBG", "MeterAlertDetailTitle",
    "MeterAlertDetailExpiry", "MeterAlertDetailDesc", "MeterAlertDetailClose",
}

-- Module-level state
local tick          = 0
local acknowledged  = false
local lastSoundTick = -300   -- fire immediately on first detection
local prevActive    = false
local currentH      = 0       -- last H sent; 0 = unset
local prevFlagSig   = ""      -- fingerprint of last known flags
local lastAlpha     = -1      -- last alpha sent; skip bang when unchanged
local lastAckHidden = nil     -- last ACK button state; skip bang when unchanged
local cachedFlags   = {}      -- flags from last JSON read
local cachedDetails = {}      -- details from last JSON read
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

-- Read nws_alert_details.json; returns table of key→{event,exp,desc}
local function readDetails()
    local path = SKIN:GetVariable("NWS_JSON") or ""
    if path == "" then return {} end
    local detailsPath = path:gsub("nws_alerts%.json$", "nws_alert_details.json")
    local f = io.open(detailsPath, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    local details = {}
    for key, obj in content:gmatch('"(%w+)":%s*(%b{})') do
        local event = obj:match('"event"%s*:%s*"(.-)"')
        local exp   = obj:match('"exp"%s*:%s*"(.-)"')
        local desc  = obj:match('"desc"%s*:%s*"(.-)"')
        if desc then desc = desc:gsub('\\n', '\n') end
        details[key] = {
            event = event or key,
            exp   = exp   or "",
            desc  = desc  or "",
        }
    end
    return details
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

-- Pack active icons sequentially: row 1 fills first, then row 2, then row 3.
-- Only called when flags actually change.
local function updateLayout(flags)
    HideDetail()   -- dismiss popup whenever alert layout changes
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
    SKIN:Bang("!SetVariable", "AlertPulseAlpha", "255")
    SKIN:Bang("!Redraw")
    SKIN:Bang("!Log", "AlertPulse: acknowledged by user", "Notice")
end

-- Format NWS description: blank line between sections, leading "* " → "- "
local function formatNWSDesc(text)
    local out = {}
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
        if #para > 0 then
            if #out > 0 then out[#out+1] = "" end   -- blank line between sections
            out[#out+1] = para:gsub("^%* ", "- ")
        end
    end
    return table.concat(out, "\n")
end

-- Word-wrap text to maxChars per line, preserving paragraph breaks.
-- All-caps paragraphs (old NWS format) use a tighter limit because
-- uppercase letters are ~20% wider than mixed case at the same point size.
local function wordWrap(text, maxChars)
    local out = {}
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
        if #para == 0 then
            out[#out+1] = ""
        else
            -- Detect all-caps paragraph (letters only uppercase, no lowercase)
            local limit = maxChars
            if not para:match("[a-z]") and para:match("[A-Z]") then
                limit = math.floor(maxChars * 0.80)
            end
            local line = ""
            for word in para:gmatch("%S+") do
                if #line == 0 then
                    line = word
                elseif #line + 1 + #word <= limit then
                    line = line .. " " .. word
                else
                    out[#out+1] = line
                    line = word
                end
            end
            if #line > 0 then out[#out+1] = line end
        end
    end
    return table.concat(out, "\n")
end

-- Called by icon LeftMouseUpAction: ShowDetail('KeyName')
function ShowDetail(key)
    local iconX, iconY = ICON_ORIGIN, tonumber(SKIN:GetVariable("AlertRowY") or "470")
    for _, p in ipairs(ALL_PAIRS) do
        if p.key == key then
            local m = SKIN:GetMeter(p.t)
            if m then iconX, iconY = m:GetX(), m:GetY() end
            break
        end
    end

    local skinW = tonumber(SKIN:GetVariable("W")   or "620")
    local pad   = tonumber(SKIN:GetVariable("Pad") or "16")

    -- Horizontal clamp; always open below icon (popup grows downward)
    local px = iconX
    if px + POPUP_W > skinW - pad then px = skinW - pad - POPUP_W end
    if px < pad then px = pad end
    local py = iconY + 64

    local d = cachedDetails[key]
    local title   = key
    local expLine = ""
    local desc    = ""
    if d then
        if d.event ~= "" then title   = d.event end
        if d.exp   ~= "" then expLine = "Expires: " .. d.exp end
        desc = d.desc
    end

    local function set(name, opts)
        for k, v in pairs(opts) do SKIN:Bang("!SetOption", name, k, v) end
        SKIN:Bang("!SetOption", name, "Hidden", "0")
        SKIN:Bang("!UpdateMeter", name)
    end

    -- Pre-wrap description so Rainmeter doesn't need to re-flow it
    local wrappedDesc = wordWrap(formatNWSDesc(desc), 46)

    -- Update text meters; desc has no fixed H so Rainmeter auto-sizes it
    set("MeterAlertDetailTitle",  {X=tostring(px+12), Y=tostring(py+10), W=tostring(POPUP_W-52), Text=title})
    set("MeterAlertDetailExpiry", {X=tostring(px+12), Y=tostring(py+36), W=tostring(POPUP_W-24), Text=expLine})
    set("MeterAlertDetailDesc",   {X=tostring(px+12), Y=tostring(py+58), W=tostring(POPUP_W-24), Text=wrappedDesc})

    -- Read actual rendered height of desc (fallback: estimate from char count)
    local dm    = SKIN:GetMeter("MeterAlertDetailDesc")
    local descH = dm and dm:GetH() or 0
    if descH <= 0 then
        -- Count explicit newlines in pre-wrapped text, ~13px per line
        local nlines = 1
        for _ in wrappedDesc:gmatch("\n") do nlines = nlines + 1 end
        descH = nlines * 18 + 8
    end
    local totalH = 58 + descH + 14   -- top padding + desc + bottom padding

    set("MeterAlertDetailClose", {X=tostring(px+POPUP_W-30), Y=tostring(py+8)})

    -- BG sized to fit actual content height
    SKIN:Bang("!SetOption", "MeterAlertDetailBG", "X", tostring(px))
    SKIN:Bang("!SetOption", "MeterAlertDetailBG", "Y", tostring(py))
    SKIN:Bang("!SetOption", "MeterAlertDetailBG", "Shape",
        string.format("Rectangle 0,0,%d,%d,6 | StrokeWidth 1 | Stroke Color 255,255,255,50 | Fill Color 12,18,32,255",
            POPUP_W, totalH))
    SKIN:Bang("!SetOption", "MeterAlertDetailBG", "Hidden", "0")
    SKIN:Bang("!UpdateMeter", "MeterAlertDetailBG")

    SKIN:Bang("!Redraw")
end

-- Called by close button and whenever alert layout changes
function HideDetail()
    for _, m in ipairs(POPUP_METERS) do
        SKIN:Bang("!SetOption",  m, "Hidden", "1")
        SKIN:Bang("!UpdateMeter", m)
    end
    SKIN:Bang("!Redraw")
end

function Update()
    tick = tick + 1

    -- Read JSON at ~1/min (every 300 ticks = 60 s at 200 ms base rate)
    if tick - lastJsonTick >= 300 then
        cachedFlags   = readFlags()
        cachedDetails = readDetails()
        lastJsonTick  = tick
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
        elseif anyWarn and (tick - lastSoundTick >= SOUND_INTERVAL) then
            -- Warnings only: triple beep every 30 s (watches are silent)
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
    local ackHidden = not (anyWarn and not acknowledged)
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

    -- Alpha pulse — single SetVariable drives all warn meters via DynamicVariables
    local alpha = (anyWarn and not acknowledged) and pulseAlpha() or 255
    if alpha ~= lastAlpha then
        lastAlpha = alpha
        SKIN:Bang("!SetVariable", "AlertPulseAlpha", tostring(alpha))
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

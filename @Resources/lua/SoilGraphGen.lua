
-- SoilGraphGen.lua
-- Reads the rolling soil-temp CSV and draws a bar chart on MeterSoilGraph
-- using Rainmeter Shape options (Shape, Shape2, Shape3, ...).
-- Triggered via: [!CommandMeasure MeasureSoilGraphGen "Run()"]

function Initialize()
end

function Run()
    local csvPath = SKIN:GetVariable('SoilHistCsv')
    SKIN:Bang('!Log', 'SoilGraphGen Run() called. csvPath=' .. tostring(csvPath), 'Notice')
    local col     = tonumber(SKIN:GetVariable('SoilGraphCol'))  or 2
    local days    = tonumber(SKIN:GetVariable('SoilGraphDays')) or 45
    local barW    = tonumber(SKIN:GetVariable('SoilGraphBarW')) or 4
    local barGap  = tonumber(SKIN:GetVariable('SoilGraphBarGap')) or 0
    local graphH  = tonumber(SKIN:GetVariable('SoilGraphH'))    or 100
    local minF    = tonumber(SKIN:GetVariable('SoilGraphMinF')) or 25
    local maxF    = tonumber(SKIN:GetVariable('SoilGraphMaxF')) or 100
    local range   = maxF - minF

    -- Parse CSV (first row = header, skip it)
    local rows = {}
    local f = io.open(csvPath, 'r')
    if f then
        local isHeader = true
        for line in f:lines() do
            if isHeader then
                isHeader = false
            else
                local fields = {}
                for v in line:gmatch('[^,\r\n]+') do
                    fields[#fields + 1] = v
                end
                if #fields >= col then
                    rows[#rows + 1] = { date = fields[1], val = tonumber(fields[col]) }
                end
            end
        end
        f:close()
    end

    -- Use the last 'days' rows
    local startIdx = math.max(1, #rows - days + 1)
    local bars = {}
    for i = startIdx, #rows do
        bars[#bars + 1] = rows[i]
    end

    -- Color: cold=blue → warm=green → hot=red
    local function barColor(val)
        local frac = math.max(0, math.min(1, (val - minF) / range))
        local r, g, b
        if frac < 0.5 then
            local t = frac * 2          -- 0..1 across blue→green
            r = math.floor(60  + t * 20)
            g = math.floor(120 + t * 80)
            b = math.floor(230 - t * 130)
        else
            local t = (frac - 0.5) * 2 -- 0..1 across green→red
            r = math.floor(80  + t * 175)
            g = math.floor(200 - t * 120)
            b = math.floor(100 - t * 50)
        end
        return r, g, b
    end

    local METER = 'MeterSoilGraph'

    -- Set a shape for each bar
    for i, bar in ipairs(bars) do
        local key = (i == 1) and 'Shape' or ('Shape' .. i)
        if bar.val then
            local frac = math.max(0, math.min(1, (bar.val - minF) / range))
            local barH = math.max(1, math.floor(frac * graphH))
            local bx   = (i - 1) * (barW + barGap)
            local by   = graphH - barH
            local r, g, b = barColor(bar.val)
            SKIN:Bang('!SetOption', METER, key,
                string.format('Rectangle %d,%d,%d,%d | Fill Color %d,%d,%d,210 | StrokeWidth 0',
                    bx, by, barW, barH, r, g, b))
        else
            -- Missing value: invisible placeholder
            local bx = (i - 1) * (barW + barGap)
            SKIN:Bang('!SetOption', METER, key,
                string.format('Rectangle %d,%d,%d,1 | Fill Color 0,0,0,0 | StrokeWidth 0',
                    bx, graphH - 1, barW))
        end
    end

    -- Erase leftover shape slots from any previous longer render
    local clearUpTo = days + 5
    for i = #bars + 1, clearUpTo do
        local key = (i == 1) and 'Shape' or ('Shape' .. i)
        SKIN:Bang('!SetOption', METER, key, '')
    end

    -- Tooltip: show most-recent date + value
    if #bars > 0 then
        local last  = bars[#bars]
        local label = (col == 2) and 'Min 7-day' or 'Avg 7-day'
        local tip   = string.format('%s  %s: %.1f°F', last.date or '?', label, last.val or 0)
        SKIN:Bang('!SetOption', METER, 'ToolTipText', tip)
    end

    SKIN:Bang('!Log', 'SoilGraphGen: set ' .. #bars .. ' bars on ' .. METER, 'Notice')
    SKIN:Bang('!UpdateMeter', METER)
    SKIN:Bang('!Redraw')
end

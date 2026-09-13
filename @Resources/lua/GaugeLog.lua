-- ============================================================
-- GaugeLog.lua — record readings from the physical rain gauge
--
-- Entries arrive from the InputText box (right-click -> "Log rain gauge
-- reading"). Each entry is appended as its own timestamped row, so the log is
-- append-only and nothing is ever silently overwritten; a day's total is the
-- SUM of its rows. That matches emptying a tipping bucket more than once in a
-- day. To correct a mistake, edit the CSV directly (right-click -> "Open rain
-- gauge log") — the totals are derived, so fixing a row fixes everything.
--
-- Readings are attributed to the calendar date they are ENTERED on. The
-- Mesonet daily bucket behaves the same way: the 2026-09-12/13 overnight cell,
-- which began around 22:00, landed in the 09-13 bucket. So a morning-after
-- reading lines up with the estimate it should be compared against.
--
-- Report() scores the Mesonet gauge-network estimate (ks_precip_daily.csv)
-- against these readings. That is what can eventually tune KSPrecipPower from
-- real local data instead of from cross-validation.
-- ============================================================

local function appendLog(path, msg)
  if not path or path == "" then return end
  local f = io.open(path, "a")
  if f then f:write(msg .. "\n"); f:close() end
end

local function logPath()    return SKIN:GetVariable("GaugeLogCsv", "")     end
local function reportPath() return SKIN:GetVariable("GaugeReportTxt", "")  end
local function estPath()    return SKIN:GetVariable("KSPrecipCsv", "")     end
local function masterLog()  return SKIN:GetVariable("HeartlandLog", "")    end

-- date -> summed inches from the user's own readings
local function readEntries()
  local out, n = {}, 0
  local p = logPath()
  if p == "" then return out, 0 end
  local f = io.open(p, "r")
  if not f then return out, 0 end
  for line in f:lines() do
    local d, v = line:match("^[^,]*,(%d%d%d%d%-%d%d%-%d%d),([%d%.%-]+)")
    if d and v then
      local num = tonumber(v)
      if num then out[d] = (out[d] or 0) + num; n = n + 1 end
    end
  end
  f:close()
  return out, n
end

-- date -> inches estimated by the Mesonet network
local function readEstimates()
  local out = {}
  local p = estPath()
  if p == "" then return out end
  local f = io.open(p, "r")
  if not f then return out end
  for line in f:lines() do
    local d, v = line:match("^(%d%d%d%d%-%d%d%-%d%d),([%d%.%-]+)")
    if d and v then out[d] = tonumber(v) end
  end
  f:close()
  return out
end

-- Rebuild the comparison report. Only days that have BOTH a reading and an
-- estimate can be scored; days where the estimate has aged out of the trailing
-- window are listed separately rather than silently dropped.
function Report()
  local entries, rowCount = readEntries()
  local est = readEstimates()

  local dates = {}
  for d in pairs(entries) do dates[#dates + 1] = d end
  table.sort(dates)

  local lines = {}
  lines[#lines + 1] = "Rain gauge: your readings vs the Mesonet estimate"
  lines[#lines + 1] = "Generated " .. os.date("%Y-%m-%d %H:%M:%S")
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("%-12s %9s %10s %9s", "date", "yours", "estimate", "diff")
  lines[#lines + 1] = string.rep("-", 43)

  local n, sumErr, sumAbs = 0, 0, 0
  local unscored = {}
  for _, d in ipairs(dates) do
    local mine = entries[d]
    local e = est[d]
    if e then
      local diff = e - mine
      n = n + 1; sumErr = sumErr + diff; sumAbs = sumAbs + math.abs(diff)
      lines[#lines + 1] = string.format("%-12s %9.2f %10.2f %+9.2f", d, mine, e, diff)
    else
      unscored[#unscored + 1] = string.format("%-12s %9.2f %10s", d, mine, "--")
    end
  end

  lines[#lines + 1] = ""
  if n > 0 then
    lines[#lines + 1] = string.format("Scored days : %d", n)
    lines[#lines + 1] = string.format("Mean error  : %+.3f in   (negative = estimate runs low)", sumErr / n)
    lines[#lines + 1] = string.format("Mean abs err: %.3f in", sumAbs / n)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "If the mean error is consistently negative, the estimate is diluting"
    lines[#lines + 1] = "local cells: raise KSPrecipPower (8 is nearly nearest-station-only)."
    lines[#lines + 1] = "If consistently positive, lower it to smooth across more stations."
    lines[#lines + 1] = "Treat this as meaningful only after a dozen or so rain days."
  else
    lines[#lines + 1] = "No days yet where a reading and an estimate overlap."
  end

  if #unscored > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Outside the estimate's trailing window (not scored):"
    for _, u in ipairs(unscored) do lines[#lines + 1] = "  " .. u end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("%d reading(s) across %d day(s).", rowCount, #dates)

  local p = reportPath()
  if p ~= "" then
    local f = io.open(p, "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
  end
  return n
end

-- Called from the InputText box. Accepts things like "0.22", ".22", "0.22 in".
function Add(raw)
  raw = tostring(raw or ""):gsub('"', ''):gsub("^%s+", ""):gsub("%s+$", "")
  local num = tonumber(raw:match("^[%d%.]+") or "")

  if not num then
    appendLog(masterLog(), os.date("%Y-%m-%d %H:%M:%S") ..
      " | GaugeLog | ignored non-numeric entry: '" .. raw .. "'")
    SKIN:Bang("!Log", "GaugeLog: ignored non-numeric entry '" .. raw .. "'", "Warning")
    return
  end
  -- A tipping bucket that reads over 12 in in a day is a typo, not a monsoon.
  if num < 0 or num > 12 then
    SKIN:Bang("!Log", "GaugeLog: rejected out-of-range entry " .. tostring(num), "Warning")
    return
  end

  local p = logPath()
  if p == "" then return end
  local isNew = (io.open(p, "r") == nil)
  local f = io.open(p, "a")
  if not f then
    SKIN:Bang("!Log", "GaugeLog: cannot write " .. p, "Error")
    return
  end
  if isNew then f:write("timestamp,date,inches\n") end
  f:write(string.format("%s,%s,%.2f\n", os.date("%Y-%m-%dT%H:%M:%S"), os.date("%Y-%m-%d"), num))
  f:close()

  local msg = string.format("%s | GaugeLog | recorded %.2f in", os.date("%Y-%m-%d %H:%M:%S"), num)
  appendLog(masterLog(), msg)
  SKIN:Bang("!Log", string.format("GaugeLog: recorded %.2f in", num), "Notice")
  Report()
end

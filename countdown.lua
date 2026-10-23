local M = {}

M.WINDOW_SECONDS = 20
M.WINDOW_INTERVAL = 600
M.WINDOW_COUNTS = { 1, 7 }
M.NAME_MAX = 30

-- A checkpoint due while zoning is sent on zone-in only if it is no later than this.
local LATE_LIMIT = 5

-- firstOnly checkpoints exist only on the first window run, and only when started before they are due;
-- on later windows the 10 min mark falls on the previous window's open.
local CHECKPOINTS = {
    { offset = -600, label = '10m',    text = '10 min', firstOnly = true },
    { offset = -300, label = '5m',     text = '5 min' },
    { offset = -180, label = '3m',     text = '3 min' },
    { offset = -120, label = '2m',     text = '2 min' },
    { offset = -60,  label = '1m',     text = '1 min' },
    { offset = -30,  label = '30s',    text = '30 sec' },
    { offset = -10,  label = '10s',    text = '10 sec' },
    { offset = 0,    label = 'Open',   text = 'NOW / Window Open' },
    { offset = M.WINDOW_SECONDS, label = 'Done' },
}

local active = nil
local last = nil

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- The hour is masked: it differs between timezones, minutes and seconds do not.
function M.formatXX(epoch)
    return os.date('xx:%M:%S', math.floor(epoch))
end

-- HH:MM:SS is local 24h time, rolling to tomorrow once passed.
-- MM:SS is the next occurrence of that minute and second.
function M.parseTime(text, now)
    text = trim(text or '')
    if text == '' then
        return nil, 'Enter a time.'
    end

    local floorNow = math.floor(now)
    local h, m, s = text:match('^(%d%d?):(%d%d):(%d%d)$')
    if h ~= nil then
        h, m, s = tonumber(h), tonumber(m), tonumber(s)
        if h > 23 or m > 59 or s > 59 then
            return nil, 'Time out of range (00:00:00-23:59:59).'
        end
        local t = os.date('*t', floorNow)
        t.hour, t.min, t.sec, t.isdst = h, m, s, nil
        local target = os.time(t)
        if target <= now then
            t.day = t.day + 1
            t.isdst = nil
            target = os.time(t)
        end
        return target
    end

    m, s = text:match('^(%d%d?):(%d%d)$')
    if m ~= nil then
        m, s = tonumber(m), tonumber(s)
        if m > 59 or s > 59 then
            return nil, 'Time out of range (00:00-59:59).'
        end
        local t = os.date('*t', floorNow)
        local target = floorNow - t.min * 60 - t.sec + m * 60 + s
        if target <= now then
            target = target + 3600
        end
        return target
    end

    return nil, 'Use HH:MM:SS or MM:SS.'
end

-- FFXI expands <t>, <me> and similar in sent chat, so angle brackets are rejected.
function M.validateName(name)
    name = trim(name or '')
    if name == '' then
        return nil, 'Enter a name.'
    end
    if #name > M.NAME_MAX then
        return nil, string.format('Name is over %d characters.', M.NAME_MAX)
    end
    if name:find('[^\32-\126]') then
        return nil, 'Name must be plain ASCII.'
    end
    if name:find('[<>]') then
        return nil, 'Name cannot contain < or >.'
    end
    return name
end

local function formatLead(seconds)
    if seconds >= 60 then
        return string.format('~%d min', math.floor(seconds / 60 + 0.5))
    end
    return string.format('%d sec', math.floor(seconds))
end

-- Checkpoints already due are skipped.
local function buildCheckpoints(now, isFirst)
    local hasNext = active.window < active.windowCount
    local checkpoints = {}
    for _, cp in ipairs(CHECKPOINTS) do
        local due = active.target + cp.offset
        if not cp.firstOnly or (isFirst and due > now) then
            checkpoints[#checkpoints + 1] = {
                label  = (cp.offset > 0 and hasNext) and 'Next' or cp.label,
                text   = cp.text,
                offset = cp.offset,
                due    = due,
                status = (due <= now) and 'skipped' or 'pending',
            }
        end
    end
    active.checkpoints = checkpoints
end

-- target is the time of window `window`; later windows follow every WINDOW_INTERVAL.
-- Returns the start message.
function M.start(name, target, now, windowCount, window)
    active = { name = name, target = target, windowCount = windowCount or 1, window = window or 1 }
    last = active
    buildCheckpoints(now, true)
    return string.format('--- %s --- Timer: %s (%s)', name, M.formatXX(target), formatLead(target - now))
end

function M.cancel()
    active = nil
end

function M.get()
    return active
end

-- 'Name - W3/7 - xx:MM:SS', or 'Name - xx:MM:SS' for a single window.
function M.describe(timer)
    if timer.windowCount > 1 then
        return string.format('%s - W%d/%d - %s', timer.name, timer.window, timer.windowCount, M.formatXX(timer.target))
    end
    return string.format('%s - %s', timer.name, M.formatXX(timer.target))
end

-- The running timer, or the last one after it finished or was cancelled.
function M.getLast()
    return last
end

local function message(cp)
    if cp.offset > 0 then
        if active.window < active.windowCount then
            return string.format('--- %s --- Next Window [%d/%d] (%s)', active.name,
                active.window + 1, active.windowCount, M.formatXX(active.target + M.WINDOW_INTERVAL))
        end
        return string.format('--- %s --- Window Done (%s)', active.name, M.formatXX(cp.due))
    end
    return string.format('--- %s --- %s (%s)', active.name, cp.text, M.formatXX(active.target))
end

-- Sends due checkpoints through send(msg). Returns true when the timer finished this tick.
function M.tick(now, canSend, send)
    if active == nil then return false end
    for _, cp in ipairs(active.checkpoints) do
        if cp.status == 'pending' and cp.due <= now then
            if now - cp.due > LATE_LIMIT then
                cp.status = 'dropped'
            elseif canSend then
                send(message(cp))
                cp.status = 'sent'
            end
        end
    end
    local final = active.checkpoints[#active.checkpoints]
    if final.status ~= 'pending' then
        if active.window < active.windowCount then
            active.window = active.window + 1
            active.target = active.target + M.WINDOW_INTERVAL
            buildCheckpoints(now, false)
            return false
        end
        active = nil
        return true
    end
    return false
end

return M

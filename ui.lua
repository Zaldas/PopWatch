local imgui     = require('imgui')
local uiTheme   = require('libs/uiTheme')
local alliance  = require('alliance')
local clock     = require('clock')
local countdown = require('countdown')

local M = {}

local open    = { false }
local nameBuf = { '' }
local timeBuf = { '' }
local windowCountIdx = { 0 }
local currentWindowIdx = { 0 }
local ssTaken = { false }
local ssTimer = nil

local WINDOW_COUNT_LIST = table.concat(countdown.WINDOW_COUNTS, '\0') .. '\0'

local STATUS_COLORS = {
    sent    = { 0.45, 0.85, 0.45, 1.00 },
    pending = { 0.92, 0.94, 0.97, 1.00 },
    skipped = { 0.40, 0.44, 0.52, 1.00 },
    dropped = { 0.95, 0.40, 0.40, 1.00 },
}
local ERROR_COLOR = { 0.95, 0.40, 0.40, 1.00 }

local HELP_NEW = 'Announces at 5m, 3m, 2m, 1m, 30s and 10s before the window, '
    .. 'when it opens, and 20s after. Checkpoints already passed at start are skipped.\n\n'
    .. 'Started more than 10 min out, the first window also gets a 10 min warning.\n\n'
    .. 'With 7 windows, each follows the last by 10 min. Enter the time of the current window.\n\n'
    .. 'Command: /pw <time> <name>, /pw cancel'
local HELP_RUNNING = 'Green: sent. White: pending. Grey: skipped, already passed at start. '
    .. 'Red: dropped, due while zoning.'

function M.toggle()
    open[1] = not open[1]
end

local function drawChannelCombo(ctx)
    imgui.SetNextItemWidth(uiTheme.comboWidth())
    local idx = { ctx.channelIndex - 1 }
    if imgui.Combo('Channel##channel', idx, ctx.channelList) then
        ctx.onChannel(idx[1] + 1)
    end
end

local function drawClockLine()
    local now = math.floor(clock.now())
    local pcOffset = clock.pcOffset()
    if pcOffset == nil then
        imgui.TextDisabled(string.format('PC clock %s (server not synced)', os.date('%H:%M:%S', now)))
    else
        imgui.TextDisabled(string.format('Server clock %s  (PC %+.1fs)', os.date('%H:%M:%S', now), pcOffset))
    end
end

local function drawSeparator()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
end

-- An error replaces the field's help lines.
local function drawFieldHelp(err, lines)
    if err ~= nil then
        imgui.TextColored(ERROR_COLOR, err)
        return
    end
    for _, line in ipairs(lines) do
        imgui.TextDisabled(line)
    end
end

local function drawNewTimer(ctx)
    uiTheme.header('New timer', HELP_NEW)
    imgui.Indent(uiTheme.indent)

    imgui.SetNextItemWidth(uiTheme.comboWidth())
    imgui.InputText('Name##name', nameBuf, countdown.NAME_MAX + 1)
    local name, nameErr = countdown.validateName(nameBuf[1])
    drawFieldHelp(nameBuf[1] ~= '' and nameErr or nil, {
        string.format('ASCII, max %d, no < >', countdown.NAME_MAX),
    })
    drawSeparator()

    imgui.SetNextItemWidth(uiTheme.comboWidth())
    imgui.InputText('Time##time', timeBuf, 9)
    local target, timeErr = countdown.parseTime(timeBuf[1], clock.now())
    drawFieldHelp(timeBuf[1] ~= '' and timeErr or nil, {
        'HH:MM:SS  your local time, 24h',
        'MM:SS     next time the clock shows it',
        'A passed HH:MM:SS rolls to tomorrow.',
    })
    drawSeparator()

    imgui.SetNextItemWidth(uiTheme.comboWidth())
    imgui.Combo('Windows##windows', windowCountIdx, WINDOW_COUNT_LIST)
    local windowCount = countdown.WINDOW_COUNTS[windowCountIdx[1] + 1]
    drawFieldHelp(nil, { '1 window, or 7 windows 10 min apart.' })
    if windowCount > 1 then
        drawSeparator()
        local windows = {}
        for i = 1, windowCount do
            windows[i] = tostring(i)
        end
        imgui.SetNextItemWidth(uiTheme.comboWidth())
        imgui.Combo('Current window##current', currentWindowIdx, table.concat(windows, '\0') .. '\0')
        drawFieldHelp(nil, { 'The window the entered time belongs to.' })
    end
    drawSeparator()

    drawChannelCombo(ctx)
    drawFieldHelp(nil, { 'Echo shows messages only to you.' })
    drawSeparator()

    drawClockLine()

    imgui.Unindent(uiTheme.indent)
    drawSeparator()

    local ready = name ~= nil and target ~= nil
    if uiTheme.centeredButton('Start', ready and 'primary' or 'ghost') and ready then
        nameBuf[1] = ''
        timeBuf[1] = ''
        local window = (windowCount > 1) and (currentWindowIdx[1] + 1) or 1
        ctx.onStart(name, target, windowCount, window)
    end
end

local function formatRemaining(remaining)
    if remaining > 0 then
        local secs = math.ceil(remaining)
        if secs >= 3600 then
            return string.format('T- %d:%02d:%02d', math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60)
        end
        return string.format('T- %d:%02d', math.floor(secs / 60), secs % 60)
    end
    local secs = math.floor(-remaining)
    return string.format('T+ %d:%02d', math.floor(secs / 60), secs % 60)
end

local function drawRunning(ctx, timer)
    uiTheme.header(timer.name, HELP_RUNNING)
    imgui.Indent(uiTheme.indent)

    local remaining = formatRemaining(timer.target - clock.now())
    local pushed = pcall(imgui.PushFont, imgui.GetFont(), imgui.GetFontSize() * 2)
    imgui.Text(remaining)
    if pushed then imgui.PopFont() end

    if timer.windowCount > 1 then
        imgui.TextColored(uiTheme.accent, string.format('Window %d/%d', timer.window, timer.windowCount))
    end
    imgui.TextDisabled(string.format('Window %s - done %s',
        countdown.formatXX(timer.target), countdown.formatXX(timer.target + countdown.WINDOW_SECONDS)))
    drawChannelCombo(ctx)
    imgui.Spacing()

    imgui.TextColored(STATUS_COLORS.sent, 'Timer')
    for _, cp in ipairs(timer.checkpoints) do
        if cp.label ~= '30s' then imgui.SameLine() end
        imgui.TextColored(STATUS_COLORS[cp.status], cp.label)
    end
    imgui.Spacing()
    drawClockLine()

    imgui.Unindent(uiTheme.indent)
    drawSeparator()

    if uiTheme.centeredButton('Cancel', 'danger') then
        ctx.onCancel()
    end
end

local function drawAlliance(ctx)
    local timer = countdown.getLast()
    if timer ~= nil then
        uiTheme.header(countdown.describe(timer))
    else
        uiTheme.header('No timer running')
    end
    imgui.Indent(uiTheme.indent)

    local parties = alliance.read()
    local any = false
    for p, names in ipairs(parties) do
        if #names > 0 then
            imgui.TextWrapped(alliance.partyLine(p, names))
            any = true
        end
    end
    if not any then
        imgui.TextDisabled('Not in a party.')
    end

    imgui.Unindent(uiTheme.indent)
    drawSeparator()

    if uiTheme.centeredButton('Copy for Discord', 'primary') then
        ctx.onCopy(parties)
    end
    if imgui.IsItemHovered() then
        uiTheme.tooltipBegin()
        imgui.TextUnformatted('Copies the timer and party lines as a Discord code block.')
        uiTheme.tooltipEnd()
    end

    -- Resets when a new timer starts, not when one finishes: the screenshot is often taken after the pop.
    if timer ~= nil and timer ~= ssTimer then
        ssTaken[1] = false
        ssTimer = timer
    end
    imgui.Spacing()
    imgui.Indent(uiTheme.indent)
    if imgui.Checkbox('Ally Snapshot taken', ssTaken) and ssTaken[1] then
        ctx.onSsTaken()
    end
    uiTheme.helpMarker('Checking it posts "Ally Snapshot taken for DKP" to party chat. Clears when a new timer starts.')
    imgui.Unindent(uiTheme.indent)
end

local function drawBody(ctx)
    if imgui.BeginTabBar('##popwatch_tabs') then
        if imgui.BeginTabItem('Timer') then
            imgui.Spacing()
            local timer = countdown.get()
            if timer ~= nil then
                drawRunning(ctx, timer)
            else
                drawNewTimer(ctx)
            end
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem('Alliance') then
            imgui.Spacing()
            drawAlliance(ctx)
            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
end

function M.draw(ctx)
    if not open[1] then return end

    -- The ### suffix keeps the window ID stable while the visible title changes.
    local n = uiTheme.push()
    imgui.SetNextWindowSizeConstraints({ 300, 0 }, { 300, 9999 })
    local ok, err = true, nil
    if imgui.Begin(ctx.windowTitle .. '###Popwatch', open, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(drawBody, ctx)
    end
    imgui.End()
    uiTheme.pop(n)
    if not ok then error(err, 0) end
end

return M

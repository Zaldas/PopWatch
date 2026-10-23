addon.name    = 'Popwatch'
addon.author  = 'zaldas'
addon.version = '0.1'
addon.desc    = 'Spawn window countdown announcer and alliance roster'

require('common')
local chat      = require('chat')
local alliance  = require('alliance')
local clock     = require('clock')
local countdown = require('countdown')
local ui        = require('ui')

local CHANNELS = {
    { label = 'Echo',  command = '/echo' },
    { label = 'Party', command = '/p' },
    { label = 'LS1',   command = '/l' },
    { label = 'LS2',   command = '/l2' },
}

local channelLabels = {}
for i, ch in ipairs(CHANNELS) do
    channelLabels[i] = ch.label
end

local channelIndex = 1

local function notify(msg)
    print(chat.header(addon.name) .. chat.message(msg))
end

local function notifyError(msg)
    print(chat.header(addon.name) .. chat.error(msg))
end

local function send(msg)
    AshitaCore:GetChatManager():QueueCommand(1, string.format('%s %s', CHANNELS[channelIndex].command, msg))
end

local function canSend()
    if GetPlayerEntity() == nil then return false end
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    return player ~= nil and player:GetIsZoning() == 0
end

local function timerSuffix(timer)
    if timer == nil then return '' end
    return string.format(' - %s - %s', timer.name, countdown.formatXX(timer.target))
end

local function setChannel(index)
    channelIndex = index
    if index == 1 then
        notify('Posting disabled - echo only.')
    else
        notify(string.format('Posting to %s.', CHANNELS[index].label))
    end
end

local function startTimer(name, target, windowCount, window)
    send(countdown.start(name, target, clock.now(), windowCount, window))
end

local function cancelTimer()
    local timer = countdown.get()
    if timer == nil then
        notifyError('No timer running.')
        return
    end
    send(string.format('--- %s --- Canceling timer', timer.name))
    countdown.cancel()
end

local function printUsage()
    notify('/pw - toggle the window')
    notify('/pw <HH:MM:SS|MM:SS> <name> - start a timer')
    notify('/pw cancel - cancel the timer')
end

local ctx = {
    channelList = table.concat(channelLabels, '\0') .. '\0',
    onChannel   = setChannel,
    onStart     = startTimer,
    onCancel    = cancelTimer,
    onCopy      = function(parties)
        local timer = countdown.getLast()
        local title = (timer ~= nil) and string.format('%s - %s', addon.name, countdown.describe(timer)) or addon.name
        ashita.misc.set_clipboard(alliance.discordText(title, parties))
        notify('Alliance copied to clipboard.')
    end,
    onSsTaken   = function()
        AshitaCore:GetChatManager():QueueCommand(1, '/p Ally Snapshot taken for DKP')
    end,
}

ashita.events.register('load', 'popwatch_load_cb', function()
    clock.init()
    if not clock.isAvailable() then
        notifyError('Server clock not found - using PC clock.')
    end
end)

ashita.events.register('unload', 'popwatch_unload_cb', function()
    ashita.events.unregister('load', 'popwatch_load_cb')
    ashita.events.unregister('unload', 'popwatch_unload_cb')
    ashita.events.unregister('command', 'popwatch_command_cb')
    ashita.events.unregister('d3d_present', 'popwatch_present_cb')
end)

ashita.events.register('command', 'popwatch_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/popwatch' and cmd ~= '/pw' then return end
    e.blocked = true

    if #args == 1 then
        ui.toggle()
        return
    end

    local sub = args[2]:lower()
    if sub == 'cancel' then
        cancelTimer()
        return
    end
    if sub == 'help' then
        printUsage()
        return
    end

    if countdown.get() ~= nil then
        notifyError('A timer is already running - cancel it first.')
        return
    end
    local target, timeErr = countdown.parseTime(args[2], clock.now())
    if target == nil then
        notifyError(timeErr)
        printUsage()
        return
    end
    local name, nameErr = countdown.validateName(table.concat(args, ' ', 3))
    if name == nil then
        notifyError(nameErr)
        return
    end
    startTimer(name, target)
end)

ashita.events.register('d3d_present', 'popwatch_present_cb', function()
    clock.update()
    countdown.tick(clock.now(), canSend(), send)

    ctx.windowTitle  = string.format('%s.%s%s', addon.name, addon.version, timerSuffix(countdown.get()))
    ctx.channelIndex = channelIndex
    ui.draw(ctx)
end)

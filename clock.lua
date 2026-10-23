local socket = require('socket')

local M = {}

local VANA_TIME_PATTERN = 'B0015EC390518B4C24088D4424005068'
local SAMPLE_COUNT = 30

local pointer = 0
local lastRaw = nil
local samples = {}
local offset = nil

function M.init()
    pointer = ashita.memory.find('FFXiMain.dll', 0, VANA_TIME_PATTERN, 0, 0)
end

-- The client's server timestamp is Unix seconds, set from the zone-in packet.
local function readRaw()
    if pointer == 0 then return nil end
    local base = ashita.memory.read_uint32(pointer + 0x34)
    if base == 0 then return nil end
    local raw = ashita.memory.read_uint32(base + 0x0C)
    if raw == 0 then return nil end
    return raw
end

-- The timestamp ticks once per second; the sub-second phase comes from timing each tick edge.
-- An edge is seen up to a frame late, so every sample undershoots and the max is the best estimate.
function M.update()
    local raw = readRaw()
    if raw == nil then return end
    if lastRaw ~= nil and raw ~= lastRaw then
        local sample = raw - socket.gettime()
        if offset ~= nil and math.abs(sample - offset) > 1 then
            samples = {}
        end
        samples[#samples + 1] = sample
        if #samples > SAMPLE_COUNT then
            table.remove(samples, 1)
        end
        offset = math.max(unpack(samples))
    end
    lastRaw = raw
end

function M.isAvailable()
    return pointer ~= 0
end

-- Server Unix time, or PC time until the first tick edge is seen.
function M.now()
    if offset == nil then
        return socket.gettime()
    end
    return socket.gettime() + offset
end

-- Seconds the PC clock runs ahead of the server; nil until synced.
function M.pcOffset()
    if offset == nil then return nil end
    return -offset
end

return M

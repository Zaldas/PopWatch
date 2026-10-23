local M = {}

-- Party slots 0-5, 6-11 and 12-17 are alliance parties 1-3, in in-game order.
function M.read()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local parties = {}
    for p = 0, 2 do
        local names = {}
        for slot = 0, 5 do
            local index = p * 6 + slot
            if party:GetMemberIsActive(index) ~= 0 then
                local name = party:GetMemberName(index)
                if name ~= nil and name ~= '' then
                    names[#names + 1] = name
                end
            end
        end
        parties[p + 1] = names
    end
    return parties
end

function M.partyLine(p, names)
    return string.format('P%d: %s', p, table.concat(names, ', '))
end

function M.discordText(title, parties)
    local lines = { '```', title }
    for p, names in ipairs(parties) do
        if #names > 0 then
            lines[#lines + 1] = M.partyLine(p, names)
        end
    end
    lines[#lines + 1] = '```'
    return table.concat(lines, '\n')
end

return M

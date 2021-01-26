-- вместилище команд "up", "left"  и прочего алфавита
local genomStore = {}

function genomStore:init()
end

local function initGenom()
    local self = {}
    return setmetatable(self, genomStore)
end



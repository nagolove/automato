require "types"
require "common"

local inspect = require "inspect"
local istate: CommonSetup
local stat: Statistic
local actions: CellActions

-- t.pos, t.code
-- конструктор клетки
function Cell.new(t: CellSetup): Cell
    t = t or {}
    local self: Cell = {}
    self.pos = {}
    if t.pos and t.pos.x then
        self.pos.x = t.pos.x
    else
        self.pos.x = istate.rg:random(1, istate.gridSize)
    end
    if t.pos and t.pos.y then
        self.pos.y = t.pos.y
    else
        self.pos.y = istate.rg:random(1, istate.gridSize)
    end
    if t.code then
        self.code = shallowCopy(t.code)
    else
        --self.code = genCode()
        error("No cell code")
    end
    if t.generation then
        self.generation = self.generation + 1
    else
        self.generation = 1
    end
    self.ip = 1
    self.id = istate.cellId
    istate.cellId = istate.cellId + 1
    self.energy = istate.rg:random(istate.initialEnergy[1], istate.initialEnergy[2])

    self:print()

    return self
end

function Cell:print()
end

function Cell:update(): boolean
    -- здесь работа vm
    local isremoved: boolean

    -- прокрутка кода клетки по кругу
    if self.ip >= #self.code then
        self.ip = 1
    end
    --print("cell", cell.id, "energy", cell.energy)
    if self.energy > 0 then
        local code = self.code[self.ip]
        --print("code", code)
        isremoved = not actions[code](self)
        self.ip = self.ip + 1
        self.energy = self.energy - istate.denergy
    else
        print("cell died with energy", self.energy, "moves", inspect(self.moves))
        isremoved = true
        -- увеличить количество умерших
        stat.died = stat.died + 1
    end
    return isremoved
end

function cellInitInternal(state: CommonSetup, s: Statistic)
    istate = shallowCopy(state)
    actions = state.cellActions
    stat = s
end

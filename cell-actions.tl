require "external"
require "types"
require "mtschemes"
require "love"
require "common"

local inspect = require "inspect"
local serpent = require "serpent"

-- функция возвращает таблицу таблиц. Для запросов вида cell = getGrid()[1][1]
local getGrid: GetGridFunction

-- размер поля
local gridSize: number

-- табличка с действиями клетки
local actions = {}

-- количество энергии прибавляемое за одну съеденную ячейку "еды"
local ENERGY = 10

-- функция-конструктор для создания клетки по координатам x, y
local initCell: InitCellFunction

-- счетчик 
local allEated: number = 0

-- табличка с напралением передачи инфы о клетках выщедщих за границы поля
-- при работе в несколько потоков
local schema: MtSchema

-- текущий номер потока
local curThreadNum: number

--local function isAlive(x: number, y: number, threadNum: number|nil): boolean
local function isAlive(x: number, y: number): boolean
    local t = getGrid()[x][y]
    return t.energy and t.energy > 0
end

-- лучшее название для переменной
local setup: CellActionsInit = {}

-- записать текущее положение клетки в ее табличку передвижений
local function pushPosition(cell: Cell)
    if not cell.moves then
        cell.moves = {}
    end
    if #cell.moves >= 2 then
        local lastX, lastY = cell.moves[#cell.moves - 1], cell.moves[#cell.moves]
        if lastX ~= cell.pos.x and lastY ~= cell.pos.y then
            table.insert(cell.moves, cell.pos.x)
            table.insert(cell.moves, cell.pos.y)
        end
    else
        table.insert(cell.moves, cell.pos.x)
        table.insert(cell.moves, cell.pos.y)
    end
end

local requestThreadDemandTimeout = 0.02

-- проверяет жива ли клетка в определенном потоке
local function isAliveNeighbours(x: number, y: number, threadNum: number): boolean
    print("threadNum", threadNum)
    local msgChan = love.thread.getChannel("msg" .. threadNum)
    msgChan:push("isalive")
    msgChan:push(x)
    msgChan:push(y)

    -- блокирующий вызов, вешает программу
    --local state: boolean = love.thread.getChannel("request" .. threadNum):demand() as boolean

    if threadNum == curThreadNum then
        return isAlive(x, y)
    else
        local threadName = "request" .. threadNum
        print("request to", threadName)
        local chan = love.thread.getChannel(threadName)
        local state: boolean = chan:demand(requestThreadDemandTimeout) as boolean

        if not state then
            print("setup.popCommand")
            setup.popCommand()
            state = chan:demand(requestThreadDemandTimeout) as boolean
            print("state", state)
        end

        print(state)
        assert(state ~= nil, "no answer from " .. threadName .. " thread")
        return state

        --return true
    end
end

-- отослать клетку в другой поток через канал
local function moveCellToThread(cell: Cell, threadNum: number)
    print("moveCellToThread", threadNum)
    --local dump: string = serpent.dump(cell)
    local dump = serpent.dump(cell)
    local chan = love.thread.getChannel("msg" .. threadNum)
    chan:push("insertcell")
    chan:push(dump)
end

function actions.left(cell: Cell): boolean
    local res = false
    local pos = cell.pos
    pushPosition(cell)
    --print("cell", inspect(cell))
    if pos.x > 1 and not isAlive(pos.x - 1, pos.y) then
        pos.x = pos.x - 1
    --elseif pos.x <= 1 and not isAlive(gridSize, pos.y) then
    --print("schema", inspect(schema))
    elseif pos.x <= 1 and not isAliveNeighbours(gridSize, pos.y, schema.l) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        --local oldx, oldy = cell.pos.x, cell.pos.y
        pos.x = gridSize
        moveCellToThread(cell, schema.l)
        --getGrid()[oldx][oldy] = {}
        -- XXX клетка должна быть сразу уничтожена
        -- после возврата из функции
        --getGrid()[oldx][oldy].energy = 0
        res = true
    end
    return res
end

function actions.right(cell: Cell): boolean
    local res = false
    local pos = cell.pos
    pushPosition(cell)
    if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
        pos.x = pos.x + 1
    --elseif pos.x >= gridSize and not isAlive(1, pos.y) then
    elseif pos.x >= gridSize and not isAliveNeighbours(1, pos.y, schema.r) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        pos.x = 1
        moveCellToThread(cell, schema.r)
        res = true
    end
    return res
end

function actions.up(cell: Cell): boolean
    local res = false
    local pos = cell.pos
    pushPosition(cell)
    if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
        pos.y = pos.y - 1
    --elseif pos.y <= 1 and not isAlive(pos.x, gridSize) then
    elseif pos.y <= 1 and not isAliveNeighbours(pos.x, gridSize, schema.u) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        pos.y = gridSize
        moveCellToThread(cell, schema.u)
        res = true
    end
    return res
end

function actions.down(cell: Cell): boolean
    local res = false
    local pos = cell.pos
    pushPosition(cell)
    if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
        pos.y = pos.y + 1
    elseif pos.y >= gridSize and not isAliveNeighbours(pos.x, 1, schema.d) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        pos.y = 1
        moveCellToThread(cell, schema.d)
        res = true
    end
    return res
end

function actions.left2(cell: Cell): boolean
    local pos = cell.pos
    pushPosition(cell)
    if pos.x > 1 and not isAlive(pos.x - 1, pos.y) then
        pos.x = pos.x - 1
    elseif pos.x <= 1 and not isAlive(gridSize, pos.y) then
        pos.x = gridSize
    end
end

function actions.right2(cell: Cell): boolean
    local pos = cell.pos
    pushPosition(cell)
    if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
        pos.x = pos.x + 1
    elseif pos.x >= gridSize and not isAlive(1, pos.y) then
        pos.x = 1
    end
end

function actions.up2(cell: Cell): boolean
    local pos = cell.pos
    pushPosition(cell)
    if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
        pos.y = pos.y - 1
    elseif pos.y <= 1 and not isAlive(pos.x, gridSize) then
        pos.y = gridSize
    end
end

function actions.down2(cell: Cell): boolean
    local pos = cell.pos
    pushPosition(cell)
    if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
        pos.y = pos.y + 1
    elseif pos.y >= gridSize and not isAlive(pos.x, 1) then
        pos.y = 1
    end
end

-- непонятно куда выкладывать значения из стека.
-- либо другие функции должны напрямую работать со стеком или
-- должны быть регистры в виде переменных внутри клетки.
function actions.popmem_pos(cell: Cell): boolean
end

function actions.pushmem_pos(cell: Cell): boolean
    --table.insert(cell.mem, cell.pos.x)
    --table.insert(cell.mem, cell.pos.y)
end

local around: {{number}} = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},          {1, 0},
    {-1,  1}, {0,  1}, {1, 1},
}

local function incEat(cell: Cell)
    if not cell.eated then
        cell.eated = 0
    end
    cell.eated = cell.eated + 1
    allEated = allEated + 1
end

-- Проверяет на съедобность все клетки вокруг себя. Найдя съедобную - поедает
-- ее оставаясь на месте
function actions.eat8(cell: Cell): boolean
    local nx, ny = cell.pos.x, cell.pos.y
    for _, displacement in ipairs(around) do
        nx = nx + displacement[1]
        ny = ny + displacement[2]

        -- проверка на выход за границы поля
        if nx >= 1 and nx <= gridSize and
            ny >= 1 and ny <= gridSize then
            local grid = getGrid()
            local dish = grid[nx][ny]
            -- проверка на нахождение еды в определенной клетке и поедание
            if dish and dish.food then
                getGrid()[nx][ny].food = nil
                dish.energy = 0
                cell.energy = cell.energy + ENERGY
                incEat(cell)
                return
            end
        end
    end
end

-- аналогично eat8, но перемещается на место съеденной клетки.
function actions.eat8move(cell: Cell): boolean
    local pos = cell.pos
    local newt: Pos = copy(pos as {any: any}) as Pos
    for _, displacement in ipairs(around) do
        newt.x = newt.x + displacement[1]
        newt.y = newt.y + displacement[2]

        -- проверка на выход за границы поля
        if newt.x >= 1 and newt.x < gridSize and
            newt.y >= 1 and newt.y < gridSize then
            local dish = getGrid()[newt.x][newt.y]
            -- проверка на нахождение еды в определенной клетке и поедание
            --print(inspect(dish))
            if dish.food then
                --print("eat8move at", newt.x, newt.y)
                dish.food = nil
                dish.energy = 0
                cell.energy = cell.energy + ENERGY
                cell.pos.x = newt.x
                cell.pos.y = newt.y
                incEat(cell)
                return
            end
        end
    end
end

-- вызывает коллбэк вида function(x, y, value) для всех доступных соседей
-- клетки. x, y - целочисленные координаты клетки в решетке. value - значение
-- решетки по текущим координатам.
-- Если коллбэк функция возвращает false, то дальнейшие вызовы прерываются, 
-- управление возвращается.
-- FIXME поиск должен рандоминизировать начальное положение что-бы 
-- исключить влияние порядка обхода клеток.
global type NeighboursCallback = function(number, number, any): boolean

local function listNeighbours(x: number, y: number, cb: NeighboursCallback)
    for _, displacement in ipairs(around) do
        local nx, ny = x + displacement[1], y + displacement[2]
        if nx >= 1 and nx < gridSize and ny >= 1 and ny < gridSize then
            if not cb(nx, ny, getGrid()[nx][ny]) then
                break
            end
        end
    end
end

-- return code, not cell
local function mixCode(cell1: Cell, cell2: Cell): {string}
    local rnd = math.random()
    local first, second: Cell, Cell
    if rnd > 0.5 then
        first, second = cell1, cell2 
    else
        first, second = cell2, cell1
    end
    local newcode = {}
    local i = 1
    local pushed: boolean

    repeat
        pushed = false
        if i <= #cell1.code then
            table.insert(newcode, first.code[i])
            pushed = true
        end
        if i <= #cell2.code then
            table.insert(newcode, second.code[i])
            pushed = true
        end
        i = i + 1
    until not pushed

    return newcode
end

local function test_mixCode()
    math.randomseed(love.timer.getTime())
    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat", "eat"}})))

    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat"}})))

    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat", "down", "down", "down"}})))
end
--test_mixCode()

-- возвращает true если найдена пустая клетка, {x, y} координаты.
-- иначе false
-- XXX not tested anymore
local function findFreePos(x: number, y: number): boolean, Pos
    local pos: Pos = {}
    listNeighbours(x, y, function(xp: number, yp: number, value: Cell): boolean
        if (not value.energy) and (not value.food) then
            pos.x = xp
            pos.y = yp
            return true
        end
        return false
    end)
    return true, pos
end

-- если достаточно энергии(>0), то клетка
function actions.cross(cell: Cell): boolean
    --[[
    if cell.energy > 0 then
        cell.wantdivide = true
        listNeighbours(cell.pos.x, cell.pos.y, function(x: number, y: number, value: Cell): boolean
            if value.wantdivide then
                local found, pos = findFreePos(cell.pos.x, cell.pos.y)
                if found then
                    local t = {
                        pos = {x = pos.x, y = pos.y},
                        code = mixCode(cell, getGrid()[x][y])
                    }
                    print("new cell!")
                    initCell(t)
                end
            end
            return false
        end)
    end
    --]]
    return false
end

local function init(t: CellActionsInit)
    --assert(type(getGridFunc) == "function")
    curThreadNum = t.threadNum
    getGrid = t.getGrid
    gridSize = t.gridSize
    initCell = t.initCell
    schema = t.schema
    ENERGY = t.foodenergy
    setup = shallowCopy(t)

    print("t", inspect(t))
    allEated = 0
end

return {
    actions = actions,
    init = init,
    getAllEated = function(): number
        return allEated
    end,
}

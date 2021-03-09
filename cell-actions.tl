require "types"
require "mtschemes"
require "love"
require "common"

local marshal = require 'marshal'
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

local maxSavedPositions = 64

local writelog: function(...: string)

-- записать текущее положение клетки в ее табличку передвижений
local function pushPosition(cell: Cell)
    if not cell.moves then
        cell.moves = {}
    end
    local moves = cell.moves
    if #moves >= 2 then
        local lastX, lastY = moves[#moves - 1], cell.moves[#moves]
        if lastX ~= cell.pos.x and lastY ~= cell.pos.y then
            if #moves > maxSavedPositions then
                table.remove(moves, 1)
                table.remove(moves, 2)
            end
            table.insert(moves, cell.pos.x)
            table.insert(moves, cell.pos.y)
        end
    else
        table.insert(cell.moves, cell.pos.x)
        table.insert(cell.moves, cell.pos.y)
    end
end

local requestThreadDemandTimeout = 0.02

-- проверяет жива ли клетка в определенном потоке
local function isAliveNeighbours(x: number, y: number, threadNum: number): boolean
    if not threadNum then
        error("no threadNum")
    end
    writelog(string.format("isAliveNeighbours(%d, %d, %d)", x, y, threadNum))

    --print("threadNum", threadNum)

    local msgChan = love.thread.getChannel("msg" .. threadNum)
    msgChan:push("isalive")
    local aliveChan = love.thread.getChannel('alive' .. threadNum)
    aliveChan:push(x)
    aliveChan:push(y)

    -- блокирующий вызов, вешает программу
    --local state: boolean = love.thread.getChannel("request" .. threadNum):demand() as boolean

    if threadNum == curThreadNum then
        return isAlive(x, y)
    else
        --print("FUCKFUCK")
        local threadName = "cellrequest" .. threadNum

        writelog("request to", threadName)

        local chan = love.thread.getChannel(threadName)
        local state: boolean = chan:demand(requestThreadDemandTimeout) as boolean

        --if not state then
        local i = 0
        local limit = 500
        while not state do
            if i >= limit then
                error("Cycles limit reached.")
            end
            writelog("setup.popCommand")

            setup.popCommand()
            love.timer.sleep(0.01)
            state = chan:demand(requestThreadDemandTimeout) as boolean
            i = i + 1
        end

        writelog("state ", tostring(state))

        assert(state ~= nil, "no answer from " .. threadName .. " thread")
        return state

        --return true
    end
end

-- отослать клетку в другой поток через канал
local function moveCellToThread(cell: Cell, threadNum: number)
    --print("moveCellToThread", threadNum)

    --local dump: string = serpent.dump(cell)
    local dump = serpent.dump(cell)
    local chan = love.thread.getChannel("msg" .. threadNum)
    print('moveCellToThread dump', inspect(dump))
    local bchan = love.thread.getChannel('busy' .. threadNum)
    local state = bchan:peek() as string
    -- блокировка в ожидании
    while state do
        state = bchan:peek() as string
    end
    bchan:push('b')
    -- пишу из рабочего
    chan:push("insertcell")
    --<<-- еще что-то вклинивается
    local cellsChan = love.thread.getChannel('cells' .. threadNum)
    print('cellsChan', cellsChan)
    -- XXX нужна ли здесь очистка?
    --cellsChan:clear()
    cellsChan:push(dump)
    bchan:clear()
end

function actions.left(cell: Cell): boolean
    local res = true
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
        --pos.x = gridSize
        cell.pos.x = gridSize
        moveCellToThread(cell, schema.l)
        --getGrid()[oldx][oldy] = {}
        -- XXX клетка должна быть сразу уничтожена
        -- после возврата из функции
        --getGrid()[oldx][oldy].energy = 0
        res = false
    end
    return res
end

function actions.right(cell: Cell): boolean
    local res = true
    local pos = cell.pos
    pushPosition(cell)
    if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
        pos.x = pos.x + 1
    --elseif pos.x >= gridSize and not isAlive(1, pos.y) then
    elseif pos.x >= gridSize and not isAliveNeighbours(1, pos.y, schema.r) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        cell.pos.x = 1
        moveCellToThread(cell, schema.r)
        res = false
    end
    return res
end

function actions.up(cell: Cell): boolean
    local res = true
    local pos = cell.pos
    pushPosition(cell)

    ----------------------------------------
    --[[
    print('actions.up()')
    local node: DrawNode = {}
    node.x = cell.pos.x
    node.y = cell.pos.y
    node.color = {1, 1, 1, 1}
    print('setup.channels', inspect(setup.channels))
    for _ = 1, 100 do 
        --do
        local ok, errmsg: boolean, string = pcall(function()
            setup.channels.drawlist_fn:push(node)
        end)
        if not ok then
            print('error in actions.cross()', errmsg)
        end
    end
    --]]
    ----------------------------------------

    if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
        pos.y = pos.y - 1
    --elseif pos.y <= 1 and not isAlive(pos.x, gridSize) then
    elseif pos.y <= 1 and not isAliveNeighbours(pos.x, gridSize, schema.u) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        cell.pos.y = gridSize
        moveCellToThread(cell, schema.u)
        res = false
    end
    return res
end

function actions.down(cell: Cell): boolean
    local res = true
    local pos = cell.pos
    pushPosition(cell)
    if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
        pos.y = pos.y + 1
    elseif pos.y >= gridSize and not isAliveNeighbours(pos.x, 1, schema.d) then
        --getGrid()[cell.pos.x][cell.pos.y].energy = 0
        cell.pos.y = 1
        moveCellToThread(cell, schema.d)
        res = false
    end
    return res
end

--[[
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
--]]

--[[

-- непонятно куда выкладывать значения из стека.
-- либо другие функции должны напрямую работать со стеком или
-- должны быть регистры в виде переменных внутри клетки.
function actions.popmem_pos(_: Cell): boolean
end

function actions.pushmem_pos(_: Cell): boolean
    --table.insert(cell.mem, cell.pos.x)
    --table.insert(cell.mem, cell.pos.y)
end

--]]

local around4: {{number}} = {
              {0, -1},
    {-1,  0},          {1, 0},
              {0,  1},
}

local around8: {{number}} = {
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
    local res = true
    local nx, ny = cell.pos.x, cell.pos.y
    for _, displacement in ipairs(around8) do
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
                return res
            end
        end
    end
    return res
end

-- аналогично eat8, но перемещается на место съеденной клетки.
function actions.eat8move(cell: Cell): boolean
    local res = true
    local pos = cell.pos
    local newt: Pos = shallowCopy(pos as {any: any}) as Pos
    for _, displacement in ipairs(around8) do
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
                return res
            end
        end
    end
    return res
end

global type NeighboursCallback = function(number, number, Cell): boolean

-- FIXME поиск должен рандоминизировать начальное положение что-бы 
-- исключить влияние порядка обхода клеток.

-- вызывает коллбэк вида function(x, y, value) для всех доступных соседей
-- клетки. x, y - целочисленные координаты клетки в решетке. value - значение
-- решетки по текущим координатам.
-- Если коллбэк функция возвращает false, то дальнейшие вызовы прерываются, 
-- управление возвращается.
--
local function listNeighbours8(x: number, y: number, cb: NeighboursCallback)
    for _, displacement in ipairs(around8) do
        local nx, ny = x + displacement[1], y + displacement[2]
        if nx >= 1 and nx <= gridSize and ny >= 1 and ny <= gridSize then
            if cb(nx, ny, getGrid()[nx][ny]) == false then
                break
            end
        end
    end
end

local function listNeighbours4(x: number, y: number, cb: NeighboursCallback)
    for _, displacement in ipairs(around4) do
        local nx, ny = x + displacement[1], y + displacement[2]
        if nx >= 1 and nx <= gridSize and ny >= 1 and ny <= gridSize then
            if cb(nx, ny, getGrid()[nx][ny]) == false then
                break
            end
        end
    end
end
--]]

-- return code, not cell
--[[
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
--]]

--[[
local function test_mixCode()
    math.randomseed(love.timer.getTime())
    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat", "eat"}})))

    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat"}})))

    print("mixCode", inspect(mixCode({code={"left", "right", "up"}},
    {code={"eat", "eat", "down", "down", "down"}})))
end
--]]
--test_mixCode()

local function findFreePos4(x: number, y: number): boolean, Pos
    local pos: Pos = {}
    listNeighbours4(x, y,
    function(xp: number, yp: number, value: Cell): boolean
        if (not value.energy) and (not value.food) then
            pos.x = xp
            pos.y = yp
            return false
        end
        return true
    end)
    return pos.x ~= nil and pos.y ~= nil, pos
end
--]]

-- возвращает true и координаты если найдена пустая клетка вокруг данной 
-- иначе false
-- XXX возвращает true и пустую позицию
local function findFreePos8(x: number, y: number): boolean, Pos
    local pos: Pos = {}
    listNeighbours8(x, y,
    function(xp: number, yp: number, value: Cell): boolean
        if (not value.energy) and (not value.food) then
            pos.x = xp
            pos.y = yp
            return false
        end
        return true
    end)
    return pos.x ~= nil and pos.y ~= nil, pos
end
--]]

function actions.wantdivide(cell: Cell): boolean
    local res = true
    if cell.energy > 0 then

        -- если счетчик уже установлен, то вернуть управление
        if cell.wantdivide and cell.wantdivide == 0 then
            return res
        end

        -- тянуть жребий
        if setup.rng:random(1, 1000) == 1 then
            cell.wantdivide = setup.rng:random(1, 10)
            cell.color = {1, 0, 0}
        end
    end
    return res
end

-- деление клетки
function actions.cross(cell: Cell): boolean
    local res = true
    -- эффективное преобразование композиции булевых выражений 
    if cell.wantdivide and cell.wantdivide == 0 and cell.energy and cell.energy > 0 then
        --[[
        --]]
        print('actions.cross()')
        local node: DrawNode = {}
        node.x = cell.pos.x
        node.y = cell.pos.y
        node.color = {1, 1, 1, 1}
        print('setup.channels', inspect(setup.channels))
        for i = 1, 100 do 
        --do
            local ok, errmsg: boolean, string = pcall(function()
                setup.channels.drawlist_fn:push(node)
            end)
            if not ok then
                print('error in actions.cross()', errmsg)
            end
        end
        --]]

        --[[
        -- найти соседей клетки
        listNeighbours4(
            cell.pos.x, 
            cell.pos.y, 
            function(_: number, _: number, other: Cell): boolean
                -- сосед тоже хочет делиться
                if other.wantdivide and 
                    other.wantdivide == 0 and 
                    other.energy > 0 then
                    print("cell.pos", cell.pos.x, cell.pos.y)
                    
                    setup.setStepMode()

                    -- здесь переход в шаговый режим, но должна быть анимация поиска
                    -- свободных клеток вокруг данной. Как вариант - создать дополнительный
                    -- канал для рисования и посылать в него номера ячеек?

                    -- если сделать графическую анимацию плавной, то будет завешиваться
                    -- обработка все остальных клеток поля

                    -- поиск свободной ячейки для новой клетки
                    local found, pos = findFreePos4(cell.pos.x, cell.pos.y)
                    if found then
                        local t = {
                            pos = {x = pos.x, y = pos.y},
                            --code = mixCode(cell, getGrid()[x][y])
                            code = {},
                            color = {0.5, 0.5, 0.5}
                        }
                        print(pos.x, pos.y)
                        print(string.format("new cell at (%d, %d)", pos.x, pos.y))
                        initCell(t)
                        setup.setStepMode()
                        return false
                    end
                end
                return true
            end
        )
        --]]
    end
    --]]
    return res
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

    writelog = t.writelog

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

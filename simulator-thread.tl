require "love.filesystem"
require "log"
require "love.timer"
require "mtschemes"
require "types"
require "love"
require "love.math"
require 'cell'
require 'log'

-- иногда возникает ошибка загрузки модулей при повторном старте
-- возможно не завершаются потоки?
--love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")

require("mobdebug").start()

local threadNum: integer = ... as integer
printLog("thread", threadNum, "is running")

local inspect = require "inspect"
local serpent = require "serpent"
--local maxDataChannelCount = 10
--local randseed: number = love.timer.getTime()
local secondDelay = 1
local rng: love.math.RandomGenerator

local istate: CommonSetup

-- массив всех клеток
local cells: Cells = {}
-- массив массивов [x][y] с клетками по индексам
-- TODO Переработать интерфейс взаимодействия с сеткой на использования класса
-- Grid на основе C-массива 2Д
local grid: Grid = {}
-- размер сетки
local gridSize: integer
-- сколько клеток создавать корутиной в начальном впрыске
local cellsNum: integer
-- текущая итерация
local iter: integer = 0
-- таблица общей статистики
local stat: Statistic = {}
-- список еды
local meals: {Cell} = {}
-- флаг остановки потока 
local stop = false 
-- схема многопоточности 
local schema: MtSchema
-- кортеж координат для сдвига площадки рисования одного потока
local drawCoefficients: {integer, integer}
-- шагнуть при шаговом режиме
local doStep = false
-- шаговый или продолжительный режим
local checkStep = false
-- команды таблички управления нитью
local commands: ThreadCommandsStore = {}
-- номер последней итерации на которой создавались клетки
local lastEmitIter = 0
-- через сколько итераций спустя создавать клетку
local emitInvSpeed = 100.

local logName = string.format("thread%d.txt", threadNum)
printLog("logName", logName)

--[[
channels.cellrequest:push() <=> channels[1].cellrequest
две таблицы
--]]
local channels: Channels = initChannels(threadNum)

-- строчка: имя
for k, v in ipairs(ChannelsTypes) do
    printLog("v", v, 'k', k)
end
printLog("channels", inspect(channels))

local cellActions = require "cell-actions"

-- расчет количества итераций в секунду
local timestamp: number
local stepsCount = 0
local stepsPerSecond = 0

-- флажок устанавливается когда корутина эксперимента закончилась
-- нет смысла в этом флаге если корутина завершилась ошибочно
-- TODO удалить за ненадобностью?
local free = false

local removed: {Cell} = {}
local experimentCoro: thread

-- заполнить решетку пустыми значениями. В качестве значений используются
-- пустые таблицы {}
function getFalseGrid(): Grid
  local res = {}
  for _ = 1, gridSize do
    local t = {}
    for _ = 1, gridSize do
      t[#t + 1] = {}
    end
    res[#res + 1] = t
  end
  return res
end

function updateGrid()
  for _, v in ipairs(cells) do
    grid[v.pos.x][v.pos.y] = v
  end
  for _, v in ipairs(meals) do
    grid[v.pos.x][v.pos.y] = v
  end
end

-- не работает нормально. Нужно отсылал с некоторой периодичностью в виде 
-- сообщений в основную нить
function gatherStatistic(cells: {Cell})
    local maxEnergy = 0.0
    --local minEnergy = istate.initialEnergy[2]
    local minEnergy = 100000000.0
    local sumEnergy = 0.0
    local square = gridSize * gridSize
    local i = 0

    -- зачем?
    for _, v in ipairs(cells) do
        if v.energy and v.energy > 0 then
            i = i + 1
        end
        if v.energy > maxEnergy then
            maxEnergy = v.energy
        end
        if v.energy < minEnergy then
            minEnergy = v.energy
        end
        sumEnergy = sumEnergy + v.energy
    end

    --local num = #cells > 0 and #cells or 1
    if sumEnergy == 0 then
        sumEnergy = 1
    end
    --printLog('square, i', square, i)

    local midEnergy: number
    if #cells == 0 then
        midEnergy = 0
        minEnergy = 0
    else
        midEnergy = sumEnergy / #cells
    end

    stat.allEated = cellActions.getAllEated()
    stat.maxEnergy = maxEnergy
    stat.minEnergy = minEnergy
    stat.midEnergy = midEnergy
    stat.cells = #cells
    stat.meals = #meals
    stat.percentAreaFilled = i / square
    stat.iterations = iter
end


function emitFoodInRandomPoint(): boolean, Cell
    --XXX проверить - может ли x достигать gridSize
    local x = math.floor(rng:random(1, gridSize))
    local y = math.floor(rng:random(1, gridSize))
    local t = grid[x][y]
    -- если клетка пустая
    if not t.energy then
        local self = {
            food = true,
            pos = {x = x, y = y}
        }
        table.insert(meals, self)
        grid[x][y] = self
        return true, grid[x][y]
    else
        return false, grid[x][y]
    end
end

local foodGenerationSpeed = 0.1
local accum = 0.

--[[
Сделать возможность генерации пищи не на каждом шагу симуляции
math.log()
--]]
function emitFood(_: number)
    if istate.nofood then
        return
        --coroutine.yield()
    end

    while true do
        accum = accum + foodGenerationSpeed

        for _ = 0, math.floor(math.log(iter)) do
            --print(i, accum)

            emitFoodInRandomPoint()

            --local emited, _ = emitFoodInRandomPoint()
            --if not emited then
                ---- здесь исследовать причины смерти яцейки
                ----print("not emited gridcell", inspect(gridcell))
            --end
        end

        coroutine.yield()
    end
end

--[[ XXX Выключено из-за проблем загрузкм модулей
function saveDeadCellsLog(cells: {Cells})
  local filename = string.format("cells%d.gzip", threadNum)
  local file = io.open(filename, "w")
  for _, cell in ipairs(cells) do
    local celldump: string = serpent.dump(cell)
    local compressedcellstr = love.data.compress("string", "gzip", celldump) as string
    if not compressedcellstr then
      error("Not compressed cell")
    end
    local len: number = compressedcellstr:len()
    -- записываю 4 байта длины сжатой строки
    file:write(struct.pack("<d", len))
    file:write(compressedcellstr)
  end
  file:close()
end
--]]

function updateCells(cells: {Cell}): {Cell}
    local alive = {}
    for _, cell in ipairs(cells) do
        local isalive = cell:update()
        if isalive then
            table.insert(alive, cell)
        else
            table.insert(removed, cell)
        end
    end
    return alive
end

--local function initCellOneCommandCode(command: string, steps: number): Cell
    --local cell = initCell()
    --print("cell.energy", cell.energy)
    --cell.code = {}
    --for i = 1, steps do
        --table.insert(cell.code, command)
    --end
    ----print("cell.code", inspect(cell.code))
    --return cell
--end

--[[ XXX Not compiled
local function cloneCell(cell: Cell, newx: number, newy: number): Cell
    if not isAlive(newx, newy) then
        local new: Cell = {}
        for k, v in pairs(cell as {any: any}) do
            if type(v) ~= "table" then
                --new[k] = v
                new as {any: any}[k] = v
            else
                new as {any: any}[k] = {}
                for k1, v1 in pairs(v as table) do
                    --new as {any: {any}}[k][k1] = v1
                    new as {any: any}[k][k1 as string] = v1
                end
            end
        end
        new.pos.x, new.pos.y = newx, newy
        printLog("cloned cell")
        table.insert(cells, new)
        return new
    else
        printLog("nothing in clone")
        return nil
    end
end
--]]

local function genPosition(): number, number
    local cx = 0.
    local cy = 0.
    local i, limit = 0, 1000
    while true do
        cx = rng:random(1, istate.gridSize)
        cy = rng:random(1, istate.gridSize)
        local len = dist(
            cx, cy, 
            istate.spreadPoint.x, istate.spreadPoint.y
        )
        local ex1 = len < istate.spreadRad
        local ex2 = grid[math.floor(cx)][math.floor(cy)].food == nil
        local ex3 = grid[math.floor(cx)][math.floor(cy)].energy == nil;
        if ex1 and ex2 and ex3 then
            return cx, cy
        end
        i = i + 1
        if i > limit then
            break
        end
    end
    error("Could not generate position")
    return 0, 0
end

--[[
Пока только линейный рост колонии
--]]
local function emitCell(_: number)
    --[[
    printLog("cellsNum", cellsNum)
    -- не создается нужное количество клеток
    while true do
        --for i = 1, cellsNum do
        if cellId >= cellsNum then
            break
        end
        if iter - lastEmitIter >= emitInvSpeed then
            printLog("iter", iter)
            --local cx, cy = genPosition()
            local cx = love.rng:random(1, istate.gridSize)
            local cy = love.rng:random(1, istate.gridSize)
            initCell({ 
                pos = { x = cx, y = cy }
            })
            lastEmitIter = iter
        end
        iter = coroutine.yield() as number
    end
    --]]

    --printLog('istate.cellsNum', istate.cellsNum)

    if istate.emitFlags == 'normal' then
        for _ = 1, istate.cellsNum do
            local cx, cy = genPosition()
            --local cx = rng:random(1, istate.gridSize)
            --local cy = rng:random(1, istate.gridSize)
            --printLog('cx, cy', cx, cy)
            table.insert(
                cells, 
                Cell.new({ pos = { x = cx, y = cy } })
            )
            coroutine.yield()
        end
    elseif istate.emitFlags == 'directions_only' then
        local cx, cy = genPosition()
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = cx, y = cy }, 
                    code = {'left',}
                }
            )
        )
        cx, cy = genPosition()
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = cx, y = cy }, 
                    code = {'right',}
                }
            )
        )
        cx, cy = genPosition()
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = cx, y = cy }, 
                    code = {'up',}
                }
            )
        )
        cx, cy = genPosition()
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = cx, y = cy }, 
                    code = {'down',}
                }
            )
        )
    elseif istate.emitFlags == 'divide_only' then
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = 20, y = 20 }, 
                    wantdivide = 0,
                    code = { 'wantdivide', 'cross',}
                }
            )
        )
        table.insert(
            cells, 
            Cell.new(
                { 
                    pos = { x = 21, y = 20 }, 
                    wantdivide = 0,
                    code = { 'wantdivide', 'cross',}
                }
            )
        )
    end

    coroutine.yield()
end

local function updateMeal(meal: {Cell}): {Cell}
  local alive = {}
  for _, dish in ipairs(meal) do
    if dish.food == true then
      table.insert(alive, dish)
    end
  end
  return alive
end

local function experiment()
    local emitCellCoro: thread = coroutine.create(emitCell)
    local emitFoodCoro: thread = coroutine.create(emitFood)

    iter = 0
    lastEmitIter = 0

    grid = getFalseGrid()
    updateGrid()

    stat = {
        allEated = 0,
        maxEnergy = 0,
        minEnergy = 0,
        midEnergy = 0,
        cells = 0,
        iterations = 0,
        meals = 0,
        born = 0,
        died = 0,
        percentAreaFilled = 0,
    }

    coroutine.yield()
    local ok, errmsg = coroutine.resume(emitCellCoro, iter) as (boolean, string)
    if not ok then
        error(errmsg)
        stop = true
    end
    printLog("#Experiment started with", #cells)

    -- если нет живых клеток, то вставать на паузу, но сохранять возможность
    -- вставки клеток через сообщение insertcell
    while true do

        local emitok, msg: boolean, string = pcall(function()
            -- создание клеток
            if emitCellCoro and not coroutine.resume(emitCellCoro, iter) then
                emitCellCoro = nil
            end
            -- создание питания
            if emitFoodCoro and not coroutine.resume(emitFoodCoro, iter) then
                emitFoodCoro = nil
            end
        end)
        if not emitok then
            printLog('emit pcall error ' .. msg)
        end

        -- проход по списку клеток и вызов их программ. уничтожение некоторых клеток
        cells = updateCells(cells)

        -- проход по списку питания и проверка на съеденность.
        meals = updateMeal(meals)

        -- сброс решетки
        grid = getFalseGrid()

        -- обновление решетки по списку живых клеток и списку еды
        updateGrid()

        if #cells == 0 then
            channels.colonystatus:push("nocellsincolony")
        end

        -- обновить статистику за такт
        --stat = gatherStatistic(cells)
        gatherStatistic(cells)

        --stat.isalive = #cells ~= 0

        -- слишком часто идет отправка.
        channels.stat:push(stat)

        iter = iter + 1
        --printLog('iter', iter)

        coroutine.yield()
    end

    printLog("there is no cells in simulation")
    -- здесь нить должна уснуть в цикле ??

--    saveDeadCellsLog(removed)
end

local experimentErrorPrinted = false

-- для интерфейса в другой модуль
local function getGrid(): Grid
  return grid
end

local function pushDrawList()
    local drawlist: {DrawNode} = {}
    for _, v in ipairs(cells) do
        table.insert(drawlist, { 
            x = v.pos.x + gridSize * drawCoefficients[1],
            y = v.pos.y + gridSize * drawCoefficients[2],
        })
        if v.color then
            drawlist[#drawlist].color = shallowCopy(v.color)
        end
    end
    for _, v in ipairs(meals) do
        table.insert(drawlist, { 
            x = v.pos.x + gridSize * drawCoefficients[1],
            y = v.pos.y + gridSize * drawCoefficients[2], 
            food = true
        })
    end
    channels.drawlist:push(drawlist)
end

function commands.stop()
    printLog("stop command, break main cycle")
    stop = true
end

function commands.getobject()
    local x, y: number, number
    x = channels.object_w:pop() as integer
    y = channels.object_w:pop() as integer
    local ok, _: boolean, string = pcall(function()
        if grid then
            local cell = grid[math.floor(x)][math.floor(y)]
            if cell then
                local dump = serpent.dump(cell)
                channels.object_r:push(dump)
            end
        end
    end)
    if not ok then
        -- попытка восстановиться от ошибки очистив очередь сообщений
        --error("Error in getobject operation " .. errmsg)
    end
end

function commands.step()
    checkStep = true
    doStep = true

    -- сброс таймера посчета итераций в секунду
    stepsPerSecond = stepsCount
    stepsCount = 0
end

function commands.continuos()
    printLog('commands.continuos')
    checkStep = false
end

function commands.isalive()
    local x, y = channels.alive:pop() as integer, channels.alive:pop() as integer  
    if type(x) ~= 'number' or type(y) ~= 'number' then
        assert(string.format("x, y " ..  x .. " " .. y .. " threadNum " .. threadNum))
    end

    local ok, errmsg: boolean, string = pcall(function()
        if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
            local cell = grid[math.floor(x)][math.floor(y)]
            --printLog(string.format("cell %s", inspect(cell)))
            local state = false
            if cell.energy and cell.energy > 0 then
                state = true
            end
            channels.cellrequest:push(state)
        end
    end)

    if not ok then
        error("isalive error: " ..errmsg)
    end
end

-- метод для пересылки клеток между нитями
function commands.insertcell()
    local msg = channels.cells:pop() as string

    if msg then
        local newcellfun, err = load(msg)
        if (not newcellfun) and err then
            error(string.format("insertcell '%s', msg = '%s'", err, msg))
        end
        local newcell: Cell = newcellfun() as Cell
        newcell = setmetatable(newcell, { __index = Cell })
        newcell.id = istate.cellId
        istate.cellId = istate.cellId + 1
        -- нормально, что grid не устанавливается и синхронизация пройдет только на
        -- следущем шаге?
        table.insert(cells, newcell)
    end
end

function commands.readstate()
    local state: string = channels.state:demand() as string
    local ok, store: boolean, any = serpent.load(state)
    printLog('commands.readstate()', inspect(store))
    if not ok then
        printLog("commands.readstate() could'not load state")
        return
    end

    cells = (store as {string:string}).cells as Cells
    meals = (store as {string:string}).meals as {Cell}
    schema = (store as {string:string}).schema as MtSchema
    istate = (store as {string:string}).istate as CommonSetup
    istate.rng = love.math.newRandomGenerator()
    istate.rng:setState(istate.rngState)
end

function commands.writestate()
    printLog('commands.writestate')

    local store = {
        cells = cells,
        meals = meals,
        schema = schema,
        istate = istate,
    }

    local data = serpent.dump(store, {fatal = true})
    love.filesystem.write('data.txt', data)
    channels.state:push(data)
end

local function clearLogs()
    love.filesystem.write(string.format('commands-thread-%d.log.txt', threadNum), "")
end

local function popCommand()
    local cmd: ThreadCommands
    repeat
        cmd = channels.msg:pop() as ThreadCommands
        local logstr = string.format('iter %d msg %s\n', iter, cmd)
        love.filesystem.append(string.format('commands-thread-%d.log.txt', threadNum), logstr)
        if cmd then
            local command = commands[cmd]
            if command then
                command()
            else
                -- TODO Восстановление после ошибки
                logerror(string.format("Unknown command '%s'", cmd))
                --msgChan:clear()
            end
        end
    until not cmd
end

local function doSetup()

    printLog('\\\\\\\\\\\\\\\\')
    for k, v in pairs(channels) do
        printLog(k, v)
    end
    printLog('\\\\\\\\\\\\\\\\')

    istate = channels.setup:pop() as CommonSetup
    if not istate then
        error("No setup for thread " .. threadNum)
    end
    -- XXX получать состояние ГПСЧ из istate
    rng = love.math.newRandomGenerator()
    rng:setState(istate.rngState)
    istate.rng = rng

    if istate.mode == "step" then
        commands.step()
    elseif istate.mode == "continuos" then
        commands.continuos()
    end

    printLog("thread", threadNum)
    printLog("istate", inspect(istate))

    gridSize = istate.gridSize
    cellsNum = istate.cellsNum
    emitInvSpeed = istate.emitInvSpeed

    local sschema: string = channels.setup:pop() as string

    local schemafun, err = load(sschema)
    if err then
        error("Could'not get schema for thread")
    end

    local schemaRestored: MtSchema = schemafun() as MtSchema
    printLog("schemaRestored", inspect(schemaRestored))
    schema = shallowCopy(schemaRestored)

    drawCoefficients = shallowCopy(schemaRestored.draw)

    printLog("schema", inspect(schema))
    printLog("drawCoefficients", inspect(drawCoefficients))

    experimentCoro = coroutine.create(experiment)

    -- первый запуск корутины, прогревочный 
    coroutine.resume(experimentCoro)

    cellActions.init({
        threadNum = threadNum,
        getGrid = getGrid,
        gridSize = gridSize,
        initCell = Cell.new,
        schema = schema,
        foodenergy = istate.foodenergy,
        popCommand = popCommand,
        writelog = printLog,
        rng = istate.rng,
        -- XXX работает только для текущей нити
        setStepMode = commands.step,
        channels = channels,
    })

    -- установка ссылки на таблицу действий - язык клетки.
    istate.cellActions = cellActions.actions
    cellInitInternal(istate, stat)
end

local function step()
    -- счетчик итераций за секунду.
    local newtimestamp = love.timer.getTime()
    if newtimestamp - timestamp >= secondDelay then
        stepsPerSecond = stepsCount
        stepsCount = 0
        timestamp = newtimestamp
    end

    local ok, errmsg = coroutine.resume(experimentCoro)
    stepsCount = stepsCount + 1

    -- XXX корутина в принципе не должна завершаться, дальше только падать и 
    -- писать отчет об ошибке
    if not ok then
        experimentErrorPrinted = true
        free = true
        error(string.format("coroutine error %s", errmsg))
    end
end

local function main()
    timestamp = love.timer.getTime()
    local __step_done = false
    while not stop do
        __step_done = false
        popCommand()
        if not free then
            if checkStep then
                if doStep then
                    step()
                    __step_done = true
                end
                love.timer.sleep(0.001)
            else
                step()
                __step_done = true
            end

            channels.drawlist_fn:performAtomic(function(channel: love.thread.Channel)
                for _ = 1, 100 do
                    local node: DrawNode = {}
                    node.x = math.floor(rng:random(1, 100))
                    node.y = math.floor(rng:random(1, 100))
                    node.color = {0.5, 0.7, 0.2}
                    channel:push(node)
                end
            end)

            pushDrawList()
            doStep = false
        else
            love.timer.sleep(0.001)
        end
    end
end

clearLogs()
doSetup()
main()

channels.isstopped:push(true)

printLog("thread", threadNum, "done")

require "love.filesystem"
require "log"
require "love.timer"
require "mtschemes"
require "types"
require "love"
-- иногда возникает ошибка загрузки модулей при повторном старте
-- возможно не завершаются потоки?
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")

require("mobdebug").start()

local threadNum: number = ... as number
print("thread", threadNum, "is running")

require 'cell'

local inspect = require "inspect"
local serpent = require "serpent"
local struct = require "struct"
local maxDataChannelCount = 10
local randseed: number = love.timer.getTime()

local rng = love.math.newRandomGenerator(randseed)

local istate: CommonSetup

-- массив всех клеток
local cells: Cells = {}
-- массив массивов [x][y] с клетками по индексам
-- TODO Переработать интерфейс взаимодействия с сеткой на использования класса
-- Grid на основе C-массива 2Д
local grid: Grid = {}
-- размер сетки
local gridSize: number
-- длина кода генерируемого новой клетке
local codeLen: number
-- сколько клеток создавать корутиной в начальном впрыске
local cellsNum: number
-- текущая итерация
local iter: number = 0
-- таблица общей статистики
local stat: Statistic = {}
-- список еды
local meals: {Cell} = {}
-- флаг остановки потока 
local stop = false 
-- схема многопоточности 
local schema: MtSchema
-- кортеж координат для сдвига площадки рисования одного потока
local drawCoefficients: {number, number}
-- шагнуть при шаговом режиме
local doStep = false
-- шаговый или продолжительный режим
local checkStep = false
-- команды таблички управления нитью
local commands: ThreadCommandsStore = {}
-- номер последней итерации на которой создавались клетки
local lastEmitIter = 0
-- через сколько итераций спустя создавать клетку
local emitInvSpeed = 100

local logName = string.format("thread%d.txt", threadNum)
print("logName", logName)

local ChannelsTypes: {string} = {
    -- запрос клетки
    "cellrequest", 
    -- получить графику для рисования клетки
    "drawlist", 
    -- прием сообщений с параметрами
    "msg", 
    -- получение объекта по координатам
    "object",
    -- готовность клетки?
    "ready",
    -- запрос?
    "request",
    -- вернуть сохраненное состояние
    "state",
}

local function initChannels(): Channels
    print(string.format("--- Thread %d initialize channels. ---", threadNum))
    local result: Channels = {}
    for _, v in ipairs(ChannelsTypes as {string}) do
        local name = v .. tostring(threadNum)
        print("get", name)
        result[v] = love.thread.getChannel(name)
    end
    print("--- ---")
    return result
end

local channels: Channels = initChannels()
local cellActions = require "cell-actions"

-- расчет количества итераций в секунду
local timestamp: number
local stepsCount = 0
local stepsPerSecond = 0

-- флажок устанавливается когда корутина эксперимента закончилась
-- нет смысла в этом флаге если корутина завершилась ошибочно
local free = false

local function getCodeValues(): {string}
  local codeValues = {}
  -- FIXME Сделал странное преобразование типов
  for k, _ in pairs(cellActions.actions as {string:string}) do
    
    -- XXX
    --if k == "left" then k = "left2"
    --elseif k == "right" then k = "right2"
    --elseif k == "up" then k = "up2"
    --elseif k == "down" then k = "down2"
    --end

    table.insert(codeValues, k)
  end
  return codeValues
end

local codeValues = getCodeValues()
print("codeValues", inspect(codeValues))

--local actions: CellActions
local removed: {Cell} = {}
local experimentCoro: thread

-- генератор кода
function genCode(): {string}
  local code = {}
  local len = #codeValues
  for i = 1, codeLen do
    table.insert(code, codeValues[rng:random(1, len)])
  end
  return code
end

-- заполнить решетку пустыми значениями. В качестве значений используются
-- пустые таблицы {}
function getFalseGrid(): Grid
  local res = {}
  for i = 1, gridSize do
    local t = {}
    for j = 1, gridSize do
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
function gatherStatistic(cells: {Cell}): Statistic
  local maxEnergy = 0
  local minEnergy = istate.initialEnergy[2]
  local sumEnergy = 0

  -- зачем?
  for _, v in ipairs(cells) do
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
  return { 
    maxEnergy = maxEnergy,
    minEnergy = minEnergy,
    midEnergy = sumEnergy / #cells,
    allEated = cellActions.getAllEated(),
  }
end


function emitFoodInRandomPoint(): boolean, Cell
  local x = rng:random(1, gridSize)
  local y = rng:random(1, gridSize)
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
local accum = 0

--[[
Сделать возможность генерации пищи не на каждом шагу симуляции
--]]
function emitFood(_: number)
    --print("math.log(iter)", math.log(iter) / 1)
    --for i = 1, math.log(iter) do
    --print("cellId", cellId)
    --print("math.log(iter)", math.log(cellId) / 1)
    --for i = 1, math.floor(math.log(cellId)) do

    while true do
        if istate.nofood then
            --return
            coroutine.yield()
        end

        accum = accum + foodGenerationSpeed

        if accum > 1 then
            accum = 0
            for i = 0, math.floor(accum) do
                --print(i, accum)
                local emited, _ = emitFoodInRandomPoint()
                if not emited then
                    -- здесь исследовать причины смерти яцейки
                    --print("not emited gridcell", inspect(gridcell))
                end
            end

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
      -- увеличить количество умерших
      stat.died = stat.died + 1
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
        print("cloned cell")
        table.insert(cells, new)
        return new
    else
        print("nothing in clone")
        return nil
    end
end
--]]

local function genPosition(): number, number
    local cx = 0
    local cy = 0
    local i, limit = 0, 1000
    while true do
        cx = rng:random(1, istate.gridSize)
        cy = rng:random(1, istate.gridSize)
        local len = dist(
            cx, cy, 
            istate.spreadPoint.x, istate.spreadPoint.y
        )
        local ex1 = len < istate.spreadRad
        local ex2 = grid[cx][cy].food == nil
        local ex3 = grid[cx][cy].energy == nil;
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
local function emitCell(iter: number)
    if threadNum == 1 then
        --local steps = 5
        --local cell = initCellOneCommandCode("left", steps)
        --cell.color = {0, 0, rng:random()}
        --cell.pos.x = 30
        --cell.pos.y = 1
    end
    if threadNum == 2 then
        --local steps = 5
        --local cell = initCellOneCommandCode("right", steps)
        --cell.color = {rng:random(), 0, 0}
    end

    --[[
    print("cellsNum", cellsNum)
    -- не создается нужное количество клеток
    while true do
        --for i = 1, cellsNum do
        if cellId >= cellsNum then
            break
        end
        if iter - lastEmitIter >= emitInvSpeed then
            print("iter", iter)
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

    for i = 1, istate.cellsNum do
        local cx = rng:random(1, istate.gridSize)
        local cy = rng:random(1, istate.gridSize)
        table.insert(cells, Cell.new({ pos = { x = cx, y = cy } }))
    end
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
    local cellEmitCoro: thread = coroutine.create(emitCell)
    local emitFoodCoro: thread = coroutine.create(emitFood)

    iter = 0
    lastEmitIter = 0

    grid = getFalseGrid()
    updateGrid()
    stat= gatherStatistic(cells)

    coroutine.yield()
    coroutine.resume(cellEmitCoro, iter)
    print("#Experiment started with", #cells)

    --while #cells > 0 do
    -- если нет живых клеток, то вставать на паузу, но сохранять возможность
    -- вставки клеток через сообщение insertcell
    while true do

        -- создание клеток
        if cellEmitCoro and not coroutine.resume(cellEmitCoro, iter) then
            cellEmitCoro = nil
        end
        -- создание питания
        if emitFoodCoro and not coroutine.resume(emitFoodCoro, iter) then
            emitFoodCoro = nil
        end

        -- проход по списку клеток и вызов их программ. уничтожение некоторых клеток
        cells = updateCells(cells)

        -- проход по списку питания и проверка на съеденность.
        meals = updateMeal(meals)

        -- сброс решетки
        grid = getFalseGrid()

        -- обновление решетки по списку живых клеток и списку еды
        updateGrid()

        -- обновить статистику за такт
        stat = gatherStatistic(cells)

        iter = iter + 1

        --print("cells", #cells)

        -- можно возвращать сдесь какое-то состояние клеток из нити
        --coroutine.yield(stepStatistic)
        coroutine.yield()
    end

    print("there is no cells in simulation")
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
    -- нужное-ли условие?
    --if dataChan:getCount() < maxDataChannelCount then
    if channels.data:getCount() < maxDataChannelCount then
        channels.data:push(drawlist)
    end
end

function commands.info()
    local info: ThreadInfo = {
        cells = #cells,
        meals = #meals,
        stepsPerSecond = stepsPerSecond,
    }
    channels.request:push(serpent.dump(info))
end

function commands.stop()
    print("stop command, break main cycle")
    stop = true
end

function commands.getobject()
    local x, y: number, number = channels.msg:pop() as number, channels.msg:pop() as number
    print("commands.getobject", x, y)
    local ok, errmsg: boolean, string = pcall(function()
        if grid then
            local cell = grid[x][y]
            if cell then
                --requestChan:push(serpent.dump(cell))
                local dump = serpent.dump(cell)
                print("dump", dump)
                channels.object:push(dump)
            end
        end
    end)
    if not ok then
        print("Error in getobject operation", errmsg)
    end
end

function commands.step()
  checkStep = true
  doStep = true
end

function commands.continuos()
  checkStep = false
end

local function writelog(...: string)
    local buf = ""
    for i = 1, select("#", ...) do
        buf = buf .. select(i, ...)
    end
    love.filesystem.append(logName, buf .. "\n")
end

function commands.isalive()
    local x, y = channels.msg:pop() as number, channels.msg:pop() as number  
    if not x or not y or not threadNum then
        assert(string.format("x, y " ..  x .. " " .. y .. " threadNum " .. threadNum))
    end

    --print(x, y, threadNum)
    --print(type(x), type(y), type(threadNum))
    --writelog(string.format("isalive %d x, y %d %d", threadNum, x, y))

    local ok, errmsg: boolean, string = pcall(function()
        if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
            local cell = grid[x][y]
            writelog(string.format("cell %s", inspect(cell)))
            --local state: boolean = cell.energy and cell.energy > 0
            local state = false
            if cell.energy and cell.energy > 0 then
                state = true
            end
            writelog(string.format("pushed state %s", state))
            --print("pushed state", state)
            channels.cellrequest:push(state)
        end
    end)
    if not ok then
        error("isalive error: " ..errmsg)
    end
end

function commands.insertcell()
  local newcellfun, err = load(channels.msg:pop() as string)
  if err then
    error(string.format("insertcell %s", err))
  end
  local newcell: Cell = newcellfun() as Cell
  newcell.id = istate.cellId
  istate.cellId = istate.cellId + 1
  -- нормально, что grid не устанавливается и синхронизация пройдет только на
  -- следущем шаге?
  table.insert(cells, newcell)
end

function commands.writestate()
    local opts = {fatal = true}
    local cellsStr = serpent.dump(cells, opts)
    local mealsStr = serpent.dump(meals, opts)
    local result = {}
    -- записываю по 4 байта - номер потока, длины строк
    local lenMarker = struct.pack("<ddd", threadNum, #cellsStr, #mealsStr)
    table.insert(result, lenMarker)
    table.insert(result, cellsStr)
    table.insert(result, mealsStr)
    
    channels.state:push(table.concat(result))
end

local function popCommand()
    local cmd: ThreadCommands
    repeat
        cmd = channels.msg:pop() as ThreadCommands
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
    local setupName = "setup" .. threadNum
    istate = love.thread.getChannel(setupName):pop() as CommonSetup
    istate.rg = rng

    if istate.mode == "step" then
        commands.step()
    elseif istate.mode == "continuos" then
        commands.continuos()
    end

    print("thread", threadNum)
    print("istate", inspect(istate))

    gridSize = istate.gridSize
    codeLen = istate.codeLen
    cellsNum = istate.cellsNum
    emitInvSpeed = istate.emitInvSpeed

    local sschema: string = love.thread.getChannel(setupName):pop() as string

    local schemafun, err = load(sschema)
    if err then
        error("Could'not get schema for thread")
    end
    local schemaRestored: MtSchema = schemafun() as MtSchema
    print("schemaRestored", inspect(schemaRestored))
    schema = shallowCopy(schemaRestored)

    drawCoefficients = shallowCopy(schemaRestored.draw)

    print("schema", inspect(schema))
    print("drawCoefficients", inspect(drawCoefficients))

    experimentCoro = coroutine.create(function()
        local ok, errmsg: boolean, string = pcall(experiment)
        if not ok then
            logferror("Error in experiment pcall '%s'", errmsg)
        end
    end)

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
        writelog = writelog,
    })

    -- установка ссылки на таблицу действий - язык клетки.
    --actions = cellActions.actions

    istate.rg = rng
    istate.cellActions = cellActions.actions
    cellInitInternal(istate)
end

local function step()
    local newtimestamp = love.timer.getTime()
    if newtimestamp - timestamp >= 1 then
        stepsPerSecond = stepsCount
        stepsCount = 0
        timestamp = newtimestamp
    end

    local ok, errmsg = coroutine.resume(experimentCoro)
    stepsCount = stepsCount + 1

    if not ok and not experimentErrorPrinted then
        experimentErrorPrinted = true
        free = true
        print(string.format("coroutine error %s", errmsg))
    end
end

local function main()
    local syncChan = love.thread.getChannel("sync")
    channels.ready:push("ready")
    timestamp = love.timer.getTime()
    while not stop do
        popCommand()

        if not free then
            if checkStep then
                if doStep then
                    step()
                end
                love.timer.sleep(0.002)
            else
                step()
            end
            pushDrawList()

            local _: any = syncChan:demand(0.001)
            --local syncMsg = syncChan:demand()
            --local syncMsg = syncChan:pop()
            --print(threadNum, syncMsg)

            doStep = false

            local iterChan = love.thread.getChannel("iter")
            iterChan:push(iter)
        else
            love.timer.sleep(0.002)
        end
    end
    channels.ready:clear()
    channels.ready:push("free")
end

doSetup()
main()

print("thread", threadNum, "done")

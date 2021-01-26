require("mobdebug").start()
local threadNum: number = ... as number
print("thread", threadNum, "is running")

require "love.filesystem"
require "love"

local inspect = require "inspect"
local serpent = require "serpent"

love.filesystem.setRequirePath("scenes/automato/?.lua")

require "ex"
require "external"
require "log"
require "love.timer"
require "mtschemes"
require "types"

--print("------------------- WORKER STARTED -------------------")

local randseed: number = love.timer.getTime()
math.randomseed(randseed)

--package.path = package.path .. ";scenes/automato/?.lua"
--local grid = require "grid".new()
local initialSetup: CommonSetup

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
local statistic: Statistic = {}
-- список еды
local meal: {Cell} = {}
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


local chan = love.thread.getChannel("msg" .. threadNum)
local data = love.thread.getChannel("data" .. threadNum)
local request = love.thread.getChannel("request" .. threadNum)

local actionsModule = require "cell-actions"

local function getCodeValues(): {string}
  local codeValues = {}
  for k, _ in pairs(actionsModule.actions) do
    
    -- XXX
    if k == "left" then k = "left2"
    elseif k == "right" then k = "right2"
    elseif k == "up" then k = "up2"
    elseif k == "down" then k = "down2"
    end

    table.insert(codeValues, k)
  end
  return codeValues
end

local codeValues = getCodeValues()

local actions: {string: function(Cell)}
local removed: {Cell} = {}
local experimentCoro: thread

-- генератор кода
function genCode(): {string}
  local code = {}
  local len = #codeValues
  for i = 1, codeLen do
    table.insert(code, codeValues[math.random(1, len)])
  end
  return code
end

local cellId = 0

-- t.pos, t.code
-- конструктор клетки
function initCell(t: CellSetup): Cell
  t = t or {}
  local self: Cell = {}
  self.pos = {}
  if t.pos and t.pos.x then
    self.pos.x = t.pos.x
  else
    self.pos.x = math.random(1, gridSize)
  end
  if t.pos and t.pos.y then
    self.pos.y = t.pos.y
  else
    self.pos.y = math.random(1, gridSize)
  end
  if t.code then
    self.code = copy(t.code)
  else
    self.code = genCode()
  end
  self.ip = 1
  self.id = cellId
  cellId = cellId + 1
  self.energy = math.random(initialSetup.initialEnergy[1], initialSetup.initialEnergy[2])
  print("self.energy", self.energy)
  table.insert(cells, self)
  return self
end

function updateCell(cell: Cell): boolean, Cell
    -- прокрутка кода клетки по кругу
    if cell.ip >= #cell.code then
        cell.ip = 1
    end
    print("cell", cell.id, "energy", cell.energy)
    if cell.energy > 0 then
        local code = cell.code[cell.ip]
        print("code", code)
        actions[code](cell)
        cell.ip = cell.ip + 1
        cell.energy = cell.energy - initialSetup.denergy
        return true, cell
    else
        print("cell died with energy", cell.energy, "moves", inspect(cell.moves))
        return false, cell
    end
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
  for _, v in ipairs(meal) do
    grid[v.pos.x][v.pos.y] = v
  end
end

-- не работает нормально. Нужно отсылал с некоторой периодичностью в виде 
-- сообщений в основную нить
function gatherStatistic(cells: {Cell}): Statistic
  local maxEnergy = 0
  local minEnergy = initialSetup.initialEnergy[2]
  local sumEnergy = 0
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
    allEated = actionsModule.getAllEated(),
  }
end


function emitFoodInRandomPoint(): boolean, Cell
  local x = math.random(1, gridSize)
  local y = math.random(1, gridSize)
  local t = grid[x][y]
  -- если клетка пустая
  if not t.energy then
    local self = {
      food = true,
      pos = {x = x, y = y}
    }
    table.insert(meal, self)
    grid[x][y] = self
    return true, grid[x][y]
  else
    return false, grid[x][y]
  end
end


function emitFood(iter: number)
    if initialSetup.nofood then
        return
    end

    --print(math.log(iter) / 1)
    for i = 1, math.log(iter) * 10 do
        local emited, _ = emitFoodInRandomPoint()
        if not emited then
            -- здесь исследовать причины смерти яцейки
            --print("not emited gridcell", inspect(gridcell))
        end
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
    local struct = require "struct"
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
    local isalive, c = updateCell(cell)
    if isalive then
      table.insert(alive, c)
    else
      table.insert(removed, c)
      print("cell removed")
    end
  end
  return alive
end

local function initCellOneCommandCode(command: string, steps: number)
  local cell = initCell()
  print("cell.energy", cell.energy)
  cell.code = {}
  for i = 1, steps do
    table.insert(cell.code, command)
  end
  print("cell.code", inspect(cell.code))
end

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

function initialEmit(iter: number)
    --[[
    [if threadNum == 1 then
    [  for i = 1, cellsNum do
    [    --coroutine.yield(initCell())
    [  end
    [  --elseif threadNum == 2 then
    [else
    [  for i = 1, cellsNum / 100 do
    [    coroutine.yield(initCell())
    [  end
    [end
    ]]

    for i = 1, 2 do
        local steps = 5
        initCellOneCommandCode("left", steps)
    end

    for i = 1, cellsNum do
        --initCell()
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

function experiment()
    local initialEmitCoro: thread = coroutine.create(initialEmit)

    grid = getFalseGrid()
    updateGrid()
    statistic = gatherStatistic(cells)

    coroutine.yield()

    print("hello from coro")
    print("#cells", #cells)

    coroutine.resume(initialEmitCoro)
    print("start with", #cells, "cells")

    --while #cells > 0 do
    while true do

        -- создание клеток
        --if initialEmitCoro and not coroutine.resume(initialEmitCoro) then
        --initialEmitCoro = nil
        --end

        --print("step", iter, " of thread", threadNum)
        --print("#cells", #cells)

        -- создать сколько-то еды
        emitFood(iter)

        -- проход по списку клеток и вызов их программ. уничтожение некоторых клеток
        cells = updateCells(cells)

        -- проход по списку еды и проверка на съеденность.
        meal = updateMeal(meal)

        -- сброс решетки
        grid = getFalseGrid()

        -- обновление решетки по списку живых клеток и списку еды
        updateGrid()

        -- обновить статистику за такт
        --statistic = gatherStatistic()

        iter = iter + 1

        print("cells", #cells)

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
  end
  for _, v in ipairs(meal) do
    table.insert(drawlist, { 
        x = v.pos.x + gridSize * drawCoefficients[1],
        y = v.pos.y + gridSize * drawCoefficients[2], 
        food = true
      })
  end
  -- нужное-ли условие?
  if data:getCount() < 5 then
    data:push(drawlist)
  end
end

function commands.stop()
  stop = true
end

function commands.getobject()
    print("commands.getobject")
    local x, y: number, number = chan:pop() as number, chan:pop() as number
    local ok, errmsg: boolean, string = pcall(function()
        if grid then
            local cell = grid[x][y]
            if cell then
                request:push(serpent.dump(cell))
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

function commands.isalive()
  local x, y = chan:pop() as number, chan:pop() as number  
  local ok, errmsg: boolean, string = pcall(function()
      if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
        local cell = grid[x][y]
        local state: boolean = cell.energy and cell.energy > 0
        request:push(state)
      end
    end)
  if not ok then
    error(errmsg)
  end
end

function commands.insertcell()
  local newcellfun, err = load(chan:pop() as string)
  if err then
    error(string.format("insertcell %s", err))
  end
  local newcell: Cell = newcellfun() as Cell
  newcell.id = cellId
  cellId = cellId + 1
  table.insert(cells, newcell)
end

local function popCommand()
  local cmd: ThreadCommands = chan:pop() as ThreadCommands
  --local cmd: string = chan:pop() as string
  if cmd then
    local command = commands[cmd]
    if command then
      command()
    else
      error(string.format("Unknown command", cmd))
    end
  end
end

local function doSetup()
  local setupName = "setup" .. threadNum
  initialSetup = love.thread.getChannel(setupName):pop() as CommonSetup

  print("thread", threadNum)
  print("initialSetup", inspect(initialSetup))

  gridSize = initialSetup.gridSize
  codeLen = initialSetup.codeLen
  cellsNum = initialSetup.cellsNum
  --initialEnergy[1], initialEnergy[2] = initialSetup.initialEnergy[1], initialSetup.initialEnergy[2]

  local sschema: string = love.thread.getChannel(setupName):pop() as string

  local schemafun, err = load(sschema)
  if err then
    error("Could'not get schema for thread")
  end
  local schemaRestored: MtSchema = schemafun() as MtSchema
  print("schemaRestored", inspect(schemaRestored))
  schema = flatCopy(schemaRestored as table) as MtSchema

  drawCoefficients = flatCopy(schemaRestored.draw) as {number, number}

  print("schema", inspect(schema))
  print("drawCoefficients", inspect(drawCoefficients))

  experimentCoro = coroutine.create(function()
      local ok, errmsg: boolean, string = pcall(experiment)
      if not ok then
        logferror("Error %s", errmsg)
      end
    end)

  -- первый запуск корутины, прогревочный 
  coroutine.resume(experimentCoro)

  actionsModule.init({
      threadNum = threadNum,
      getGrid = getGrid,
      gridSize = gridSize,
      initCell = initCell,
      schema = schema,
      foodenergy = initialSetup.foodenergy,
    })

  -- установка ссылки на таблицу действий - язык клетки.
  actions = actionsModule.actions
end

local free = false

local function step()
  local ok, errmsg = coroutine.resume(experimentCoro)
  if not ok and not experimentErrorPrinted then
    experimentErrorPrinted = true
    free = true
    print(string.format("coroutine error %s", errmsg))
  end
end

local function main()
    local syncChan = love.thread.getChannel("sync")
    while not stop do
        popCommand()

        if not free then
            if checkStep then
                if doStep then
                    step()
                end
                love.timer.sleep(0.02)
            else
                step()
            end
            pushDrawList()

            local syncMsg: any = syncChan:demand(0.001)
            --local syncMsg = syncChan:demand()
            --local syncMsg = syncChan:pop()
            --print(threadNum, syncMsg)

            doStep = false

            local iterChan = love.thread.getChannel("iter")
            iterChan:push(iter)
        else
            love.timer.sleep(0.02)
        end
    end
end

doSetup()
main()

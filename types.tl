require "love"
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
require "mtschemes"

local inspect = require "inspect"

global type Pos = record
    x: number
    y: number
end

global type Cell = record
    color: {number}
    pos: Pos
    ip: number
    energy: number
    code: {string}
    moves: {number} -- массив предыдущих положений клетки
    eated: number   -- сколько клетка съела других клеток
    food: boolean   -- является ли клетка едой
    wantdivide: boolean
    id: number
    generation: number

    new: function(t: CellSetup): Cell
    print: function(Cell)
    update: function(Cell): boolean
end

global type CellActions = {string: function(Cell): boolean}

global type CommonSetup = record
    threadCount: number
    gridSize: number
    cellsNum: number
    -- разброс границы энергии клетки при создании, массив двух элементов
    initialEnergy: {number, number}
    codeLen: number
    nofood: boolean
    denergy: number
    foodenergy: number
    mode: SimulatorMode
    emitInvSpeed: number
    -- положение центра окружности функции разбрасывания клеток
    spreadPoint: Pos
    -- радиус в клетках окружности функции разбрасывания клеток
    spreadRad: number
    rg: love.math.RandomGenerator
    cellId:number
    cellActions: CellActions
end

global type CellSetup = record
    pos: Pos
    code: {string}
    --code: {Expression}
    generation: number
end

global type Cells = {Cell}
global type Grid = {{Cell}}
global type GetGridFunction = function(): Grid
global type InitCellFunction = function(any): Cell

global type CellActionsInit = record
    threadNum: number
    getGrid: GetGridFunction
    gridSize: number
    initCell: InitCellFunction
    schema: MtSchema
    popCommand: function
    -- сколько прибавляется энергии за съеденную еду
    foodenergy: number
    writelog: function(...:string)
end

global type Statistic = record

    enum Types
        "cells"
        "iterations"
        "meals"
        "born"
        "died"
    end

    allEated: number
    maxEnergy: number
    minEnergy: number
    midEnergy: number
    iterAverage: number

    -- количество клеток
    cells: number
    -- пройдено итераций
    iterations: number
    -- количество клеток еды
    meals: number
    -- количество рожденных клеток
    born: number
    -- количество умерших клеток
    died: number

    --[[
    Как собирать и где хранить информацию: 
        самая старая клетка, 
        клетка с наибольшим значением энергии,
        клетка с наименьшим значением энергии,
        самая молодая клетка,
        клетка прошедшая самый длинный путь
        клетка прошедшая самый короткий путь
        клетка съевшая больше всех остальных других клеток
        клетка съевшая меньше всех других клеток
    --]]
end

global type DrawNode = record
    x: number
    y: number
    food: boolean
    color: {number}
end

global type SimulatorMode = enum
    "step"
    "continuos"
    "stop"
end

global type ThreadCommandsStore = record
    stop: function
    getobject: function
    step: function
    continuos: function
    isalive: function
    insertcell: function
    info: function
    writestate: function
end

global type ThreadCommands = enum
    -- прервать главный цикл, завершить поток
    "stop"
    -- получить информацию об клетке в определенной точке
    "getobject"
    -- сделать шаг симуляции
    "step"
    -- перейти в последовательный режим
    "continuos"
    -- проверить жива ли клетка в определенной позиции
    "isalive"
    -- вставить переданную клетку в список клеток
    "insertcell"
    -- получить информацию по нити
    "info"
    -- сохранить состояние на диск
    "writestate"
end

global type ThreadInfo = record
    -- сколько на момент запроса живых клетор
    cells: number
    -- сколько на момент запроса клеток еды
    meals: number
    -- средннее с начала работы количество проведенных итераций симулятора за 
    -- секунду.
    stepsPerSecond: number
    --threadNum: number
end

global type Channels = {string: love.thread.Channel}

--global ChannelsTypes<const>: {string} = {
global ChannelsTypes<const>: {string} = {
    -- передача настроек инициализации
    'setup',
    -- запрос клетки
    "cellrequest", 
    -- получить графику для рисования клетки
    "drawlist", 
    -- прием сообщений с параметрами
    "msg", 
    -- получение объекта по координатам
    "object",
    -- готовность клетки?
    --"ready",
    -- запрос?
    "request",
    -- вернуть сохраненное состояние
    "state",
}

function initChannels(n: number): Channels
    local result: Channels = {}
    for _, v in ipairs(ChannelsTypes as {string}) do
        local name = v .. tostring(n)
        result[v] = love.thread.getChannel(name)
    end
    print('initChannels', inspect(result))
    return result
end

global type Simulator = record

    -- Очень похоже на CommonSetup, объеденить?
    type Preset = record
        name: string
        nofood: boolean
        cellsNum: number
        denergy: number
        foodenergy: number
        gridSize: number
        threadCount: number
    end

    create: function(CommonSetup)
    -- записать состояние симулятора для последующего восстановления
    writeState: function(): string
    -- послать всем потокам выключение
    shutdown: function()
    setMode : function(m: SimulatorMode)
    getMode : function(): SimulatorMode
    getDrawLists : function(): {DrawNode}
    findThreadByPos: function(x: number, y: number): number
    getObject : function(number, number): Cell
    step : function()
    doStep : function()
    getStatistic : function(): Statistic
    getIter : function(): number
    getGridSize : function(): number
    getSchema : function()
    getThreadsInfo: function(): {ThreadInfo}
    -- время симуляции в секундах
    getUptime: function(): number
end


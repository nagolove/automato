require "love"
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
require "mtschemes"

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
end

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
end

global type CellSetup = record
    pos: Pos
    code: {string}
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
    allEated: number
    maxEnergy: number
    minEnergy: number
    midEnergy: number
    iterAverage: number
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
    cells: number
    meals: number
    -- количество проведенных итераций симулятора за секунду
    stepsPerSecond: number
    --threadNum: number
end

global type ChannelsTypes = enum
    "cellrequest" -- = love.thread.getChannel("cellrequest" .. threadNum)
    "data" -- = love.thread.getChannel("data" .. threadNum)
    "msg" -- = love.thread.getChannel("msg" .. threadNum)
    "object" -- = love.thread.getChannel("object" .. threadNum)
    "ready" -- = love.thread.getChannel("ready" .. threadNum)
    "request" -- = love.thread.getChannel("request" .. threadNum)
    "state" -- = love.thread.getChannel("state" .. threadNum)
end

global type Channels = {string: love.thread.Channel}

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


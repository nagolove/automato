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
end

global type CellSetup = record
    pos: Pos
    code: {string}
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
end

global type ThreadCommandsStore = record
    stop: function
    getobject: function
    step: function
    continuos: function
    isalive: function
    insertcell: function
    info: function
end

global type ThreadCommands = enum
    "stop"
    "getobject"
    "step"
    "continuos"
    "isalive"
    "insertcell"
    "info"
end

global type ThreadInfo = record
    cells: number
    meals: number
    -- количество проведенных итераций симулятора за секунду
    stepsPerSecond: number
    --threadNum: number
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


require "love"
love.filesystem.setRequirePath("scenes/automato/?.lua")
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
    -- сколько прибавляется энергии за съеденную еду
    foodenergy: number
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
end

global type ThreadCommands = enum
    "stop"
    "getobject"
    "step"
    "continuos"
    "isalive"
    "insertcell"
end

global type Simulator = record
    create: function(CommonSetup)
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
end


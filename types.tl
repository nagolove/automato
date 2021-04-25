require "love"
--love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
require "mtschemes"
require "log"

local inspect = require "inspect"

global type Pos = record
    x: integer
    y: integer
end

global type Cell = record
    color: {number}
    pos: Pos
    ip: integer
    energy: number
    code: {string}
    moves: {number} -- массив предыдущих положений клетки
    eated: number   -- сколько клетка съела других клеток
    food: boolean   -- является ли клетка едой
    -- Счетчик деления. Если == 0, то клетка готова делится
    wantdivide: number
    id: number
    generation: number

    new: function(t: CellSetup): Cell
    print: function(Cell)
    update: function(Cell): boolean
end

global type CellActions = {string: function(Cell): boolean}

global type CommonSetup = record
    -- количество потоков
    threadCount: integer
    -- размер сетки
    gridSize: integer
    -- максимальное количество клеток
    cellsNum: integer
    -- разброс границы энергии клетки при создании, массив двух элементов
    initialEnergy: {number, number}
    -- длина кода генерируемого новой клетке
    codeLen: integer
    -- обновлять-ли клетки еды
    nofood: boolean
    -- на сколько уменьшается энергия клетки
    denergy: number
    -- на сколько увеличивается энергия если поесть
    foodenergy: number
    -- режим работы
    mode: SimulatorMode
    -- 1/(скорость создания новых клеток)
    emitInvSpeed: number
    -- положение центра окружности функции разбрасывания клеток
    spreadPoint: Pos
    -- радиус в клетках окружности функции разбрасывания клеток
    spreadRad: number
    -- состояние ГПСЧ из вызывающей нити, разделяется между всеми потоками
    rngState: string
    -- используется только в рабочей нити
    rng: love.math.RandomGenerator
    -- номер последней клетки(всешл созданных)
    cellId:number
    -- используется в классе Cell
    cellActions: CellActions
    -- как располагать начальные клетки
    emitFlags: EmitFlags
end

global type CellSetup = record
    pos: Pos
    code: {string}
    --code: {Expression}
    energy: number
    generation: number
    wantdivide: number
end

global type Cells = {Cell}
global type Grid = {{Cell}}
global type GetGridFunction = function(): Grid
global type InitCellFunction = function(any): Cell

global type CellActionsInit = record
    threadNum: integer
    getGrid: GetGridFunction
    gridSize: integer
    initCell: InitCellFunction
    schema: MtSchema
    popCommand: function
    -- сколько прибавляется энергии за съеденную еду
    foodenergy: number
    writelog: function(...:any)
    rng: love.math.RandomGenerator
    setStepMode: function()
    channels: Channels
end

global type Statistic = record

    enum Types
        'allEated'
        'maxEnergy'
        'minEnergy'
        'midEnergy'
        "cells"
        "iterations"
        "meals"
        "born"
        "died"
        'percentAreaFilled'
        'stepsPerSecond'
    end

    -- съедено клеток
    allEated: number
    -- максимальная энергия клетки
    maxEnergy: number
    -- минимальная энергия клетки
    minEnergy: number
    -- среднее значение энергии клеток
    midEnergy: number
    -- количество клеток
    cells: number
    -- сделано циклов
    iterations: number
    -- количество клеток еды
    meals: number
    -- количество рожденных клеток
    born: number
    -- количество умерших клеток
    died: number
    -- процент заполнения площади поля
    percentAreaFilled: number
    -- средннее с начала работы количество проведенных итераций симулятора за 
    -- секунду.
    stepsPerSecond: number

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

    --isalive: boolean
end

global formatMods<const>: {Statistic.Types:string} = {
--global formatMods: {string: string} = {
    ['allEated'] = '%d',
    ['maxEnergy'] = '%d',
    ['minEnergy'] = '%d',
    ['midEnergy'] = '%d',
    ['cells'] = '%d',
    ['iterations'] = '%d',
    ['meals'] = '%d',
    ['born'] = '%d',
    ['died'] = '%d',
    ['percentAreaFilled'] = '%f',
    ['stepsPerSecond'] = '%d',
}

global type PictureTypes = enum
    "cell"
    "food"
    "search"
end

-- передается из рабочего потока в основой
global type DrawNode = record
    -- целочисленные координаты от (1,1) до размеров поля
    x: number
    y: number
    -- ячейка еды?
    food: boolean
    -- цвет, только для обычных клеток
    color: {number}
    picture: PictureTypes
end

-- режим работы - протяженный, пошаговый или стоп
global type SimulatorMode = enum
    "continuos"
    "step"
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
    readstate: function
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
    --"info"
    -- сохранить состояние на диск
    "writestate"
    -- прочитать состояние с диска
    'readstate'
end

global type EmitFlags = enum
    'normal'
    -- для тестирования перемещений
    'directions_only'
    -- для тестирования деления
    'divide_only'
end

global type Channels = {string: love.thread.Channel}

global ChannelsTypes: {string} = {
    -- основная нить: запись настроек инициализации
    -- рабочая нить: чтение настроек инициализации
    'setup',

    -- запрос клетки
    "cellrequest", 

    -- основная нить: получить графику для рисования клеток и еды
    -- рабочая нить: записать графику для рисования еды и клеток
    "drawlist", 

    -- основная нить: получить графику для рисования анимации поиска соседней клетки(find neighbor)
    -- рабочая нить: записать графику
    "drawlist_fn",

    -- рабочая нить: прием сообщений
    -- основная нить: отправка сообщений
    "msg", 

    -- основная нить: прочитать клетку
    -- рабочая нить: записать клетку
    "object_r",

    -- основная нить: записать координаты клетки
    -- рабочая нить: прочитать координаты клетки
    "object_w",

    -- готовность клетки?
    --"ready",
    -- запрос?
    "request",

    --[[
    при сериализации:
        * рабочий поток записывает состояние своих клеток
        * основной поток считывает состояния при сериализации
    при десериализации:
        * рабочий поток считывает состояние клеток и еды
        * основной потоко запиcывает состояние клеток и еды
    --]]
    "state",

    -- рабочий поток: запись
    -- основной поток: чтение
    'stat',

    'isstopped',
    --'busy',

    -- рабочий поток: считывает клетку
    -- другой рабочий поток: записывает клетку
    -- XXX может понадобиться операция atomic?
    'cells',

    -- рабочий поток: считывает координаты клетки
    -- другой рабочий поток(или тот-же): записывает координаты клетк
    'alive',

    'colonystatus',
}

function initChannels(n: number): Channels
    local result: Channels = {}
    for _, v in ipairs(ChannelsTypes as {string}) do
        result[v] = love.thread.getChannel(v .. tostring(n))
    end
    printLog(string.format('initChannels, n = %d', n), inspect(result))
    printLog('initChannels traceback', debug.traceback())
    return result
end

global type Simulator = record

    -- Очень похоже на CommonSetup, объеденить?
    type Preset = record
        name: string
        nofood: boolean
        cellsNum: integer
        denergy: number
        foodenergy: number
        gridSize: integer
        threadCount: integer
    end

    -- создать и запустить
    create: function(CommonSetup)
    -- вызывать каждый кадр, для обновления статистики
    update: function(dt: number)

    -- записать состояние симулятора для последующего восстановления
    writeState: function(): string
    -- восстановить состояние из сжатой строки
    readState: function(string): boolean

    -- послать всем потокам выключение
    shutdown: function()
    setMode : function(m: SimulatorMode)
    getMode : function(): SimulatorMode

    -- возвращает истину если колония умерла
    isColonyDied: function(): boolean
    -- убить колонию
    killColony: function()

    -- получить массив данных для рисования
    getDrawLists : function(): {{DrawNode}}

    -- пример запроса для рисования(предки-потомки и тд)
    --getDrawLists : function(query: function(Cell): boolean): {DrawNode}

    -- вернуть номер нити обрабатывающей клетку с индексом x, y
    findThreadByPos: function(x: integer, y: integer): integer

    -- вернуть клетку по координатам ее ячейки
    getObject : function(x: integer, y: integer): Cell

    -- выполнить шаг в пошаговом режиме
    step : function()

    -- возвзвращает таблицу с информацией по колонии на текущий момент
    getStatistic : function(): {Statistic}

    -- размер решетки
    getGridSize : function(): integer

    getSchema : function(): {MtSchema}

    -- время симуляции в секундах
    getUptime: function(): number
end


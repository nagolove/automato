local inspect = require "inspect"
local serpent = require "serpent"
local struct = require "struct"
local timer = require "Timer"
local marshal = require 'marshal'

--local profi = require "profi"
--profi:start()

--local tabular = require "tabular"
package.path = "./scenes/automato/?.lua;" .. package.path
print("package.path", package.path)

require "log"
require "love"
require "mtschemes"
require "types"
require "common"

local infoTimer: Timer = timer.new()
local gridSize: number
local mtschema: {MtSchema}
local starttime: number = 0
local statistic: {Statistic} = {}
local threads: {love.thread.Thread} = {}
local statGatherDelay = 0.1
-- количество потоков
local threadCount: number = -1
local mode: SimulatorMode = "stop"
local channels: {Channels} = {}
--[[
channels[1].cellrequest:push()
--]]
local isdone: boolean = true
local setup: CommonSetup

function Simulator.getDrawLists(): {DrawNode}
    local list = {}
    for k, _ in ipairs(threads) do
        local drawlist = channels[k].drawlist
        --print("datachannel", inspect(drawlist))
        if drawlist then
            --local sublist: {DrawNode} = drawlist:pop() as {DrawNode}
            local sublist: {DrawNode}

            if drawlist:getCount() > 1 then
                sublist = drawlist:pop() as {DrawNode}
            else
                sublist = drawlist:peek() as {DrawNode}
            end

            -- XXX workaround
            if drawlist:getCount() > 20 then
                while drawlist:getCount() > 1 do
                    drawlist:pop()
                end
            end

            print('drawlist:getCount()', drawlist:getCount())

            if sublist then
                for _, node in ipairs(sublist) do
                    table.insert(list, node)
                end
            end
        end
    end
    --print("getDrawLists", inspect(list))
    return list
end

--[[
local function pushSync()
    local syncChan = love.thread.getChannel("sync")
    local i = 1
    while i < threadCount do
        i = i + 1
        syncChan:push("sync")
    end
    --for i = 1, threadCount do
        --syncChan:push("sync")
    --end
end
--]]

local function pushMsg2Threads(t: any)
    for i = 1, threadCount do
        print("send to 'msg" .. i .. "'")
        channels[i].msg:push(t)
    end
end

local function clearChannels()
    print('clearChannels')
    for i = 1, threadCount do
        for _, ch in pairs(channels[i]) do
            ch:clear()
        end
    end
end

--function love.threaderror(thread: love.thread.Thread, errstr: string)
function love.threaderror(_: love.thread.Thread, errstr: string)
    print("Some thread failed with " .. errstr)    
end

function Simulator.create(commonSetup: CommonSetup)
    print('commonSetup', inspect(commonSetup))
    setup = deepCopy(commonSetup)
    print("--------------------------------------------")

    print("commonSetup", inspect(commonSetup))

    if isdone == false then
        Simulator.shutdown()
    end

    -- установка глобальной переменной модуля
    threadCount = commonSetup.threadCount

    print("threadCount", threadCount)

    gridSize = commonSetup.gridSize
    commonSetup.cellId = 0

    local mainRng = love.math.newRandomGenerator()
    -- XXX или лучше os.time()?
    mainRng:setSeed(love.timer.getTime())

    commonSetup.rngState = mainRng:getState()

    mtschema = require "mtschemes"[threadCount] as {MtSchema}
    print("mtschema", inspect(mtschema))

    if not mtschema then
        error(string.format("Unsupported scheme for %d threads.", threadCount))
    end

    for i = 1, threadCount do
        print("Channels for thread", i)
        table.insert(channels, initChannels(i))

        channels[i].setup:push(commonSetup)
        channels[i].setup:push(serpent.dump(mtschema[i]))
        --love.thread.getChannel(setupName):push(serpent.dump(commonSetup))
        --love.thread.getChannel(setupName):push(commonSetup)
        --love.thread.getChannel(setupName):push(serpent.dump(mtschema[i]))

        local th: love.thread.Thread = love.thread.newThread("scenes/automato/simulator-thread.lua")
        table.insert(threads, th)
        th:start(i)
        local errmsg = th:getError()
        if errmsg then
            --logfwarn("Thread %s", errmsg)
            print("Thread %s", errmsg)
        end
    end

    --pushSync()

    print("threads", inspect(threads))
    print("thread errors")
    for _, v in ipairs(threads) do
        print(v:getError())
    end
    print("end thread errors")

    local processorCount = love.system.getProcessorCount()
    print("processorCount", processorCount)

    starttime = love.timer.getTime()
    isdone = false
    infoTimer:every(statGatherDelay, function(_: number)
        -- TODO собирать значения реже, брать таймаут по таймеру

        -- получить структуру статистики из всех запущенных нитей
        local newstat: {Statistic} = {}
        for i, _ in ipairs(threads) do
            local t: Statistic
            if channels[i].stat:getCount() > 1 then
                t = channels[i].stat:pop() as Statistic
            else
                t = channels[i].stat:peek() as Statistic
            end
            print('channels[i].stat:getCount()', channels[i].stat:getCount())
            if t then
                table.insert(newstat, t)
            end
        end
        statistic = newstat
    end)
end

-- FIXME Как починить счетчик итераций при работе в несколько нитей?
--function Simulator.getIter(): number
       --return 0
--end

-- возвращает номер нити многопоточной схемы по целочисленным координатам 
-- клетки. Отсчет с левого верхнего угла
function Simulator.findThreadByPos(x: number, y: number): number
    local fract: number
    local _: any
    _, fract = math.modf(x)
    assert(fract == 0.0, string.format("x = %f", x))
    _, fract = math.modf(y)
    assert(fract == 0.0, string.format("y = %f", y))

    --local ix, iy = math.floor(x / gridSize), math.floor(y / gridSize)
    --local rx, ry = x % gridSize, y % gridSize

    --[[
    Тут должен быть поиск по массиву mtschema для нахождения нити.
    --]]
    for k, v in ipairs(mtschema) do
        local x2, y2 = gridSize + gridSize * v.draw[1], gridSize + gridSize * v.draw[2]
        local x1, y1 = x2 - gridSize, y2 - gridSize

        -- использовать > или >= ???
        if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
            return k
        end
    end
    return -1
end

-- здеcь нужно определять в какой из потоков отправить запрос используя каналы
-- msg1, msg2, ...
-- функция - запрос для визуального отладчика
function Simulator.getObject(x: number, y: number): Cell
    local threadNum = Simulator.findThreadByPos(x, y)

    if threadNum == -1 then
        error(string.format("threadNum == -1 for %d, %d with schema %s", x, y, inspect(mtschema)))
    end

    --local mchan = love.thread.getChannel("msg" .. threadNum)
    local mchan = channels[threadNum].msg
    local bchan = love.thread.getChannel('busy' .. threadNum)
    --local state = bchan:peek() as string

    --channels[threadNum].msg:push('getobject')
    -- пишу из главного
    bchan:push('b')

    --mchan:push("getobject")
    --mchan:push(x)
    --mchan:push(y)

    -- передать команду
    channels[threadNum].msg:push("getobject")
    -- передать параметры команды
    channels[threadNum].object:push(x)
    channels[threadNum].object:push(y)

    bchan:clear()

    --[[


    --mchan:push("getobject")
    channels[threadNum].msg:push("getobject")
    channels[threadNum].object:push(x)
    channels[threadNum].object:push(y)


    { 
        cmd = 'getobject',
        ...,
        ...,
    }
    ]]

    -- FIXME demand не дает ответа за таймаут и вешает программу
    --local sobject = rchan:demand(0.01) as string
    local sobject = channels[threadNum].object:pop() as string

    --print("sobject", sobject)

    if not sobject then
        return nil
    end

    --local objectfun, err: function, boolean = serpent.load(sobject)
    local ok, object: boolean, Cell = serpent.load(sobject) as (boolean, Cell)

    --print("ok", ok)

    if not ok then
        --logferror("Could'not deserialize cell object %s", err)
        logferror("Could'not deserialize cell object")
        return nil
    end

    print("rchan:getCount()", channels[threadNum].object:getCount())
    print("object", inspect(object))
    return object
end

function Simulator.setMode(m: SimulatorMode)
    mode = m
    print("push", mode)
    pushMsg2Threads(mode)
end

function Simulator.getMode(): SimulatorMode
    return mode
end

function Simulator.step()
    pushMsg2Threads("step")
end

function Simulator.getStatistic(): {Statistic}
    return statistic
end

function Simulator.getSchema(): {MtSchema}
    return mtschema
end

function Simulator.update(dt: number)
    infoTimer:update(dt)
end

function Simulator.getGridSize(): number
    return gridSize
end

function Simulator.shutdown()
    print("Simulator.shutdown()")
    pushMsg2Threads('stop')

    if isdone then
        return
    end

    local t = {}
    for i = 1, threadCount do
        table.insert(t, i)
    end

    while #t ~= 0 do
        local i = #t
        while i > 0 do
            local stopped: boolean = channels[i].isstopped:pop() as boolean
            if stopped and stopped == true then
                print('thread', i, 'stopped')
                table.remove(t, i)
                break
            end
            i = i - 1
        end
    end

    clearChannels()
    print('t', inspect(t))
    print('shutdown done')
    isdone = true
    mode = 'stop'
end

function Simulator.getUptime(): number
    return love.timer.getTime() - starttime
end

local function unpackState(data: string): {string}
    local res = {}
    local threadNum: number = struct.unpack('<d', data) as number
    local intSize = 4
    local idx = intSize + 1
    print('threadNum', threadNum)
    print('data', #data)
    for i = 1, threadNum do
        print('idx', idx)
        print('idx + intSize', idx + intSize)
        local s = string.sub(data, idx, idx + intSize)
        print('subs', #s)
        print('s', s)
        local len = struct.unpack('<d', s) as number
        local payload = string.sub(data, idx + intSize + 1, idx + intSize + len + 1)
        idx = idx + len + 1
        table.insert(res, payload)

        love.filesystem.write(string.format('unpack-%d.txt', i), payload)
    end

    return res
end

function Simulator.readState(data: string): boolean
    -- отправить сообщение о завершении всем нитям
    -- подождать

    -- два варианта восстановления состояния :
    -- * разосласть сообщения потокам 
    --          преимущество в быстродействии при перемотке
    --          нужно писать код для потока
    -- * запустить потоки заново, передав прочтенные данные как параметр
    --          полное восстановление конфигурации
    --          нужно дописать код завершения потока. Добавить прерывание
    --          главного цикла
    --          нужно заменить идентификаторы потоков в модуле simulator

    print("readState")

    local decompData = love.data.decompress('string', 'zlib', data) as string
    local threadStates = unpackState(decompData)

    do
        return false
    end

    infoTimer = timer.new()

    if isdone == false then
        Simulator.shutdown()
    end

    --threadCount = commonSetup.threadCount
    print("threadCount", threadCount)

    --gridSize = commonSetup.gridSize
    --commonSetup.cellId = 0

    local mainRng = love.math.newRandomGenerator()
    -- XXX или лучше os.time()?
    mainRng:setSeed(love.timer.getTime())

    --commonSetup.rngState = mainRng:getState()

    mtschema = require "mtschemes"[threadCount] as {MtSchema}
    print("mtschema", inspect(mtschema))

    if not mtschema then
        error(string.format("Unsupported scheme for %d threads.", threadCount))
    end

    for i = 1, threadCount do
        print("Channels for thread", i)
        table.insert(channels, initChannels(i))

        --channels[i].setup:push(commonSetup)
        channels[i].setup:push(serpent.dump(mtschema[i]))
        --love.thread.getChannel(setupName):push(serpent.dump(commonSetup))
        --love.thread.getChannel(setupName):push(commonSetup)
        --love.thread.getChannel(setupName):push(serpent.dump(mtschema[i]))

        local th: love.thread.Thread = love.thread.newThread("scenes/automato/simulator-thread.lua")
        table.insert(threads, th)
        th:start(i)
        local errmsg = th:getError()
        if errmsg then
            --logfwarn("Thread %s", errmsg)
            print("Thread %s", errmsg)
        end
    end

    --pushSync()

    print("threads", inspect(threads))
    print("thread errors")
    for _, v in ipairs(threads) do
        print(v:getError())
    end
    print("end thread errors")

    local processorCount = love.system.getProcessorCount()
    print("processorCount", processorCount)

    starttime = love.timer.getTime()
    isdone = false
    infoTimer:every(statGatherDelay, function(_: number)
        -- TODO собирать значения реже, брать таймаут по таймеру

        -- получить структуру статистики из всех запущенных нитей
        local newstat: {Statistic} = {}
        for i, _ in ipairs(threads) do
            local t: Statistic
            --if channels[i].stat:getCount() > 1 then
                t = channels[i].stat:pop() as Statistic
            --else
                --t = channels[i].stat:peek() as Statistic
            --end
            print('channels[i].stat:getCount()', channels[i].stat:getCount())
            if t then
                table.insert(newstat, t)
            end
        end
        statistic = newstat
    end)

    return true
end

function Simulator.writeState(): string
    -- выставить паузу для всех нитей
    -- послать сообщение каждой нити о сохранении
    -- прочитать все полученные результаты
    -- объеденить результаты
    -- отключить паузу для потоков

    -- TODO добавить сериализацию commonSetup

    for i = 1, threadCount do
        channels[i].msg:push('writestate')
    end

    local t = {}
    local notwritten = 0

    -- TODO
    -- добавить схему mtschema??
    -- примитивный цикл обработки. Попробовать while allDemanded do
    -- с методом :peek() для проверки готовы-ли данные
    local setupString = serpent.dump(setup)
    local mtschemaString = serpent.dump(mtschema)
    local threadCountString = tostring(threadCount)
    --[[
    local blobStructure = {
        [1] = 'setup',
        [2] = 'mtschema',
        [3] = 'threadCount',
        [4] = 'threads',
    }
    --]]

    local function writeString(str: string)
        local len = struct.pack("<d", #str) as string
        table.insert(t, len)
        table.insert(t, str)
    end

    -- записываю структуру для запуска потока
    writeString(setupString)
    -- записываю массив схем многопоточности
    writeString(mtschemaString)
    -- записываю количество потоков(кусков данных)
    writeString(threadCountString)

    for i = 1, threadCount do
        local t1 = love.timer.getTime()
        ---- XXX Может все завесить навечно
        local thread = channels[i].state:demand() as string
        local t2 = love.timer.getTime()
        print('demand time', t2 - t1)

        if not thread then
            error("Could'not retrive string from thread")
        end

        -- записываю содержимое потока
        writeString(thread)

        if not (thread and #thread ~= 0) then
            notwritten = notwritten + 1
        end
    end

    print('writestate by', threadCount, ' not written ', notwritten)

    local fullData = table.concat(t)

    -- TODO возвращать управление сразу, сжатие проводить в отдельном потоке.
    -- возвращать флаг завершения и сжатую строчку через уникальный именованный
    -- канал
    --[[
    local thread = love.thread.newThread([[
        local channelName = ...
        local channel = love.thread.getChannel(channelName)
        local data = channel:demand()
        local comressed = love.data.compress('string', 'zlib', data, 9)
        channel:push('done')
        channel:push(data)
    ]]
    -- Вызывающая сторона получает ссылку на межпрцессный канал и выставляет 
    -- кнопку записи состояния в неактивное положение пока не прочитает 'done'
    --]]

    return love.data.compress("string", "zlib", fullData, 9) as string
end

--profi:stop()
--profi:writeReport("simulator-profile.txt")

return Simulator

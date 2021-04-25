require "log"

local inspect = require "inspect"
local serpent = require "serpent"
local timer = require "Timer"
--local struct = require "struct"
--local marshal = require 'marshal'

--local profi = require "profi"
--profi:start()

--local tabular = require "tabular"
package.path = "./scenes/automato/?.lua;" .. package.path
printLog("package.path", package.path)

require "log"
require "love"
require "mtschemes"
require "types"
require "common"

--local prof = require "jprof"
local infoTimer: Timer = timer.new()
local gridSize: integer
local mtschema: {MtSchema}
local starttime: number = 0
local statistic: {Statistic} = {}
local threads: {love.thread.Thread} = {}
local statGatherDelay = 0.1
-- количество потоков
local threadCount: integer = -1
local mode: SimulatorMode = "stop"
local channels: {Channels} = {}
--[[
channels[1].cellrequest:push()
--]]
local isdone: boolean = true
local setup: CommonSetup
local colonyDied = false
local maxExtractDrawListCount = 20

-- опрашивает поток симулятора через именованный канал на получение списка рисования и
-- добавляет полученные ноды в переданный список
local function extractDrawList(list: {DrawNode}, channel: love.thread.Channel)

    --prof.push("extractDrawList")

    if channel then
        local sublist: {DrawNode}

        -- если элементов несколько, то снимаю последние. Если элемент один, то
        -- оставляю
        if channel:getCount() > 1 then
            sublist = channel:pop() as {DrawNode}
        else
            sublist = channel:peek() as {DrawNode}
        end

        if channel:getCount() > maxExtractDrawListCount then
            while channel:getCount() > 1 do
                channel:pop()
            end
        end

        if sublist then
            for _, node in ipairs(sublist) do
                table.insert(list, node)
            end
        end
    else
        --printLog('extractDrawList() with nil channel')
    end

    --prof.pop("extractDrawList")

end

function Simulator.killColony()
    colonyDied = true
end

function Simulator.getDrawLists(): {{DrawNode}}
    --prof.push("getDrawLists")
    local list = {}

    -- первый список рисования
    list[#list + 1] = {}

    -- второй список рисования
    list[#list + 1] = {}

    -- опросить все потоки
    for k, _ in ipairs(threads) do
        -- основной список 
        local drawlist: love.thread.Channel = channels[k].drawlist
        -- дололнительный(экспериментальный) список
        local drawlist_fn: love.thread.Channel = channels[k].drawlist_fn_

        --print('lists', drawlist, drawlist_fn)

        extractDrawList(list[1], drawlist)
        extractDrawList(list[2], drawlist_fn)

        --love.filesystem.append('drawlist_fn.txt', inspect(list[2]) .. "\n\n\n\n")
    end
    --prof.pop("getDrawLists")
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
    print('pushMsg2Threads()', tostring(t))
    for i = 1, threadCount do
        print("send to 'msg" .. i .. "'")
        channels[i as integer].msg:push(t)
    end
end

local function clearChannels()
    print('clearChannels')
    for i = 1, threadCount do
        for _, ch in pairs(channels[i as integer]) do
            ch:clear()
        end
    end
end

--function love.threaderror(thread: love.thread.Thread, errstr: string)
function love.threaderror(_: love.thread.Thread, errstr: string)
    print("Some thread failed with " .. errstr)    
end

local type ThreadCreateCallback = function(th: love.thread.Thread, i: number)
local function createThreads(
    threadCount: number,
    mtschema: {MtSchema},
    commonSetup: CommonSetup, 
    cb: ThreadCreateCallback
)
    for i = 1, threadCount do
        print("Channels for thread", i)
        table.insert(channels, initChannels(i))

        channels[i as integer].setup:performAtomic(function(channel: love.thread.Channel)
            channel:push(commonSetup)
            channel:push(serpent.dump(mtschema[i as integer]))
        end)
        -- создание рабочей нити
        local th: love.thread.Thread = love.thread.newThread("scenes/automato/simulator-thread.lua")
        table.insert(threads, th)
        -- запуск нити, передаю номер
        th:start(i)
        if cb then
            cb(th, i)
        end
        local errmsg = th:getError()
        if errmsg then
            --logfwarn("Thread %s", errmsg)
            print("Thread %s", errmsg)
        end
    end
end

function Simulator.create(commonSetup: CommonSetup)
    print('commonSetup', inspect(commonSetup))

    love.filesystem.write('drawlist_fn.txt', "")

    setup = deepCopy(commonSetup)

    printLog("--------------------------------------------")
    printLog("commonSetup", inspect(commonSetup))

    if isdone == false then
        Simulator.shutdown()
    end

    colonyDied = false

    -- установка глобальной переменной модуля
    threadCount = commonSetup.threadCount

    printLog("threadCount", threadCount)

    gridSize = commonSetup.gridSize
    commonSetup.cellId = 0

    local mainRng = love.math.newRandomGenerator()
    -- XXX или лучше os.time()?
    mainRng:setSeed(love.timer.getTime())

    commonSetup.rngState = mainRng:getState()

    mtschema = require "mtschemes"[threadCount] as {MtSchema}
    printLog("mtschema", inspect(mtschema))

    if not mtschema then
        error(string.format("Unsupported scheme for %d threads.", threadCount))
    end

    createThreads(threadCount, mtschema, commonSetup)

    printLog("threads", inspect(threads))
    printLog("thread errors")
    for _, v in ipairs(threads) do
        printLog(v:getError())
    end
    printLog("end thread errors")

    local processorCount = love.system.getProcessorCount()
    printLog("processorCount", processorCount)

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
            if t then
                table.insert(newstat, t)
            end
        end
        statistic = newstat
    end)
end

function Simulator.isColonyDied(): boolean
    return colonyDied
end

-- возвращает номер нити многопоточной схемы по целочисленным координатам 
-- клетки. Отсчет с левого верхнего угла
function Simulator.findThreadByPos(x: integer, y: integer): integer
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
function Simulator.getObject(x: integer, y: integer): Cell
    local threadNum = Simulator.findThreadByPos(x, y)

    if threadNum == -1 then
        error(string.format("threadNum == -1 for %d, %d with schema %s", x, y, inspect(mtschema)))
    end

    -- передать команду
    channels[threadNum].msg:push("getobject")

    -- передать параметры команды
    channels[threadNum].object_w:performAtomic(function(channel: love.thread.Channel)
        channel:push(x)
        channel:push(y)
    end)

    -- FIXME demand не дает ответа за таймаут и вешает программу
    local sobject = channels[threadNum].object_r:demand(0.01) as string

    if not sobject then
        return nil
    end

    local ok, object: boolean, Cell = serpent.load(sobject) as (boolean, Cell)
    if not ok then
        logferror("Could'not deserialize cell object")
        return nil
    end

    return object
end

function Simulator.setMode(m: SimulatorMode)
    mode = m
    print("push", mode)
    print('Simulator.setMode', m)
    pushMsg2Threads(mode)
end

function Simulator.getMode(): SimulatorMode
    return mode
end

function Simulator.step()
    print('Simulator.step()')
    --print('ppppppppppppppppppppppppppppppppppp')
    --getDrawLists
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

    local counter = 0
    for i = 1, threadCount do
        local value = channels[i].colonystatus:pop() as string
        if value and value == "nocellsincolony" then
            counter = counter + 1
        end
    end
    if threadCount == counter then
        colonyDied = true
    end
end

function Simulator.getGridSize(): integer
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

--[[
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
--]]

function Simulator.readState(data: string): boolean
    print('Simulator.readState()')

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

    local decompData = love.data.decompress('string', 'zlib', data) as string
    print('#data', #data)
    print('#decompData', #decompData)
    local ok, store_any = serpent.load(decompData)
    local store: {string: any} = store_any as {string: any}

    if not ok then
        return false
    end

    print('store', store)
    love.filesystem.write('restore.txt', inspect(store))

    --print("os.exit()")
    --os.exit()
    ----local threadStates = unpackState(decompData)

    setup = deepCopy(store.setup as CommonSetup)
    mtschema = store.mtschema as {MtSchema}

    infoTimer = timer.new()

    if isdone == false then
        Simulator.shutdown()
    end

    --threadCount = commonSetup.threadCount
    threadCount = tonumber(store.threadCount) as integer
    print("threadCount", threadCount)

    --gridSize = commonSetup.gridSize
    --commonSetup.cellId = 0

    local mainRng = love.math.newRandomGenerator()
    -- XXX или лучше os.time()?
    --mainRng:setSeed(love.timer.getTime())
    if setup.rngState then
        mainRng:setState(setup.rngState)
    else
        print('No rngState in store structure')
    end

    --commonSetup.rngState = mainRng:getState()

    --mtschema = require "mtschemes"[threadCount] as {MtSchema}
    print("mtschema", inspect(mtschema))

    if not mtschema then
        error(string.format("Unsupported scheme for %d threads.", threadCount))
    end

    createThreads(
        setup.threadCount, 
        mtschema, 
        setup,
        function(_: love.thread.Thread, i: integer)
            channels[i].state:performAtomic(
                function(channel: love.thread.Channel)
                    channel:clear()
                    channel:push(store['thread' .. tostring(i)])
                end
            )
            channels[i].msg:push('readstate')
        end
    )

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
            --print('channels[i].stat:getCount()', channels[i].stat:getCount())
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

    --local t = {}
    local notwritten = 0

    local store: {string:any} = {
        setup = setup,
        mtschema= mtschema,
        -- восстанавливаться будет тоже самое количество нитей
        threadCount = tostring(threadCount),
    }

    for i = 1, threadCount do
        local t1 = love.timer.getTime()
        ---- XXX Может все завесить навечно
        local thread = channels[i].state:demand() as string
        local t2 = love.timer.getTime()
        print('demand time', t2 - t1)

        if not thread then
            error("Could'not retrive string from thread")
        end

        store["thread" .. tostring(i)] = thread

        if not (thread and #thread ~= 0) then
            notwritten = notwritten + 1
        end
    end

    print('writestate by', threadCount, ' not written ', notwritten)

    local fullData = serpent.dump(store)

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

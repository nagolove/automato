local inspect = require "inspect"
local serpent = require "serpent"

--local tabular = require "tabular"
package.path = "./scenes/automato/?.lua;" .. package.path
print("package.path", package.path)

require "love"
require "external"
require "log"
require "types"
require "mtschemes"

local threads: {love.thread.Thread} = {}
local gridSize: number
local mtschema: {MtSchema}

-- количество потоков
local threadCount: number = -1

-- режим работы - протяженный, пошаговый или стоп
local mode = "stop" -- "step"

local statistic: Statistic = {}

function Simulator.getDrawLists(): {DrawNode}
    local list = {}
    for k, _ in ipairs(threads) do
        local chan = love.thread.getChannel("data" .. k)
        if chan then
            local sublist: {DrawNode} = chan:demand(0.1) as {DrawNode}
            if sublist then
                for _, v1 in ipairs(sublist) do
                    table.insert(list, v1)
                end
            end
        end
    end
    return list
end

function Simulator.getThreadsInfo(): {ThreadInfo}
    local list: {ThreadInfo} = {}
    for k, _ in ipairs(threads) do
        local chan = love.thread.getChannel("msg" .. k)
        if chan then
            chan:push("info")

            local rchan = love.thread.getChannel("request" .. k)
            local infostr = rchan:demand(0.02) as string

            if infostr then
                local ok, info = serpent.load(infostr)
                if not ok then
                    error(string.format("Could not load string in getThreadsInfo()"))
                end
                table.insert(list, info as ThreadInfo)
            end
            --local sublist: {DrawNode} = chan:demand(0.1) as {DrawNode}
            --if sublist then
                --for _, v1 in ipairs(sublist) do
                    --table.insert(list, v1)
                --end
            --end
        end
    end
    return list
end

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

local function pushMsg2Threads(t: any)
    for i = 1, threadCount do
        love.thread.getChannel("msg" .. i):push(t)
    end
end

local function sendStopClearChannels()
    if #threads ~= 0 then
        pushMsg2Threads("stop")
        love.timer.sleep(0.05)
        for i = 1, threadCount do
            love.thread.getChannel("msg" .. i):clear()
            love.thread.getChannel("data" .. i):clear()
            love.thread.getChannel("setup" .. i):clear()
            love.thread.getChannel("request" .. i):clear()
        end
    end
end

function love.threaderror(thread: love.thread.Thread, errstr: string)
    print("Some thread failed with " .. errstr)    
end

function Simulator.create(commonSetup: CommonSetup)
    print("--------------------------------------------")
    print("commonSetup", inspect(commonSetup))

    sendStopClearChannels()

    threadCount = commonSetup.threadCount
    print("threadCount", threadCount)

    gridSize = commonSetup.gridSize

    mtschema = require "mtschemes"[threadCount] as {MtSchema}
    print("mtschema", inspect(mtschema))

    if not mtschema then
        error(string.format("Unsupported scheme for %d threads.", threadCount))
    end

    for i = 1, threadCount do
        local setupName = "setup" .. i
        love.thread.getChannel(setupName):push(commonSetup)
        love.thread.getChannel(setupName):push(serpent.dump(mtschema[i]))

        local th: love.thread.Thread = love.thread.newThread("scenes/automato/simulator-thread.lua")
        table.insert(threads, th)
        th:start(i)
        local errmsg = th:getError()
        if errmsg then
            --logfwarn("Thread %s", errmsg)
            print("Thread %s", errmsg)
        end
    end

    pushSync()

    print("threads", inspect(threads))
    print("thread errors")
    for _, v in ipairs(threads) do
        print(v:getError())
    end
    print("end thread errors")

    local processorCount = love.system.getProcessorCount()
    print("processorCount", processorCount)
end


local function getThreadsLog()
    local logChan = love.thread.getChannel("log")
    local msg: {any} = logChan:pop() as {any}
    while msg do
        print(msg[1], msg[2])
        msg = logChan:pop() as {any}
    end
end

function Simulator.step()
    if mode == "stop" then
        return
    end

    --local iterSum: number = 0
    --local iterChan: love.thread.Channel = love.thread.getChannel("iter")
    --local value = iterChan:pop() as number
    --while value do
        --iterSum = iterSum + value
        --value = iterChan:pop() as number
    --end
    --statistic.iterAverage = iterSum / threadCount
    --pushSync()
end

-- FIXME Как починить счетчик итераций при работе в несколько нитей?
function Simulator.getIter(): number
    --[[
       [local newIter = love.thread.getChannel("iter")
       [if newIter then
       [    iter = newIter:pop() or iter
       [end
       [return iter
       ]]
       return 0
end

-- возвращает номер нити многопоточной схемы по координатам 
function Simulator.findThreadByPos(x: number, y: number): number
    local ix, iy = math.floor(x / gridSize), math.floor(y / gridSize)
    local rx, ry = x % gridSize, y % gridSize
    --[[
    Тут должен быть поиск по массиву mtschema для нахождения нити.
    --]]
    --for k, v in pairs(mtschema) do
    --end
    return 1
end

-- здеcь нужно определять в какой из потоков отправить запрос используя каналы
-- msg1, msg2, ...
-- функция - запрос для визуального отладчика
function Simulator.getObject(x: number, y: number): Cell
    local threadNum = Simulator.findThreadByPos(x, y)

    local mchan = love.thread.getChannel("msg")
    mchan:push("getobject")
    mchan:push(x)
    mchan:push(y)

    local rchan = love.thread.getChannel("request" .. threadNum)
    -- FIXME demand не дает ответа за таймаут и вешает программу
    local sobject = rchan:demand(0.1) as string

    if not sobject then
        return nil
    end

    --local objectfun, err: function, boolean = serpent.load(sobject)
    local ok, objectfun: boolean, function = serpent.load(sobject)

    if not ok then
        --logferror("Could'not deserialize cell object %s", err)
        logferror("Could'not deserialize cell object")
        return nil
    end

    return objectfun() as Cell
end

function Simulator.setMode(m: SimulatorMode)
    --assert(m == "step" or m == "continuos")
    mode = m
    print("push", mode)
    pushMsg2Threads(mode)
end

function Simulator.getMode(): SimulatorMode
    return mode
end

function Simulator.doStep()
    pushMsg2Threads("step")
end

function Simulator.getStatistic(): Statistic
    return statistic
end

function Simulator.getSchema(): {MtSchema}
    return mtschema
end

function Simulator.getGridSize(): number
    return gridSize
end

return Simulator

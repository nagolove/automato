local type Map = {string: boolean}
local type Seq = {number}

local a: Seq = {1, 2, 3}
local b: Map = {
    hi = -1 or false,
    lo = 1 or true,
}

function printMap(m: Map)
    for k, v in pairs(m) do
        printLog(k, v)
    end
end

function printSeq(arr: Seq)
    for k, v in ipairs(arr) do
        printLog(k, v)
    end
end

printSeq(a)
printMap(b)


function copy<T>(t:T):T
    --if t is table then 
        local result = {}
        for k, v in pairs(t as {any: any}) do
            result[k] = v
        end
        return result as T
    --end
    --return t
end

--local commands: {string: function(any)} = {}
--local commands: {string: function} = {}
--local commands: {string: function} = {}

--commands["do3"] = function()
    --print("do3")
--end

--function commands.do1() print("do1") end
--function commands.do2() print("do2") end

--function process(cmd: string)
    --if cmd then
        --local command = commands[cmd]
        --if command then
            --command()
        --end
    --end
--end

local type Commands = record
    do1: function()
    do2: function()
    do3: function()
end

local type Cmds = enum
    "do1"
    "do2"
    "do3"
end

local commands: Commands = {}

commands["do3"] = function()
    printLog("do3")
end

function commands.do1() print("do1") end
function commands.do2() print("do2") end

function process(cmd: Cmds)
    if cmd then
        local command: function() = commands[cmd]
        if command then
            command()
        end
    end
end

function zoo(): string, number
    return "blah", -1
end

function goo(s: string)
    printLog(s)
end

--goo(zoo as string)
goo(zoo as string)

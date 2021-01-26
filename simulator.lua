local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local inspect = require("inspect")
local serpent = require("serpent")


package.path = "./scenes/automato/?.lua;" .. package.path
print("package.path", package.path)

require("love")
require("external")
require("log")
require("types")
require("mtschemes")

local threads = {}
local gridSize
local mtschema


local threadCount = -1


local mode = "stop"

local statistic = {}

function Simulator.getDrawLists()
   local list = {}
   for k, _ in ipairs(threads) do
      local chan = love.thread.getChannel("data" .. k)
      if chan then
         local sublist = chan:demand(0.1)
         if sublist then
            for _, v1 in ipairs(sublist) do
               table.insert(list, v1)
            end
         end
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



end

local function pushMsg2Threads(t)
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

function love.threaderror(thread, errstr)
   print("Some thread failed with " .. errstr)
end

function Simulator.create(commonSetup)
   print("--------------------------------------------")
   print("commonSetup", inspect(commonSetup))

   sendStopClearChannels()

   threadCount = commonSetup.threadCount
   print("threadCount", threadCount)

   gridSize = commonSetup.gridSize

   mtschema = require("mtschemes")[threadCount]
   print("mtschema", inspect(mtschema))

   if not mtschema then
      error(string.format("Unsupported scheme for %d threads.", threadCount))
   end

   for i = 1, threadCount do
      local setupName = "setup" .. i
      love.thread.getChannel(setupName):push(commonSetup)
      love.thread.getChannel(setupName):push(serpent.dump(mtschema[i]))

      local th = love.thread.newThread("scenes/automato/simulator-thread.lua")
      table.insert(threads, th)
      th:start(i)
      local errmsg = th:getError()
      if errmsg then

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
   local msg = logChan:pop()
   while msg do
      print(msg[1], msg[2])
      msg = logChan:pop()
   end
end

function Simulator.step()
   if mode == "stop" then
      return
   end










end


function Simulator.getIter()







   return 0
end


function Simulator.findThreadByPos(x, y)
   local ix, iy = math.floor(x / gridSize), math.floor(y / gridSize)
   local rx, ry = x % gridSize, y % gridSize





   return 1
end




function Simulator.getObject(x, y)
   local threadNum = Simulator.findThreadByPos(x, y)

   local mchan = love.thread.getChannel("msg")
   mchan:push("getobject")
   mchan:push(x)
   mchan:push(y)

   local rchan = love.thread.getChannel("request" .. threadNum)

   local sobject = rchan:demand(0.1)

   if not sobject then
      return nil
   end

   local objectfun, err = serpent.load(sobject)

   if err then
      logferror("Could'not deserialize cell object %s", err)
      return nil
   end

   return objectfun()
end

function Simulator.setMode(m)

   mode = m
   print("push", mode)
   pushMsg2Threads(mode)
end

function Simulator.getMode()
   return mode
end

function Simulator.doStep()
   pushMsg2Threads("step")
end

function Simulator.getStatistic()
   return statistic
end

function Simulator.getSchema()
   return mtschema
end

function Simulator.getGridSize()
   return gridSize
end

return Simulator

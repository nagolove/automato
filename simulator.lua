local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("log")

local inspect = require("inspect")
local serpent = require("serpent")
local timer = require("Timer")







package.path = "./scenes/automato/?.lua;" .. package.path
printLog("package.path", package.path)

require("log")
require("love")
require("mtschemes")
require("types")
require("common")


local infoTimer = timer.new()
local gridSize
local mtschema
local starttime = 0
local statistic = {}
local threads = {}
local statGatherDelay = 0.1

local threadCount = -1
local mode = "stop"
local channels = {}



local isdone = true
local setup
local colonyDied = false

local function extractDrawList(list, channel)

   if channel then
      local sublist



      if channel:getCount() > 1 then
         sublist = channel:pop()
      else
         sublist = channel:peek()
      end


      if channel:getCount() > 20 then
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

   end

end

function Simulator.getDrawLists()

   local list = {}
   list[#list + 1] = {}
   list[#list + 1] = {}
   for k, _ in ipairs(threads) do
      local drawlist = channels[k].drawlist
      local drawlist_fn = channels[k].drawlist_fn_



      extractDrawList(list[1], drawlist)
      extractDrawList(list[2], drawlist_fn)


   end

   return list
end















local function pushMsg2Threads(t)
   print('pushMsg2Threads()', tostring(t))
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


function love.threaderror(_, errstr)
   print("Some thread failed with " .. errstr)
end

local ThreadCreateCallback = {}
local function createThreads(
   threadCount,
   mtschema,
   commonSetup,
   cb)

   for i = 1, threadCount do
      print("Channels for thread", i)
      table.insert(channels, initChannels(i))

      channels[i].setup:performAtomic(function(channel)
         channel:push(commonSetup)
         channel:push(serpent.dump(mtschema[i]))
      end)

      local th = love.thread.newThread("scenes/automato/simulator-thread.lua")
      table.insert(threads, th)

      th:start(i)
      if cb then
         cb(th, i)
      end
      local errmsg = th:getError()
      if errmsg then

         print("Thread %s", errmsg)
      end
   end
end

function Simulator.create(commonSetup)
   print('commonSetup', inspect(commonSetup))

   love.filesystem.write('drawlist_fn.txt', "")

   setup = deepCopy(commonSetup)
   print("--------------------------------------------")

   print("commonSetup", inspect(commonSetup))

   if isdone == false then
      Simulator.shutdown()
   end


   threadCount = commonSetup.threadCount

   print("threadCount", threadCount)

   gridSize = commonSetup.gridSize
   commonSetup.cellId = 0

   local mainRng = love.math.newRandomGenerator()

   mainRng:setSeed(love.timer.getTime())

   commonSetup.rngState = mainRng:getState()

   mtschema = require("mtschemes")[threadCount]
   print("mtschema", inspect(mtschema))

   if not mtschema then
      error(string.format("Unsupported scheme for %d threads.", threadCount))
   end

   createThreads(threadCount, mtschema, commonSetup)

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
   infoTimer:every(statGatherDelay, function(_)



      local newstat = {}
      for i, _ in ipairs(threads) do
         local t
         if channels[i].stat:getCount() > 1 then
            t = channels[i].stat:pop()
         else
            t = channels[i].stat:peek()
         end

         if t then
            table.insert(newstat, t)
         end
      end
      statistic = newstat









   end)
end






function Simulator.isColonyDied()
   return colonyDied
end



function Simulator.findThreadByPos(x, y)
   local fract
   local _
   _, fract = math.modf(x)
   assert(fract == 0.0, string.format("x = %f", x))
   _, fract = math.modf(y)
   assert(fract == 0.0, string.format("y = %f", y))







   for k, v in ipairs(mtschema) do
      local x2, y2 = gridSize + gridSize * v.draw[1], gridSize + gridSize * v.draw[2]
      local x1, y1 = x2 - gridSize, y2 - gridSize


      if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
         return k
      end
   end
   return -1
end




function Simulator.getObject(x, y)
   local threadNum = Simulator.findThreadByPos(x, y)

   if threadNum == -1 then
      error(string.format("threadNum == -1 for %d, %d with schema %s", x, y, inspect(mtschema)))
   end















   channels[threadNum].msg:push("getobject")




   channels[threadNum].object_w:performAtomic(function(channel)
      channel:push(x)
      channel:push(y)
   end)




















   local sobject = channels[threadNum].object_r:demand(0.01)




   if not sobject then
      return nil
   end


   local ok, object = serpent.load(sobject)



   if not ok then

      logferror("Could'not deserialize cell object")
      return nil
   end



   return object
end

function Simulator.setMode(m)
   mode = m
   print("push", mode)
   print('Simulator.setMode', m)
   pushMsg2Threads(mode)
end

function Simulator.getMode()
   return mode
end

function Simulator.step()
   print('Simulator.step()')
   print('ppppppppppppppppppppppppppppppppppp')
   pushMsg2Threads("step")
end

function Simulator.getStatistic()
   return statistic
end

function Simulator.getSchema()
   return mtschema
end

function Simulator.update(dt)
   infoTimer:update(dt)
end

function Simulator.getGridSize()
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
         local stopped = channels[i].isstopped:pop()
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

function Simulator.getUptime()
   return love.timer.getTime() - starttime
end



























function Simulator.readState(data)
   print('Simulator.readState()')














   local decompData = love.data.decompress('string', 'zlib', data)
   print('#data', #data)
   print('#decompData', #decompData)
   local ok, store_any = serpent.load(decompData)
   local store = store_any

   if not ok then
      return false
   end

   print('store', store)
   love.filesystem.write('restore.txt', inspect(store))





   setup = deepCopy(store.setup)
   mtschema = store.mtschema

   infoTimer = timer.new()

   if isdone == false then
      Simulator.shutdown()
   end


   threadCount = tonumber(store.threadCount)
   print("threadCount", threadCount)




   local mainRng = love.math.newRandomGenerator()


   if setup.rngState then
      mainRng:setState(setup.rngState)
   else
      print('No rngState in store structure')
   end




   print("mtschema", inspect(mtschema))

   if not mtschema then
      error(string.format("Unsupported scheme for %d threads.", threadCount))
   end

   createThreads(
   setup.threadCount,
   mtschema,
   setup,
   function(_, i)
      channels[i].state:performAtomic(
      function(channel)
         channel:clear()
         channel:push(store['thread' .. tostring(i)])
      end)

      channels[i].msg:push('readstate')
   end)


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
   infoTimer:every(statGatherDelay, function(_)



      local newstat = {}
      for i, _ in ipairs(threads) do
         local t

         t = channels[i].stat:pop()




         if t then
            table.insert(newstat, t)
         end
      end
      statistic = newstat
   end)

   return true
end

function Simulator.writeState()








   for i = 1, threadCount do
      channels[i].msg:push('writestate')
   end


   local notwritten = 0

   local store = {
      setup = setup,
      mtschema = mtschema,

      threadCount = tostring(threadCount),
   }

   for i = 1, threadCount do
      local t1 = love.timer.getTime()

      local thread = channels[i].state:demand()
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

















   return love.data.compress("string", "zlib", fullData, 9)
end




return Simulator

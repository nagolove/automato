local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local inspect = require("inspect")
local serpent = require("serpent")
local struct = require("struct")
local timer = require("Timer")
local marshal = require('marshal')





package.path = "./scenes/automato/?.lua;" .. package.path
print("package.path", package.path)

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

function Simulator.getDrawLists()
   local list = {}
   for k, _ in ipairs(threads) do
      local drawlist = channels[k].drawlist

      if drawlist then

         local sublist

         if drawlist:getCount() > 1 then
            sublist = drawlist:pop()
         else
            sublist = drawlist:peek()
         end


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

   return list
end















local function pushMsg2Threads(t)
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

function Simulator.create(commonSetup)
   print('commonSetup', inspect(commonSetup))
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

   for i = 1, threadCount do
      print("Channels for thread", i)
      table.insert(channels, initChannels(i))

      channels[i].setup:push(commonSetup)
      channels[i].setup:push(serpent.dump(mtschema[i]))




      local th = love.thread.newThread("scenes/automato/simulator-thread.lua")
      table.insert(threads, th)
      th:start(i)
      local errmsg = th:getError()
      if errmsg then

         print("Thread %s", errmsg)
      end
   end



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
         print('channels[i].stat:getCount()', channels[i].stat:getCount())
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

   channels[threadNum].object_w:push(x)
   channels[threadNum].object_w:push(y)




















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
   pushMsg2Threads(mode)
end

function Simulator.getMode()
   return mode
end

function Simulator.step()
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

local function unpackState(data)
   local res = {}
   local threadNum = struct.unpack('<d', data)
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
      local len = struct.unpack('<d', s)
      local payload = string.sub(data, idx + intSize + 1, idx + intSize + len + 1)
      idx = idx + len + 1
      table.insert(res, payload)

      love.filesystem.write(string.format('unpack-%d.txt', i), payload)
   end

   return res
end

function Simulator.readState(data)













   print("readState")

   local decompData = love.data.decompress('string', 'zlib', data)
   local threadStates = unpackState(decompData)

   do
      return false
   end

   infoTimer = timer.new()

   if isdone == false then
      Simulator.shutdown()
   end


   print("threadCount", threadCount)




   local mainRng = love.math.newRandomGenerator()

   mainRng:setSeed(love.timer.getTime())



   mtschema = require("mtschemes")[threadCount]
   print("mtschema", inspect(mtschema))

   if not mtschema then
      error(string.format("Unsupported scheme for %d threads.", threadCount))
   end

   for i = 1, threadCount do
      print("Channels for thread", i)
      table.insert(channels, initChannels(i))


      channels[i].setup:push(serpent.dump(mtschema[i]))




      local th = love.thread.newThread("scenes/automato/simulator-thread.lua")
      table.insert(threads, th)
      th:start(i)
      local errmsg = th:getError()
      if errmsg then

         print("Thread %s", errmsg)
      end
   end



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



         print('channels[i].stat:getCount()', channels[i].stat:getCount())
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

   local t = {}
   local notwritten = 0





   local setupString = serpent.dump(setup)
   local mtschemaString = serpent.dump(mtschema)
   local threadCountString = tostring(threadCount)









   local function writeString(str)
      local len = struct.pack("<d", #str)
      table.insert(t, len)
      table.insert(t, str)
   end


   writeString(setupString)

   writeString(mtschemaString)

   writeString(threadCountString)

   for i = 1, threadCount do
      local t1 = love.timer.getTime()

      local thread = channels[i].state:demand()
      local t2 = love.timer.getTime()
      print('demand time', t2 - t1)

      if not thread then
         error("Could'not retrive string from thread")
      end


      writeString(thread)

      if not (thread and #thread ~= 0) then
         notwritten = notwritten + 1
      end
   end

   print('writestate by', threadCount, ' not written ', notwritten)

   local fullData = table.concat(t)

















   return love.data.compress("string", "zlib", fullData, 9)
end




return Simulator

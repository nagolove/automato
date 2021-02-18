local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local inspect = require("inspect")
local serpent = require("serpent")
local struct = require("struct")
local timer = require("Timer")





package.path = "./scenes/automato/?.lua;" .. package.path
print("package.path", package.path)

require("log")
require("love")
require("mtschemes")
require("types")

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

function Simulator.getDrawLists()
   local list = {}


   for k, _ in ipairs(threads) do
      local drawlist = channels[k].drawlist

      if drawlist then


         local sublist = drawlist:peek()
         if sublist then
            for _, v1 in ipairs(sublist) do
               table.insert(list, v1)
            end
            drawlist:pop()
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

   pushSync()

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
         local t = channels[i].stat:pop()
         if t then
            table.insert(newstat, t)
         end
      end
      statistic = newstat
   end)
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

   local mchan = love.thread.getChannel("msg" .. threadNum)
   mchan:push("getobject")
   mchan:push(x)
   mchan:push(y)



   local sobject = channels[threadNum].object:pop()



   if not sobject then
      return nil
   end


   local ok, object = serpent.load(sobject)



   if not ok then

      logferror("Could'not deserialize cell object")
      return nil
   end

   print("rchan:getCount()", channels[threadNum].object:getCount())
   print("object", inspect(object))
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

function Simulator.readState(data)








end

function Simulator.writeState()






   for i = 1, threadCount do


      channels[i].msg:push('writestate')
   end

   local t = {}

   local notwritten = 0





   for i = 1, threadCount do
      local t1 = love.timer.getTime()

      local st = channels[i].state:demand()
      local t2 = love.timer.getTime()
      print('demand time', t2 - t1)
      if st and #st ~= 0 then

         local len = struct.pack("<dd", i, #st)
         table.insert(t, len)
         table.insert(t, st)
      else
         notwritten = notwritten + 1
      end
   end
   print('writestate by', threadCount, ' not written ', notwritten)

   local fullData = table.concat(t)
















   return love.data.compress("string", "zlib", fullData, 9)
end




return Simulator

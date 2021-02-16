local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local load = _tl_compat and _tl_compat.load or load; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("love.filesystem")
require("log")
require("love.timer")
require("mtschemes")
require("types")
require("love")


love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")

require("mobdebug").start()

local threadNum = ...
print("thread", threadNum, "is running")

require('cell')

local inspect = require("inspect")
local serpent = require("serpent")
local struct = require("struct")
local maxDataChannelCount = 10
local randseed = love.timer.getTime()

local rng = love.math.newRandomGenerator(randseed)

local istate


local cells = {}



local grid = {}

local gridSize

local codeLen

local cellsNum

local iter = 0

local stat = {}

local meals = {}

local stop = false

local schema

local drawCoefficients

local doStep = false

local checkStep = false

local commands = {}

local lastEmitIter = 0

local emitInvSpeed = 100

local logName = string.format("thread%d.txt", threadNum)
print("logName", logName)

local ChannelsTypes = {

   "cellrequest",

   "drawlist",

   "msg",

   "object",

   "ready",

   "request",

   "state",
}

local function initChannels()
   print(string.format("--- Thread %d initialize channels. ---", threadNum))
   local result = {}
   for _, v in ipairs(ChannelsTypes) do
      local name = v .. tostring(threadNum)
      print("get", name)
      result[v] = love.thread.getChannel(name)
   end
   print("--- ---")
   return result
end

local channels = initChannels()
local cellActions = require("cell-actions")


local timestamp
local stepsCount = 0
local stepsPerSecond = 0



local free = false

local function getCodeValues()
   local codeValues = {}

   for k, _ in pairs(cellActions.actions) do








      table.insert(codeValues, k)
   end
   return codeValues
end

local codeValues = getCodeValues()
print("codeValues", inspect(codeValues))


local removed = {}
local experimentCoro


function genCode()
   local code = {}
   local len = #codeValues
   for i = 1, codeLen do
      table.insert(code, codeValues[rng:random(1, len)])
   end
   return code
end



function getFalseGrid()
   local res = {}
   for i = 1, gridSize do
      local t = {}
      for j = 1, gridSize do
         t[#t + 1] = {}
      end
      res[#res + 1] = t
   end
   return res
end

function updateGrid()
   for _, v in ipairs(cells) do
      grid[v.pos.x][v.pos.y] = v
   end
   for _, v in ipairs(meals) do
      grid[v.pos.x][v.pos.y] = v
   end
end



function gatherStatistic(cells)
   local maxEnergy = 0
   local minEnergy = istate.initialEnergy[2]
   local sumEnergy = 0


   for _, v in ipairs(cells) do
      if v.energy > maxEnergy then
         maxEnergy = v.energy
      end
      if v.energy < minEnergy then
         minEnergy = v.energy
      end
      sumEnergy = sumEnergy + v.energy
   end


   if sumEnergy == 0 then
      sumEnergy = 1
   end
   return {
      maxEnergy = maxEnergy,
      minEnergy = minEnergy,
      midEnergy = sumEnergy / #cells,
      allEated = cellActions.getAllEated(),
   }
end


function emitFoodInRandomPoint()
   local x = rng:random(1, gridSize)
   local y = rng:random(1, gridSize)
   local t = grid[x][y]

   if not t.energy then
      local self = {
         food = true,
         pos = { x = x, y = y },
      }
      table.insert(meals, self)
      grid[x][y] = self
      return true, grid[x][y]
   else
      return false, grid[x][y]
   end
end

local foodGenerationSpeed = 0.1
local accum = 0




function emitFood(_)






   while true do
      if istate.nofood then

         coroutine.yield()
      end

      accum = accum + foodGenerationSpeed

      if accum > 1 then
         accum = 0
         for i = 0, math.floor(accum) do

            local emited, _ = emitFoodInRandomPoint()
            if not emited then


            end
         end

      end
      coroutine.yield()
   end
end




















function updateCells(cells)
   local alive = {}
   for _, cell in ipairs(cells) do
      local isalive = cell:update()
      if isalive then
         table.insert(alive, cell)
      else
         table.insert(removed, cell)

         stat.died = stat.died + 1
      end
   end
   return alive
end







































local function genPosition()
   local cx = 0
   local cy = 0
   local i, limit = 0, 1000
   while true do
      cx = rng:random(1, istate.gridSize)
      cy = rng:random(1, istate.gridSize)
      local len = dist(
      cx, cy,
      istate.spreadPoint.x, istate.spreadPoint.y)

      local ex1 = len < istate.spreadRad
      local ex2 = grid[cx][cy].food == nil
      local ex3 = grid[cx][cy].energy == nil;
      if ex1 and ex2 and ex3 then
         return cx, cy
      end
      i = i + 1
      if i > limit then
         break
      end
   end
   error("Could not generate position")
   return 0, 0
end




local function emitCell(iter)
   if threadNum == 1 then





   end
   if threadNum == 2 then



   end























   for i = 1, istate.cellsNum do
      local cx = rng:random(1, istate.gridSize)
      local cy = rng:random(1, istate.gridSize)
      table.insert(cells, Cell.new({ pos = { x = cx, y = cy } }))
   end
end

local function updateMeal(meal)
   local alive = {}
   for _, dish in ipairs(meal) do
      if dish.food == true then
         table.insert(alive, dish)
      end
   end
   return alive
end

local function experiment()
   local cellEmitCoro = coroutine.create(emitCell)
   local emitFoodCoro = coroutine.create(emitFood)

   iter = 0
   lastEmitIter = 0

   grid = getFalseGrid()
   updateGrid()
   stat = gatherStatistic(cells)

   coroutine.yield()
   coroutine.resume(cellEmitCoro, iter)
   print("#Experiment started with", #cells)




   while true do


      if cellEmitCoro and not coroutine.resume(cellEmitCoro, iter) then
         cellEmitCoro = nil
      end

      if emitFoodCoro and not coroutine.resume(emitFoodCoro, iter) then
         emitFoodCoro = nil
      end


      cells = updateCells(cells)


      meals = updateMeal(meals)


      grid = getFalseGrid()


      updateGrid()


      stat = gatherStatistic(cells)

      iter = iter + 1





      coroutine.yield()
   end

   print("there is no cells in simulation")



end

local experimentErrorPrinted = false


local function getGrid()
   return grid
end

local function pushDrawList()
   local drawlist = {}
   for _, v in ipairs(cells) do
      table.insert(drawlist, {
         x = v.pos.x + gridSize * drawCoefficients[1],
         y = v.pos.y + gridSize * drawCoefficients[2],
      })
      if v.color then
         drawlist[#drawlist].color = shallowCopy(v.color)
      end
   end
   for _, v in ipairs(meals) do
      table.insert(drawlist, {
         x = v.pos.x + gridSize * drawCoefficients[1],
         y = v.pos.y + gridSize * drawCoefficients[2],
         food = true,
      })
   end


   if channels.data:getCount() < maxDataChannelCount then
      channels.data:push(drawlist)
   end
end

function commands.info()
   local info = {
      cells = #cells,
      meals = #meals,
      stepsPerSecond = stepsPerSecond,
   }
   channels.request:push(serpent.dump(info))
end

function commands.stop()
   print("stop command, break main cycle")
   stop = true
end

function commands.getobject()
   local x, y = channels.msg:pop(), channels.msg:pop()
   print("commands.getobject", x, y)
   local ok, errmsg = pcall(function()
      if grid then
         local cell = grid[x][y]
         if cell then

            local dump = serpent.dump(cell)
            print("dump", dump)
            channels.object:push(dump)
         end
      end
   end)
   if not ok then
      print("Error in getobject operation", errmsg)
   end
end

function commands.step()
   checkStep = true
   doStep = true
end

function commands.continuos()
   checkStep = false
end

local function writelog(...)
   local buf = ""
   for i = 1, select("#", ...) do
      buf = buf .. select(i, ...)
   end
   love.filesystem.append(logName, buf .. "\n")
end

function commands.isalive()
   local x, y = channels.msg:pop(), channels.msg:pop()
   if not x or not y or not threadNum then
      assert(string.format("x, y " .. x .. " " .. y .. " threadNum " .. threadNum))
   end





   local ok, errmsg = pcall(function()
      if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
         local cell = grid[x][y]
         writelog(string.format("cell %s", inspect(cell)))

         local state = false
         if cell.energy and cell.energy > 0 then
            state = true
         end
         writelog(string.format("pushed state %s", state))

         channels.cellrequest:push(state)
      end
   end)
   if not ok then
      error("isalive error: " .. errmsg)
   end
end

function commands.insertcell()
   local newcellfun, err = load(channels.msg:pop())
   if err then
      error(string.format("insertcell %s", err))
   end
   local newcell = newcellfun()
   newcell.id = istate.cellId
   istate.cellId = istate.cellId + 1


   table.insert(cells, newcell)
end

function commands.writestate()
   local opts = { fatal = true }
   local cellsStr = serpent.dump(cells, opts)
   local mealsStr = serpent.dump(meals, opts)
   local result = {}

   local lenMarker = struct.pack("<ddd", threadNum, #cellsStr, #mealsStr)
   table.insert(result, lenMarker)
   table.insert(result, cellsStr)
   table.insert(result, mealsStr)

   channels.state:push(table.concat(result))
end

local function popCommand()
   local cmd
   repeat
      cmd = channels.msg:pop()
      if cmd then
         local command = commands[cmd]
         if command then
            command()
         else

            logerror(string.format("Unknown command '%s'", cmd))

         end
      end
   until not cmd
end

local function doSetup()
   local setupName = "setup" .. threadNum
   istate = love.thread.getChannel(setupName):pop()
   istate.rg = rng

   if istate.mode == "step" then
      commands.step()
   elseif istate.mode == "continuos" then
      commands.continuos()
   end

   print("thread", threadNum)
   print("istate", inspect(istate))

   gridSize = istate.gridSize
   codeLen = istate.codeLen
   cellsNum = istate.cellsNum
   emitInvSpeed = istate.emitInvSpeed

   local sschema = love.thread.getChannel(setupName):pop()

   local schemafun, err = load(sschema)
   if err then
      error("Could'not get schema for thread")
   end
   local schemaRestored = schemafun()
   print("schemaRestored", inspect(schemaRestored))
   schema = shallowCopy(schemaRestored)

   drawCoefficients = shallowCopy(schemaRestored.draw)

   print("schema", inspect(schema))
   print("drawCoefficients", inspect(drawCoefficients))

   experimentCoro = coroutine.create(function()
      local ok, errmsg = pcall(experiment)
      if not ok then
         logferror("Error in experiment pcall '%s'", errmsg)
      end
   end)


   coroutine.resume(experimentCoro)

   cellActions.init({
      threadNum = threadNum,
      getGrid = getGrid,
      gridSize = gridSize,
      initCell = Cell.new,
      schema = schema,
      foodenergy = istate.foodenergy,
      popCommand = popCommand,
      writelog = writelog,
   })




   istate.rg = rng
   istate.cellActions = cellActions.actions
   cellInitInternal(istate)
end

local function step()
   local newtimestamp = love.timer.getTime()
   if newtimestamp - timestamp >= 1 then
      stepsPerSecond = stepsCount
      stepsCount = 0
      timestamp = newtimestamp
   end

   local ok, errmsg = coroutine.resume(experimentCoro)
   stepsCount = stepsCount + 1

   if not ok and not experimentErrorPrinted then
      experimentErrorPrinted = true
      free = true
      print(string.format("coroutine error %s", errmsg))
   end
end

local function main()
   local syncChan = love.thread.getChannel("sync")
   channels.ready:push("ready")
   timestamp = love.timer.getTime()
   while not stop do
      popCommand()

      if not free then
         if checkStep then
            if doStep then
               step()
            end
            love.timer.sleep(0.002)
         else
            step()
         end
         pushDrawList()

         local _ = syncChan:demand(0.001)




         doStep = false

         local iterChan = love.thread.getChannel("iter")
         iterChan:push(iter)
      else
         love.timer.sleep(0.002)
      end
   end
   channels.ready:clear()
   channels.ready:push("free")
end

doSetup()
main()

print("thread", threadNum, "done")

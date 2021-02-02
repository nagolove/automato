local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local load = _tl_compat and _tl_compat.load or load; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("mobdebug").start()
local threadNum = ...
print("thread", threadNum, "is running")

require("love.filesystem")
require("love")

local inspect = require("inspect")
local serpent = require("serpent")



love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")

require("external")
require("log")
require("love.timer")
require("mtschemes")
require("types")

local maxDataChannelCount = 10

local randseed = love.timer.getTime()
math.randomseed(randseed)



local initialSetup


local cells = {}




local grid = {}

local gridSize

local codeLen

local cellsNum

local iter = 0

local statistic = {}

local meal = {}

local stop = false

local schema

local drawCoefficients

local doStep = false

local checkStep = false

local commands = {}

local logName = string.format("thread%d.txt", threadNum)
print("logName", logName)



local msgChan = love.thread.getChannel("msg" .. threadNum)
local readyChan = love.thread.getChannel("ready" .. threadNum)
local dataChan = love.thread.getChannel("data" .. threadNum)
local requestChan = love.thread.getChannel("request" .. threadNum)
local cellrequestChan = love.thread.getChannel("cellrequest" .. threadNum)
local objectChan = love.thread.getChannel("object" .. threadNum)

local cellActions = require("cell-actions")

local timestamp
local stepsCount = 0
local stepsPerSecond = 0

local function getCodeValues()
   local codeValues = {}
   for k, _ in pairs(cellActions.actions) do








      table.insert(codeValues, k)
   end
   return codeValues
end

local codeValues = getCodeValues()
print("codeValues", inspect(codeValues))

local actions
local removed = {}
local experimentCoro


function genCode()
   local code = {}
   local len = #codeValues
   for i = 1, codeLen do
      table.insert(code, codeValues[math.random(1, len)])
   end
   return code
end

local cellId = 0



function initCell(t)
   t = t or {}
   local self = {}
   self.pos = {}
   if t.pos and t.pos.x then
      self.pos.x = t.pos.x
   else
      self.pos.x = math.random(1, gridSize)
   end
   if t.pos and t.pos.y then
      self.pos.y = t.pos.y
   else
      self.pos.y = math.random(1, gridSize)
   end
   if t.code then
      self.code = copy(t.code)
   else
      self.code = genCode()
   end
   self.ip = 1
   self.id = cellId
   cellId = cellId + 1
   self.energy = math.random(initialSetup.initialEnergy[1], initialSetup.initialEnergy[2])



   table.insert(cells, self)
   return self
end

function updateCell(cell)

   if cell.ip >= #cell.code then
      cell.ip = 1
   end

   if cell.energy > 0 then
      local code = cell.code[cell.ip]




      local isremoved = not actions[code](cell)



      cell.ip = cell.ip + 1
      cell.energy = cell.energy - initialSetup.denergy
      return isremoved, cell
   else
      print("cell died with energy", cell.energy, "moves", inspect(cell.moves))
      return false, cell
   end
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
   for _, v in ipairs(meal) do
      grid[v.pos.x][v.pos.y] = v
   end
end



function gatherStatistic(cells)
   local maxEnergy = 0
   local minEnergy = initialSetup.initialEnergy[2]
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
   local x = math.random(1, gridSize)
   local y = math.random(1, gridSize)
   local t = grid[x][y]

   if not t.energy then
      local self = {
         food = true,
         pos = { x = x, y = y },
      }
      table.insert(meal, self)
      grid[x][y] = self
      return true, grid[x][y]
   else
      return false, grid[x][y]
   end
end


function emitFood(iter)
   if initialSetup.nofood then
      return
   end


   for i = 1, math.log(iter) * 10 do
      local emited, _ = emitFoodInRandomPoint()
      if not emited then


      end
   end
end





















function updateCells(cells)
   local alive = {}
   for _, cell in ipairs(cells) do
      local isalive, c = updateCell(cell)
      if isalive then
         table.insert(alive, c)
      else
         table.insert(removed, c)

      end
   end
   return alive
end

local function initCellOneCommandCode(command, steps)
   local cell = initCell()
   print("cell.energy", cell.energy)
   cell.code = {}
   for i = 1, steps do
      table.insert(cell.code, command)
   end

   return cell
end




























function initialEmit(iter)














   if threadNum == 1 then





   end
   if threadNum == 2 then



   end


   for i = 1, cellsNum do
      initCell()
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

function experiment()
   local initialEmitCoro = coroutine.create(initialEmit)

   grid = getFalseGrid()
   updateGrid()
   statistic = gatherStatistic(cells)

   coroutine.yield()

   print("hello from coro")
   print("#cells", #cells)

   coroutine.resume(initialEmitCoro)
   print("start with", #cells, "cells")


   while true do










      emitFood(iter)


      cells = updateCells(cells)


      meal = updateMeal(meal)


      grid = getFalseGrid()


      updateGrid()




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
   for _, v in ipairs(meal) do
      table.insert(drawlist, {
         x = v.pos.x + gridSize * drawCoefficients[1],
         y = v.pos.y + gridSize * drawCoefficients[2],
         food = true,
      })
   end

   if dataChan:getCount() < maxDataChannelCount then
      dataChan:push(drawlist)
   end
end

function commands.info()
   local info = {
      cells = #cells,
      meals = #meal,
      stepsPerSecond = stepsPerSecond,
   }
   requestChan:push(serpent.dump(info))
end

function commands.stop()
   print("stop command, break main cycle")
   stop = true
end

function commands.getobject()
   local x, y = msgChan:pop(), msgChan:pop()
   print("commands.getobject", x, y)
   local ok, errmsg = pcall(function()
      if grid then
         local cell = grid[x][y]
         if cell then

            local dump = serpent.dump(cell)
            print("dump", dump)
            objectChan:push(dump)
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
   local x, y = msgChan:pop(), msgChan:pop()
   if not x or not y or not threadNum then
      assert(string.format("x, y " .. x .. " " .. y .. " threadNum " .. threadNum))
   end
   print(x, y, threadNum)
   print(type(x), type(y), type(threadNum))
   writelog(string.format("isalive %d x, y %d %d", threadNum, x, y))
   local ok, errmsg = pcall(function()
      if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
         local cell = grid[x][y]
         writelog(string.format("cell %s", inspect(cell)))

         local state = false
         if cell.energy and cell.energy > 0 then
            state = true
         end
         writelog(string.format("pushed state %s", state))

         cellrequestChan:push(state)
      end
   end)
   if not ok then
      error(errmsg)
   end
end

function commands.insertcell()
   local newcellfun, err = load(msgChan:pop())
   if err then
      error(string.format("insertcell %s", err))
   end
   local newcell = newcellfun()
   newcell.id = cellId
   cellId = cellId + 1
   table.insert(cells, newcell)
end

local function popCommand()
   local cmd
   repeat
      cmd = msgChan:pop()

      if cmd then
         local command = commands[cmd]
         if command then
            command()
         else
            error(string.format("Unknown command '%s'", cmd))
         end
      end
   until not cmd
end

local function doSetup()
   local setupName = "setup" .. threadNum
   initialSetup = love.thread.getChannel(setupName):pop()

   if initialSetup.mode == "step" then
      commands.step()
   elseif initialSetup.mode == "continuos" then
      commands.continuos()
   end

   print("thread", threadNum)
   print("initialSetup", inspect(initialSetup))

   gridSize = initialSetup.gridSize
   codeLen = initialSetup.codeLen
   cellsNum = initialSetup.cellsNum


   local sschema = love.thread.getChannel(setupName):pop()

   local schemafun, err = load(sschema)
   if err then
      error("Could'not get schema for thread")
   end
   local schemaRestored = schemafun()
   print("schemaRestored", inspect(schemaRestored))
   schema = flatCopy(schemaRestored)

   drawCoefficients = flatCopy(schemaRestored.draw)

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
      initCell = initCell,
      schema = schema,
      foodenergy = initialSetup.foodenergy,
      popCommand = popCommand,
      writelog = writelog,
   })


   actions = cellActions.actions
end



local free = false

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
   readyChan:push("ready")
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

         local syncMsg = syncChan:demand(0.001)




         doStep = false

         local iterChan = love.thread.getChannel("iter")
         iterChan:push(iter)
      else
         love.timer.sleep(0.002)
      end
   end
   readyChan:clear()
   readyChan:push("free")
end

doSetup()
main()

print("thread", threadNum, "done")

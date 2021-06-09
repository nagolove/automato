local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local load = _tl_compat and _tl_compat.load or load; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("love.filesystem")
require("log")
require("love.timer")
require("mtschemes")
require("types")
require("love")
require("love.math")
require('cell')
require('log')





require("mobdebug").start()

local threadNum = ...
printLog("thread", threadNum, "is running")

local inspect = require("inspect")
local serpent = require("serpent")


local secondDelay = 1
local rng

local istate


local cells = {}



local grid = {}

local gridSize

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

local emitInvSpeed = 100.

local logName = string.format("thread%d.txt", threadNum)
printLog("logName", logName)





local channels = initChannels(threadNum)


for k, v in ipairs(ChannelsTypes) do
   printLog("v", v, 'k', k)
end
printLog("channels", inspect(channels))

local cellActions = require("cell-actions")


local timestamp
local stepsCount = 0
local stepsPerSecond = 0




local free = false

local removed = {}
local experimentCoro



function getFalseGrid()
   local res = {}
   for _ = 1, gridSize do
      local t = {}
      for _ = 1, gridSize do
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
   local maxEnergy = 0.0

   local minEnergy = 100000000.0
   local sumEnergy = 0.0
   local square = gridSize * gridSize
   local i = 0


   for _, v in ipairs(cells) do
      if v.energy and v.energy > 0 then
         i = i + 1
      end
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


   local midEnergy
   if #cells == 0 then
      midEnergy = 0
      minEnergy = 0
   else
      midEnergy = sumEnergy / #cells
   end

   stat.allEated = cellActions.getAllEated()
   stat.maxEnergy = maxEnergy
   stat.minEnergy = minEnergy
   stat.midEnergy = midEnergy
   stat.cells = #cells
   stat.meals = #meals
   stat.percentAreaFilled = i / square
   stat.iterations = iter
end


function emitFoodInRandomPoint()

   local x = math.floor(rng:random(1, gridSize))
   local y = math.floor(rng:random(1, gridSize))
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
local accum = 0.





function emitFood(_)
   if istate.nofood then
      return

   end

   while true do
      accum = accum + foodGenerationSpeed

      for _ = 0, math.floor(math.log(iter)) do


         emitFoodInRandomPoint()






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
      end
   end
   return alive
end







































local function genPosition()
   local cx = 0.
   local cy = 0.
   local i, limit = 0, 1000
   while true do
      cx = rng:random(1, istate.gridSize)
      cy = rng:random(1, istate.gridSize)
      local len = dist(
      cx, cy,
      istate.spreadPoint.x, istate.spreadPoint.y)

      local ex1 = len < istate.spreadRad
      local ex2 = grid[math.floor(cx)][math.floor(cy)].food == nil
      local ex3 = grid[math.floor(cx)][math.floor(cy)].energy == nil;
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




local function emitCell(_)
























   if istate.emitFlags == 'normal' then
      for _ = 1, istate.cellsNum do
         local cx, cy = genPosition()



         table.insert(
         cells,
         Cell.new({ pos = { x = cx, y = cy } }))

         coroutine.yield()
      end
   elseif istate.emitFlags == 'directions_only' then
      local cx, cy = genPosition()
      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = cx, y = cy },
         code = { 'left' },
      }))


      cx, cy = genPosition()
      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = cx, y = cy },
         code = { 'right' },
      }))


      cx, cy = genPosition()
      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = cx, y = cy },
         code = { 'up' },
      }))


      cx, cy = genPosition()
      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = cx, y = cy },
         code = { 'down' },
      }))


   elseif istate.emitFlags == 'divide_only' then
      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = 20, y = 20 },
         wantdivide = 0,
         code = { 'wantdivide', 'cross' },
      }))


      table.insert(
      cells,
      Cell.new(
      {
         pos = { x = 21, y = 20 },
         wantdivide = 0,
         code = { 'wantdivide', 'cross' },
      }))


   end

   coroutine.yield()
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
   local emitCellCoro = coroutine.create(emitCell)
   local emitFoodCoro = coroutine.create(emitFood)

   iter = 0
   lastEmitIter = 0

   grid = getFalseGrid()
   updateGrid()

   stat = {
      allEated = 0,
      maxEnergy = 0,
      minEnergy = 0,
      midEnergy = 0,
      cells = 0,
      iterations = 0,
      meals = 0,
      born = 0,
      died = 0,
      percentAreaFilled = 0,
   }

   coroutine.yield()
   local ok, errmsg = coroutine.resume(emitCellCoro, iter)
   if not ok then
      error(errmsg)
      stop = true
   end
   printLog("#Experiment started with", #cells)



   while true do

      local emitok, msg = pcall(function()

         if emitCellCoro and not coroutine.resume(emitCellCoro, iter) then
            emitCellCoro = nil
         end

         if emitFoodCoro and not coroutine.resume(emitFoodCoro, iter) then
            emitFoodCoro = nil
         end
      end)
      if not emitok then
         printLog('emit pcall error ' .. msg)
      end


      cells = updateCells(cells)


      meals = updateMeal(meals)


      grid = getFalseGrid()


      updateGrid()

      if #cells == 0 then
         channels.colonystatus:push("nocellsincolony")
      end



      gatherStatistic(cells)




      channels.stat:push(stat)

      iter = iter + 1


      coroutine.yield()
   end

   printLog("there is no cells in simulation")



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
   channels.drawlist:push(drawlist)
end

function commands.stop()
   printLog("stop command, break main cycle")
   stop = true
end

function commands.getobject()
   local x, y
   x = channels.object_w:pop()
   y = channels.object_w:pop()
   local ok, _ = pcall(function()
      if grid then
         local cell = grid[math.floor(x)][math.floor(y)]
         if cell then
            local dump = serpent.dump(cell)
            channels.object_r:push(dump)
         end
      end
   end)
   if not ok then


   end
end

function commands.step()
   checkStep = true
   doStep = true


   stepsPerSecond = stepsCount
   stepsCount = 0
end

function commands.continuos()
   printLog('commands.continuos')
   checkStep = false
end

function commands.isalive()
   local x, y = channels.alive:pop(), channels.alive:pop()
   if type(x) ~= 'number' or type(y) ~= 'number' then
      assert(string.format("x, y " .. x .. " " .. y .. " threadNum " .. threadNum))
   end

   local ok, errmsg = pcall(function()
      if x >= 1 and x <= gridSize and y >= 1 and y <= gridSize then
         local cell = grid[math.floor(x)][math.floor(y)]

         local state = false
         if cell.energy and cell.energy > 0 then
            state = true
         end
         channels.cellrequest:push(state)
      end
   end)

   if not ok then
      error("isalive error: " .. errmsg)
   end
end


function commands.insertcell()
   local msg = channels.cells:pop()

   if msg then
      local newcellfun, err = load(msg)
      if (not newcellfun) and err then
         error(string.format("insertcell '%s', msg = '%s'", err, msg))
      end
      local newcell = newcellfun()
      newcell = setmetatable(newcell, { __index = Cell })
      newcell.id = istate.cellId
      istate.cellId = istate.cellId + 1


      table.insert(cells, newcell)
   end
end

function commands.readstate()
   local state = channels.state:demand()
   local ok, store = serpent.load(state)
   printLog('commands.readstate()', inspect(store))
   if not ok then
      printLog("commands.readstate() could'not load state")
      return
   end

   cells = (store).cells
   meals = (store).meals
   schema = (store).schema
   istate = (store).istate
   istate.rng = love.math.newRandomGenerator()
   istate.rng:setState(istate.rngState)
end

function commands.writestate()
   printLog('commands.writestate')

   local store = {
      cells = cells,
      meals = meals,
      schema = schema,
      istate = istate,
   }

   local data = serpent.dump(store, { fatal = true })
   love.filesystem.write('data.txt', data)
   channels.state:push(data)
end

local function clearLogs()
   love.filesystem.write(string.format('commands-thread-%d.log.txt', threadNum), "")
end

local function popCommand()
   local cmd
   repeat
      cmd = channels.msg:pop()
      local logstr = string.format('iter %d msg %s\n', iter, cmd)
      love.filesystem.append(string.format('commands-thread-%d.log.txt', threadNum), logstr)
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

   printLog('\\\\\\\\\\\\\\\\')
   for k, v in pairs(channels) do
      printLog(k, v)
   end
   printLog('\\\\\\\\\\\\\\\\')

   istate = channels.setup:pop()
   if not istate then
      error("No setup for thread " .. threadNum)
   end

   rng = love.math.newRandomGenerator()
   rng:setState(istate.rngState)
   istate.rng = rng

   if istate.mode == "step" then
      commands.step()
   elseif istate.mode == "continuos" then
      commands.continuos()
   end

   printLog("thread", threadNum)
   printLog("istate", inspect(istate))

   gridSize = istate.gridSize
   cellsNum = istate.cellsNum
   emitInvSpeed = istate.emitInvSpeed

   local sschema = channels.setup:pop()

   local schemafun, err = load(sschema)
   if err then
      error("Could'not get schema for thread")
   end

   local schemaRestored = schemafun()
   printLog("schemaRestored", inspect(schemaRestored))
   schema = shallowCopy(schemaRestored)

   drawCoefficients = shallowCopy(schemaRestored.draw)

   printLog("schema", inspect(schema))
   printLog("drawCoefficients", inspect(drawCoefficients))

   experimentCoro = coroutine.create(experiment)


   coroutine.resume(experimentCoro)

   cellActions.init({
      threadNum = threadNum,
      getGrid = getGrid,
      gridSize = gridSize,
      initCell = Cell.new,
      schema = schema,
      foodenergy = istate.foodenergy,
      popCommand = popCommand,
      writelog = printLog,
      rng = istate.rng,

      setStepMode = commands.step,
      channels = channels,
   })


   istate.cellActions = cellActions.actions
   cellInitInternal(istate, stat)
end

local function step()

   local newtimestamp = love.timer.getTime()
   if newtimestamp - timestamp >= secondDelay then
      stepsPerSecond = stepsCount
      stepsCount = 0
      timestamp = newtimestamp
   end

   local ok, errmsg = coroutine.resume(experimentCoro)
   stepsCount = stepsCount + 1



   if not ok then
      experimentErrorPrinted = true
      free = true
      error(string.format("coroutine error %s", errmsg))
   end
end

local function main()
   timestamp = love.timer.getTime()
   local __step_done = false
   while not stop do
      __step_done = false
      popCommand()
      if not free then
         if checkStep then
            if doStep then
               step()
               __step_done = true
            end
            love.timer.sleep(0.001)
         else
            step()
            __step_done = true
         end

         channels.drawlist_fn:performAtomic(function(channel)
            for _ = 1, 100 do
               local node = {}
               node.x = math.floor(rng:random(1, 100))
               node.y = math.floor(rng:random(1, 100))
               node.color = { 0.5, 0.7, 0.2 }
               channel:push(node)
            end
         end)

         pushDrawList()
         doStep = false
      else
         love.timer.sleep(0.001)
      end
   end
end

clearLogs()
doSetup()
main()

channels.isstopped:push(true)

printLog("thread", threadNum, "done")

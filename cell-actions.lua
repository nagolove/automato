local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("types")
require("mtschemes")
require("love")
require("common")

local inspect = require("inspect")
local serpent = require("serpent")


local getGrid


local gridSize


local actions = {}


local ENERGY = 10


local initCell


local allEated = 0



local schema


local curThreadNum


local function isAlive(x, y)
   local t = getGrid()[x][y]
   return t.energy and t.energy > 0
end


local setup = {}

local maxSavedPositions = 64

local writelog


local function pushPosition(cell)
   if not cell.moves then
      cell.moves = {}
   end
   local moves = cell.moves
   if #moves >= 2 then
      local lastX, lastY = moves[#moves - 1], cell.moves[#moves]
      if lastX ~= cell.pos.x and lastY ~= cell.pos.y then
         if #moves > maxSavedPositions then
            table.remove(moves, 1)
            table.remove(moves, 2)
         end
         table.insert(moves, cell.pos.x)
         table.insert(moves, cell.pos.y)
      end
   else
      table.insert(cell.moves, cell.pos.x)
      table.insert(cell.moves, cell.pos.y)
   end
end

local requestThreadDemandTimeout = 0.02


local function isAliveNeighbours(x, y, threadNum)
   if not threadNum then
      error("no threadNum")
   end
   writelog(string.format("isAliveNeighbours(%d, %d, %d)", x, y, threadNum))



   local msgChan = love.thread.getChannel("msg" .. threadNum)
   msgChan:push("isalive")
   msgChan:push(x)
   msgChan:push(y)




   if threadNum == curThreadNum then
      return isAlive(x, y)
   else

      local threadName = "cellrequest" .. threadNum

      writelog("request to", threadName)

      local chan = love.thread.getChannel(threadName)
      local state = chan:demand(requestThreadDemandTimeout)


      local i = 0
      local limit = 500
      while not state do
         if i >= limit then
            error("Cycles limit reached.")
         end
         writelog("setup.popCommand")

         setup.popCommand()
         love.timer.sleep(0.01)
         state = chan:demand(requestThreadDemandTimeout)
         i = i + 1
      end

      writelog("state ", tostring(state))

      assert(state ~= nil, "no answer from " .. threadName .. " thread")
      return state


   end
end


local function moveCellToThread(cell, threadNum)



   local dump = serpent.dump(cell)
   local chan = love.thread.getChannel("msg" .. threadNum)
   chan:push("insertcell")
   print('moveCellToThread dump', inspect(dump))
   chan:push(dump)
end

function actions.left(cell)
   local res = true
   local pos = cell.pos
   pushPosition(cell)

   if pos.x > 1 and not isAlive(pos.x - 1, pos.y) then
      pos.x = pos.x - 1


   elseif pos.x <= 1 and not isAliveNeighbours(gridSize, pos.y, schema.l) then



      cell.pos.x = gridSize
      moveCellToThread(cell, schema.l)




      res = false
   end
   return res
end

function actions.right(cell)
   local res = true
   local pos = cell.pos
   pushPosition(cell)
   if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
      pos.x = pos.x + 1

   elseif pos.x >= gridSize and not isAliveNeighbours(1, pos.y, schema.r) then

      cell.pos.x = 1
      moveCellToThread(cell, schema.r)
      res = false
   end
   return res
end

function actions.up(cell)
   local res = true
   local pos = cell.pos
   pushPosition(cell)
   if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
      pos.y = pos.y - 1

   elseif pos.y <= 1 and not isAliveNeighbours(pos.x, gridSize, schema.u) then

      cell.pos.y = gridSize
      moveCellToThread(cell, schema.u)
      res = false
   end
   return res
end

function actions.down(cell)
   local res = true
   local pos = cell.pos
   pushPosition(cell)
   if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
      pos.y = pos.y + 1
   elseif pos.y >= gridSize and not isAliveNeighbours(pos.x, 1, schema.d) then

      cell.pos.y = 1
      moveCellToThread(cell, schema.d)
      res = false
   end
   return res
end


























































local around4 = {
   { 0, -1 },
   { -1, 0 }, { 1, 0 },
   { 0, 1 },
}

local around8 = {
   { -1, -1 }, { 0, -1 }, { 1, -1 },
   { -1, 0 }, { 1, 0 },
   { -1, 1 }, { 0, 1 }, { 1, 1 },
}

local function incEat(cell)
   if not cell.eated then
      cell.eated = 0
   end
   cell.eated = cell.eated + 1
   allEated = allEated + 1
end



function actions.eat8(cell)
   local res = true
   local nx, ny = cell.pos.x, cell.pos.y
   for _, displacement in ipairs(around8) do
      nx = nx + displacement[1]
      ny = ny + displacement[2]


      if nx >= 1 and nx <= gridSize and
         ny >= 1 and ny <= gridSize then
         local grid = getGrid()
         local dish = grid[nx][ny]

         if dish and dish.food then
            getGrid()[nx][ny].food = nil
            dish.energy = 0
            cell.energy = cell.energy + ENERGY
            incEat(cell)
            return res
         end
      end
   end
   return res
end


function actions.eat8move(cell)
   local res = true
   local pos = cell.pos
   local newt = shallowCopy(pos)
   for _, displacement in ipairs(around8) do
      newt.x = newt.x + displacement[1]
      newt.y = newt.y + displacement[2]


      if newt.x >= 1 and newt.x < gridSize and
         newt.y >= 1 and newt.y < gridSize then
         local dish = getGrid()[newt.x][newt.y]


         if dish.food then

            dish.food = nil
            dish.energy = 0
            cell.energy = cell.energy + ENERGY
            cell.pos.x = newt.x
            cell.pos.y = newt.y
            incEat(cell)
            return res
         end
      end
   end
   return res
end

 NeighboursCallback = {}










local function listNeighbours8(x, y, cb)
   for _, displacement in ipairs(around8) do
      local nx, ny = x + displacement[1], y + displacement[2]
      if nx >= 1 and nx <= gridSize and ny >= 1 and ny <= gridSize then
         if cb(nx, ny, getGrid()[nx][ny]) == false then
            break
         end
      end
   end
end

local function listNeighbours4(x, y, cb)
   for _, displacement in ipairs(around4) do
      local nx, ny = x + displacement[1], y + displacement[2]
      if nx >= 1 and nx <= gridSize and ny >= 1 and ny <= gridSize then
         if cb(nx, ny, getGrid()[nx][ny]) == false then
            break
         end
      end
   end
end
















































local function findFreePos4(x, y)
   local pos = {}
   listNeighbours4(x, y,
   function(xp, yp, value)
      if (not value.energy) and (not value.food) then
         pos.x = xp
         pos.y = yp
         return false
      end
      return true
   end)
   return pos.x ~= nil and pos.y ~= nil, pos
end





local function findFreePos8(x, y)
   local pos = {}
   listNeighbours8(x, y,
   function(xp, yp, value)
      if (not value.energy) and (not value.food) then
         pos.x = xp
         pos.y = yp
         return false
      end
      return true
   end)
   return pos.x ~= nil and pos.y ~= nil, pos
end


function actions.wantdivide(cell)
   local res = true
   if cell.energy > 0 then

      if cell.wantdivide and cell.wantdivide > 0 then
         return res
      end

      if setup.rng:random(1, 1000) == 1 then
         cell.wantdivide = setup.rng:random(1, 10)
         cell.color = { 1, 0, 0 }
      end
   end
   return res
end


function actions.cross(cell)
   local res = true

   if cell.wantdivide and cell.wantdivide > 0 and cell.energy > 0 then

      listNeighbours4(
      cell.pos.x,
      cell.pos.y,
      function(_, _, other)

         if other.wantdivide and
            other.wantdivide > 0 and
            other.energy > 0 then
            print("cell.pos", cell.pos.x, cell.pos.y)

            setup.setStepMode()


            local found, pos = findFreePos4(cell.pos.x, cell.pos.y)
            if found then
               local t = {
                  pos = { x = pos.x, y = pos.y },

                  code = {},
                  color = { 0.5, 0.5, 0.5 },
               }
               print(pos.x, pos.y)
               print(string.format("new cell at (%d, %d)", pos.x, pos.y))
               initCell(t)
               setup.setStepMode()
               return false
            end
         end
         return true
      end)

   end

   return res
end

local function init(t)

   curThreadNum = t.threadNum
   getGrid = t.getGrid
   gridSize = t.gridSize
   initCell = t.initCell
   schema = t.schema
   ENERGY = t.foodenergy
   setup = shallowCopy(t)

   writelog = t.writelog

   print("t", inspect(t))
   allEated = 0
end

return {
   actions = actions,
   init = init,
   getAllEated = function()
      return allEated
   end,
}

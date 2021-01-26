local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local table = _tl_compat and _tl_compat.table or table; require("external")
require("types")
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


local threadNum


local function isAlive(x, y)
   local t = getGrid()[x][y]
   return t.energy and t.energy > 0
end


local setup = {}


local function pushPosition(cell)
   if not cell.moves then
      cell.moves = {}
   end
   if #cell.moves >= 2 then
      local lastX, lastY = cell.moves[#cell.moves - 1], cell.moves[#cell.moves]
      if lastX ~= cell.pos.x and lastY ~= cell.pos.y then
         table.insert(cell.moves, cell.pos.x)
         table.insert(cell.moves, cell.pos.y)
      end
   else
      table.insert(cell.moves, cell.pos.x)
      table.insert(cell.moves, cell.pos.y)
   end
end


local function isAliveNeighbours(x, y, threadNum)
   local msgChan = love.thread.getChannel("msg" .. threadNum)
   msgChan:push("isalive")
   msgChan:push(x)
   msgChan:push(y)

   local state = love.thread.getChannel("request" .. threadNum):demand(0.1)
   print(state)
   assert(state ~= nil)
   return state
end


local function moveCellToThread(cell, threadNum)
   local dump = serpent.dump(cell)
   local chan = love.thread.getChannel("msg" .. threadNum)
   chan:push("insertcell")
   chan:push(dump)
end

function actions.left(cell)
   local pos = cell.pos
   pushPosition(cell)

   if pos.x > 1 and not isAlive(pos.x - 1, pos.y) then
      pos.x = pos.x - 1
   elseif pos.x <= 1 and not isAlive(gridSize, pos.y) then



      pos.x = gridSize

   end
end

function actions.right(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
      pos.x = pos.x + 1

   elseif pos.x >= gridSize and not isAliveNeighbours(1, pos.y, schema.r) then
      getGrid()[cell.pos.x][cell.pos.y].energy = 0
      pos.x = 1
      moveCellToThread(cell, schema.r)
   end
end

function actions.up(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
      pos.y = pos.y - 1

   elseif pos.y <= 1 and not isAliveNeighbours(pos.x, gridSize, schema.u) then
      getGrid()[cell.pos.x][cell.pos.y].energy = 0
      pos.y = gridSize
      moveCellToThread(cell, schema.u)
   end
end

function actions.down(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
      pos.y = pos.y + 1
   elseif pos.y >= gridSize and not isAliveNeighbours(pos.x, 1, schema.d) then
      getGrid()[cell.pos.x][cell.pos.y].energy = 0
      pos.y = 1
      moveCellToThread(cell, schema.d)
   end
end

function actions.left2(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.x > 1 and not isAlive(pos.x - 1, pos.y) then
      pos.x = pos.x - 1
   elseif pos.x <= 1 and not isAlive(gridSize, pos.y) then
      pos.x = gridSize
   end
end

function actions.right2(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.x < gridSize and not isAlive(pos.x + 1, pos.y) then
      pos.x = pos.x + 1
   elseif pos.x >= gridSize and not isAlive(1, pos.y) then
      pos.x = 1
   end
end

function actions.up2(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.y > 1 and not isAlive(pos.x, pos.y - 1) then
      pos.y = pos.y - 1
   elseif pos.y <= 1 and not isAlive(pos.x, gridSize) then
      pos.y = gridSize
   end
end

function actions.down2(cell)
   local pos = cell.pos
   pushPosition(cell)
   if pos.y < gridSize and not isAlive(pos.x, pos.y + 1) then
      pos.y = pos.y + 1
   elseif pos.y >= gridSize and not isAlive(pos.x, 1) then
      pos.y = 1
   end
end




function actions.popmem_pos(cell)
end

function actions.pushmem_pos(cell)


end

local around = {
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
   local nx, ny = cell.pos.x, cell.pos.y
   for _, displacement in ipairs(around) do
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
            return
         end
      end
   end
end


function actions.eat8move(cell)
   local pos = cell.pos
   local newt = copy(pos)
   for _, displacement in ipairs(around) do
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
            return
         end
      end
   end
end








 NeighboursCallback = {}

local function listNeighbours(x, y, cb)
   for _, displacement in ipairs(around) do
      local nx, ny = x + displacement[1], y + displacement[2]
      if nx >= 1 and nx < gridSize and ny >= 1 and ny < gridSize then
         if not cb(nx, ny, getGrid()[nx][ny]) then
            break
         end
      end
   end
end


local function mixCode(cell1, cell2)
   local rnd = math.random()
   local first, second
   if rnd > 0.5 then
      first, second = cell1, cell2
   else
      first, second = cell2, cell1
   end
   local newcode = {}
   local i = 1
   local pushed

   repeat
      pushed = false
      if i <= #cell1.code then
         table.insert(newcode, first.code[i])
         pushed = true
      end
      if i <= #cell2.code then
         table.insert(newcode, second.code[i])
         pushed = true
      end
      i = i + 1
   until not pushed

   return newcode
end

local function test_mixCode()
   math.randomseed(love.timer.getTime())
   print("mixCode", inspect(mixCode({ code = { "left", "right", "up" } },
   { code = { "eat", "eat", "eat" } })))

   print("mixCode", inspect(mixCode({ code = { "left", "right", "up" } },
   { code = { "eat", "eat" } })))

   print("mixCode", inspect(mixCode({ code = { "left", "right", "up" } },
   { code = { "eat", "eat", "down", "down", "down" } })))
end





local function findFreePos(x, y)
   local pos = {}
   listNeighbours(x, y, function(xp, yp, value)
      if (not value.energy) and (not value.food) then
         pos.x = xp
         pos.y = yp
         return true
      end
      return false
   end)
   return true, pos
end


function actions.cross(cell)



















end

local function init(t)

   threadNum = t.threadNum
   getGrid = t.getGrid
   gridSize = t.gridSize
   initCell = t.initCell
   schema = t.schema

   ENERGY = t.foodenergy




   setup = shallowCopy(t)

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

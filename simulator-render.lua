local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack; require("love")
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
package.path = package.path .. ";scenes/automato/?.lua"
require("imgui")
require("common")
require("types")

local gr = love.graphics
local inspect = require("inspect")

local mtschemes = require("mtschemes")

local sim = require("simulator")


 SimulatorRender = {}















local SimulatorRender_mt = {
   __index = SimulatorRender,
}


local pixSize = 10
local gridLineWidth = 1

function SimulatorRender.new(commonSetup, cam)
   local self = {
      commonSetup = shallowCopy(commonSetup),
      cam = cam,
   }
   return setmetatable(self, SimulatorRender_mt)
end

function SimulatorRender:p()
   print("hi")
end

function SimulatorRender:draw()

   self:drawGrid()
   self:drawCells()

end

function SimulatorRender:drawCells()
   print("SimulatorRender:drawCells")
   local drawlist = sim.getDrawLists()
   print("drawlist", inspect(drawlist))
   if drawlist then
      for _, v in ipairs(drawlist) do
         if v.food then
            gr.setColor(0, 1, 0)
            local x, y = (v.x - 1) * pixSize, (v.y - 1) * pixSize
            local w, h = pixSize, pixSize
            gr.rectangle("fill", x, y, w, h)
         else
            if v.color then
               gr.setColor(v.color)
            else
               gr.setColor(0.5, 0.5, 0.5)
            end
            local x, y = (v.x - 1) * pixSize, (v.y - 1) * pixSize
            local w, h = pixSize, pixSize
            gr.rectangle("fill", x, y, w, h)
         end
      end
   end
end

function SimulatorRender:drawGrid()
   gr.setColor(0.5, 0.5, 0.5)
   local gridSize = self.commonSetup.gridSize

   if not gridSize then
      return
   end

   local schema
   local ok, errmsg = pcall(function()
      schema = mtschemes[self.commonSetup.threadCount]
   end)
   if not ok then
      print("Could'not require 'mtschemes'", errmsg)
   end

   local oldWidth = { gr.getColor() }
   gr.setLineWidth(gridLineWidth)
   if schema then
      for _, v in pairs(schema) do
         local dx, dy = (v).draw[1] * pixSize * gridSize, (v).draw[2] * pixSize * gridSize
         for i = 0, gridSize do

            local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
            local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
            gr.line(x1, y1, x2, y2)

            x1, y1 = dx + 0, dy + i * pixSize
            x2, y2 = dx + gridSize * pixSize, dy + i * pixSize
            gr.line(x1, y1, x2, y2)
         end
      end
   else
      local dx, dy = 0, 0
      for i = 0, gridSize do

         gr.line(dx + i * pixSize, dy + 0, dx + i * pixSize, dy + gridSize * pixSize)

         gr.line(dx + 0, dy + i * pixSize, dx + gridSize * pixSize, dy + i * pixSize)
      end
   end
   gr.setLineWidth(_tl_table_unpack(oldWidth))
end

function SimulatorRender:getPixSize()
   return pixSize
end

function SimulatorRender:drawCellPath(cell)
   if cell and cell.moves and #cell.moves >= 4 then
      local pixels = self:getPixSize()
      local half = pixels / 2
      local prevx, prevy = cell.moves[1], cell.moves[2]
      local i = 3
      while i <= #cell.moves do
         gr.setColor(1, 0, 0)
         gr.line(prevx * pixels + half,
         prevy * pixels + half,
         cell.moves[i] * pixels + half,
         cell.moves[i + 1] * pixels + half)
         prevx, prevy = cell.moves[i], cell.moves[i + 1]
         i = i + 2
      end
   end
end

return SimulatorRender

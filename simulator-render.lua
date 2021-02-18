local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack; require("love")
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

local gridLineWidth = 3

local canvasmultfactor = 1

local gridColor = { 0.5, 0.5, 0.5 }
local mealcolor = { 0, 1, 0, 1 }
local cellcolor1 = { 0.5, 0.5, 0.5, 1 }
local cellcolor2 = { 0, 0, 1, 1 }


local function clearCanvases(canvases, color)
   for _, canvas in ipairs(canvases) do
      gr.setCanvas(canvas)
      gr.clear(color)
      gr.setCanvas()
   end
end

function SimulatorRender.new(commonSetup, cam)
   local self = {
      commonSetup = shallowCopy(commonSetup),
      cam = cam,
      fieldWidthPixels = 0,
      fieldHeightPixels = 0,
      canvas = nil,
      cellCanvas = gr.newCanvas(pixSize, pixSize),
      mealCanvas = gr.newCanvas(pixSize, pixSize),
   }
   self = setmetatable(self, SimulatorRender_mt)
   self:computeGrid()
   print("fieldWidthPixels, fieldHeightPixels", self.fieldWidthPixels, self.fieldHeightPixels)

   self.canvas = gr.newCanvas(
   self.fieldWidthPixels * canvasmultfactor,
   self.fieldHeightPixels * canvasmultfactor)


   clearCanvases(
   { self.canvas, self.cellCanvas, self.mealCanvas },
   { 0.5, 0, 0, 1 })


   self:prerender()
   self:cameraToCenter()
   self:draw()

   self.canvas:newImageData():encode('png', "simulator-render-canvas.png")
   self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas.png')
   self.mealCanvas:newImageData():encode('png', 'simulator-render-meal-canvas.png')

   return self
end

function SimulatorRender:cameraToCenter()
   local w, h = gr.getDimensions()


   print('w, h', w, h)

   print('self.fieldWidthPixels', self.fieldWidthPixels, self.fieldHeightPixels)
   local dx = (w - (self.canvas):getWidth()) / 2
   local dy = (h - (self.canvas):getHeight()) / 2


   print("camera position", self.cam:position())
   print("dx, dy", dx, dy)
   self.cam.scale = 1.
   self.cam:lookAt(dx, dy)
   print("camera position2", self.cam:position())






end

function SimulatorRender:bakeCanvas()
   gr.setColor({ 1, 1, 1, 1 })
   gr.setCanvas(self.canvas)

   gr.clear({ 0, 0, 0, 1 })
   self:drawGrid()
   self:drawCells()
   gr.setCanvas()
end

local testing = require('testing')

function SimulatorRender:draw()
   self:bakeCanvas()


   gr.setColor({ 1, 1, 1, 1 })

   local sx, sy = 1, 1

   print('self.camera.position', self.cam:position())

   self.cam:attach()
   gr.draw(
   self.canvas,
   0,
   0,
   0.0,
   sx,
   sy)

   self.cam:detach()




   local font = love.graphics.newFont("fonts/DroidSansMono.ttf", 32)
   gr.setFont(font)
   gr.setColor(1, 1, 1)
   gr.print('привет галактика!', 100, 100)
end

function SimulatorRender:update(_)
end

function SimulatorRender:prerender()
   if not self.cellCanvas and not self.mealCanvas then
      error("No cellCanvas created!")
   end

   gr.setCanvas(self.mealCanvas)
   gr.clear(0, 0, 0, 1)
   gr.setColor(mealcolor)
   gr.rectangle("fill", 0, 0, pixSize, pixSize)
   gr.setCanvas()

   local n = 2
   gr.setCanvas(self.cellCanvas)
   gr.clear(cellcolor1)
   gr.setColor(cellcolor2)
   gr.rectangle("fill", n, n, pixSize - 2 * n, pixSize - 2 * n)
   gr.setCanvas()
end

function SimulatorRender:drawCells()
   local drawlist = sim.getDrawLists()


   if not drawlist then
      return
   end

   for _, node in ipairs(drawlist) do
      local x, y = (node.x - 1) * pixSize, (node.y - 1) * pixSize
      if node.food then
         gr.setColor(1, 1, 1, 1)
         gr.draw(self.mealCanvas, x, y)
      else
         if node.color then
            gr.setColor(node.color)
         else
            gr.setColor(1, 1, 1, 1)
         end
         gr.draw(self.cellCanvas, x, y)
      end
   end
end

function SimulatorRender:computeGrid()
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

   if schema then
      for _, v in pairs(schema) do
         local dx, dy = (v).draw[1] * pixSize * gridSize, (v).draw[2] * pixSize * gridSize
         for i = 0, gridSize do
            local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
            local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
            self.fieldHeightPixels = y2 - y1
            x1, y1 = dx + 0, dy + i * pixSize
            x2, y2 = dx + gridSize * pixSize, dy + i * pixSize
            self.fieldWidthPixels = x2 - x1
         end
      end
   else
      error(string.format(
      "No schema for %d", self.commonSetup.threadCount))
   end
end

function SimulatorRender:drawGrid()
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

   local prevwidth = { gr.getColor() }

   gr.setLineWidth(gridLineWidth)
   gr.setColor(gridColor)

   if schema then
      for _, v in pairs(schema) do
         local dx, dy = (v).draw[1] * pixSize * gridSize, (v).draw[2] * pixSize * gridSize
         for i = 0, gridSize do

            local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
            local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
            self.fieldHeightPixels = y2 - y1
            gr.line(x1, y1, x2, y2)

            x1, y1 = dx + 0, dy + i * pixSize
            x2, y2 = dx + gridSize * pixSize, dy + i * pixSize
            self.fieldWidthPixels = x2 - x1
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
   gr.setLineWidth(_tl_table_unpack(prevwidth))
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

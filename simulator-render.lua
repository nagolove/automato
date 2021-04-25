local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack; require("love")





love.filesystem.setRequirePath(
love.filesystem.getRequirePath() .. "?.lua;scenes/automato/?.lua")


require("love")
require("imgui")
require("common")
require("types")





local gr = love.graphics
local mtschemes = require("mtschemes")
local sim = require("simulator")

 SimulatorRender = {}






























local SimulatorRender_mt = {
   __index = SimulatorRender,
}


local cellAnimFramesCount = 4

local cellAnimSpeed = 24.

local AnimatedCell = {}








local AnimatedCell_mt = {
   __index = AnimatedCell,
}

function AnimatedCell.new(x, y)
   local self = setmetatable({}, AnimatedCell_mt)
   self.x = x
   self.y = y

   self.frame = math.random(1, cellAnimFramesCount)
   self.timestamp = love.timer.getTime()
   return self
end

local animatedCellsArr
local animatedCellsGrid


local pixSize = 60

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

function SimulatorRender:createAnimatedCells()
   animatedCellsGrid = {}
   animatedCellsArr = {}
   for i = 1, self.commonSetup.gridSize do
      table.insert(animatedCellsGrid, {})
      local row = animatedCellsGrid[math.floor(i)]
      for j = 1, self.commonSetup.gridSize do
         local animatedCell = AnimatedCell.new(j, i)
         row[#row + 1] = animatedCell
         animatedCellsArr[#animatedCellsArr + 1] = animatedCell
      end
   end
end

function SimulatorRender:updateAnimatedCells(_)
   local now = love.timer.getTime()
   local framePause = 1 / cellAnimSpeed
   for _, animatedCell in ipairs(animatedCellsArr) do
      if now - animatedCell.timestamp >= framePause then
         animatedCell.timestamp = now
         if animatedCell.frame + 1 >= cellAnimFramesCount then
            animatedCell.frame = 1
         else
            animatedCell.frame = animatedCell.frame + 1
         end
      end
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
      enabled = true,
   }
   self = setmetatable(self, SimulatorRender_mt)
   self:computeGrid()
   printLog("fieldWidthPixels, fieldHeightPixels", self.fieldWidthPixels, self.fieldHeightPixels)

   local cw, ch = math.ceil(self.fieldWidthPixels * canvasmultfactor), math.ceil(self.fieldHeightPixels * canvasmultfactor)
   self.gridCanvas = gr.newCanvas(cw, ch)
   self.canvas = gr.newCanvas(cw, ch)

   clearCanvases(
   { self.gridCanvas, self.canvas, self.cellCanvas, self.mealCanvas },
   { 0, 0, 0, 1 })


   self:prerender()
   self:cameraToCenter()
   self:draw()

   self.canvas:newImageData():encode('png', "simulator-render-canvas.png")
   self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas.png')
   self.mealCanvas:newImageData():encode('png', 'simulator-render-meal-canvas.png')

   return self
end

function SimulatorRender:getRect()
   local x, y = self.cam:cameraCoords(0, 0)
   local w = self.commonSetup.gridSize * self.cam.scale * pixSize
   local h = self.commonSetup.gridSize * self.cam.scale * pixSize
   return x, y, w, h
end

function SimulatorRender:mouseToCamera(x, y)
   local nx, ny = self.cam:worldCoords(x, y)
   return {
      x = math.ceil((nx / self:getPixSize()) * self.cam.scale),
      y = math.ceil((ny / self:getPixSize()) * self.cam.scale),
   }
end

function SimulatorRender:cameraToCenter()
   local w, h = gr.getDimensions()
   printLog('w, h', w, h)
   printLog('self.fieldWidthPixels', self.fieldWidthPixels, self.fieldHeightPixels)
   local dx = (w - (self.canvas):getWidth()) / 2
   local dy = (h - (self.canvas):getHeight()) / 2

   self.cam.scale = 1.
   self.cam:lookAt(dx, dy)
end

function SimulatorRender:bakeCanvas()
   gr.setColor({ 1, 1, 1, 1 })
   gr.setCanvas(self.canvas)
   gr.clear({ 0, 0, 0, 1 })
   gr.draw(self.gridCanvas)
   self:presentLists()
   gr.setCanvas()
end



function SimulatorRender:draw()
   if not self.enabled then
      return
   end

   self:bakeCanvas()
   gr.setColor({ 1, 1, 1, 1 })
   local sx, sy = 1, 1

   self.cam:attach()
   gr.draw(self.canvas, 0, 0, 0.0, sx, sy)
   self.cam:detach()


end

function SimulatorRender:update(dt)
   self:updateAnimatedCells(dt)
end

function SimulatorRender:prerenderMeal()
   gr.setCanvas(self.mealCanvas)
   gr.clear(0, 0, 0, 1)
   gr.setColor(mealcolor)
   gr.rectangle("fill", 0, 0, pixSize, pixSize)
   gr.setCanvas()
end

function SimulatorRender:prerenderCell()

   local tmpImage = gr.newImage("scenes/automato/cell-anim.png")

   gr.setCanvas(self.cellCanvas)
   gr.clear(cellcolor1)
   gr.setColor(cellcolor2)

   gr.draw(
   tmpImage, 0, 0, 0,
   (self.cellCanvas):getWidth() / tmpImage:getWidth(),
   (self.cellCanvas):getHeight() / tmpImage:getHeight())

   gr.setCanvas()
   self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas-1.png')
   self:createAnimatedCells()
end

function SimulatorRender:prerenderGrid()
   gr.setCanvas(self.gridCanvas)
   self:drawGrid()
   gr.setCanvas()
end

function SimulatorRender:prerender()
   if not self.cellCanvas and not self.mealCanvas then
      error("No cellCanvas created!")
   end
   self:prerenderMeal()
   self:prerenderCell()
   self:prerenderGrid()
end

function SimulatorRender:drawCell(animatedCell)
   gr.setColor(1, 1, 1, 1)
   gr.draw(self.cellCanvas, animatedCell.x, animatedCell.y)
end

function SimulatorRender:drawMeal(animatedCell)
   gr.draw(self.mealCanvas, animatedCell.x, animatedCell.y)
end

function SimulatorRender:presentList(list)
   for _, node in ipairs(list) do
      local x, y = math.floor((node.x - 1) * pixSize), math.floor((node.y - 1) * pixSize)

      local animatedCell = animatedCellsGrid[x][y]
      if animatedCell and animatedCell.empty then
         local tmpCell = AnimatedCell.new(x, y)
         animatedCellsGrid[x][y] = tmpCell
         animatedCellsArr[#animatedCellsArr + 1] = tmpCell
      end
      if animatedCell then
         if node.food then
            self:drawCell(animatedCell)
         else
            if node.color then
               gr.setColor(node.color)
            else
               gr.setColor(1, 1, 1, 1)
            end
            self:drawMeal(animatedCell)
         end
      end
   end
end

function SimulatorRender:presentLists()
   local drawlists = sim.getDrawLists()
   if not drawlists then
      return
   end
   for _, list in ipairs(drawlists) do
      self:presentList(list)
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
      printLog("Could'not require 'mtschemes'", errmsg)
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
      printLog("Could'not require 'mtschemes'", errmsg)
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

local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack






require("love")
love.filesystem.setRequirePath("scenes/automato/?.lua")

require("external")
require("common")
require("types")

package.path = package.path .. ";scenes/automato/?.lua"

local cam = require("camera").new()
local gr = love.graphics
local imgui = require("imgui")
local inspect = require("inspect")
local prof = require("jprof")
local keyconfig = require("keyconfig")
local mtschemes = require("mtschemes")
local next = next
local sim = require("simulator")
local startInStepMode = false
local timer = require("Timer")

PROF_CAPTURE = true

local ViewState = {}




local profi = require("profi")


local viewState = "sim"


local MouseCapture = {}






local mouseCapture
local underCursor = {}


local graphCanvas = gr.newCanvas(gr.getWidth() * 4, gr.getHeight())


local MAX_ENERGY_COLOR = { 1, 0.5, 0.7, 1 }
local MID_ENERGY_COLOR = { 0.8, 0.3, 0.7, 1 }
local MIN_ENERGY_COLOR = { 0.6, 0.1, 1, 1 }





local mode = "continuos"


local pixSize = 10




local commonSetup = {

   gridSize = 50,

   cellsNum = 1000,

   initialEnergy = { 5000, 10000 },

   codeLen = 32,

   threadCount = 1,

   nofood = false,
   denergy = 1,
   foodenergy = 10,
}
local maxCellsNum = 5000

local gridLineWidth = 1
local infoTimer = timer.new()

local threadsInfo

local function getMode()
   return mode
end

function drawCells()
   local drawlist = sim.getDrawLists()
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

function drawGrid()




   do
      gr.setColor(0.5, 0.5, 0.5)
      local gridSize = commonSetup.gridSize

      if not gridSize then
         return
      end


      local schema
      local ok, errmsg = pcall(function()
         schema = mtschemes[commonSetup.threadCount]
      end)
      if not ok then
         print("Could'not require 'mtschemes'")
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
end

function drawStatisticTable()
   local y0 = 0
   gr.setColor(1, 0, 0)

   y0 = y0 + gr.getFont():getHeight()
   local statistic = sim.getStatistic()
   if statistic then
      if statistic.maxEnergy then
         gr.setColor(1, 0, 0)
         gr.print(string.format("max energy in cell %d", statistic.maxEnergy), 0, y0)
         y0 = y0 + gr.getFont():getHeight()
      end
      if statistic.minEnergy then
         gr.setColor(1, 0, 0)
         gr.print(string.format("min energy in cell %d", statistic.minEnergy), 0, y0)
         y0 = y0 + gr.getFont():getHeight()
      end
      if statistic.midEnergy then
         gr.setColor(1, 0, 0)
         gr.print(string.format("mid energy in cell %d", statistic.midEnergy), 0, y0)
         y0 = y0 + gr.getFont():getHeight()
      end
   end
end

function drawAxises()
   gr.setColor(0, 1, 0)
   local w, h = gr.getDimensions()
   gr.setLineWidth(3)
   gr.line(0, h, 0, 0)
   gr.line(0, h, w, h)
   gr.setLineWidth(1)
end

local function drawLegends()
   local y0 = 0

   gr.setColor(MAX_ENERGY_COLOR)
   gr.print("max energy", 0, y0)
   y0 = y0 + gr.getFont():getHeight()

   gr.setColor(MID_ENERGY_COLOR)
   gr.print("mid energy", 0, y0)
   y0 = y0 + gr.getFont():getHeight()

   gr.setColor(MIN_ENERGY_COLOR)
   gr.print("min energy", 0, y0)
   y0 = y0 + gr.getFont():getHeight()
end

local function drawGraphs()
   drawAxises()
   drawLegends()
   gr.draw(graphCanvas)
end

local function getCell(pos)
   if not pos or not pos.x or not pos.y then
      return nil
   end
   local size = sim.getGridSize()
   if size then
      local x, y = pos.x, pos.y
      if x + 1 >= 1 and x + 1 <= size and
         y + 1 >= 1 and y + 1 <= size then
         local cell = sim.getObject(x + 1, y + 1)
         return cell
      end
   end
   return nil
end

local function replaceCaret(str)
   return string.gsub(str, "\n", "")
end

local function drawCellInfo(cell)
   if not cell then
      return
   end


   if next(cell) ~= nil then
      local mx, my = love.mouse.getPosition()
      gr.setColor(1, 0, 0)

      gr.circle("line", mx, my, 5)
   end

   local msg
   for k, v in pairs(cell) do
      if k ~= "code" then
         local fmt



         local a = v
         local tp = type(v)
         if tp == "number" then
            fmt = "%d"
            a = tonumber(a)
         elseif tp == "table" then
            fmt = "%s"
            a = replaceCaret(inspect(a))
         else
            fmt = "%s"
            a = tostring(a)
         end
         msg = string.format(fmt, a)
         imgui.LabelText(k, msg)
      end
   end
end

local function getPixSize()
   return pixSize
end

local function drawCellPath(cell)
   if cell and cell.moves and #cell.moves >= 4 then
      local pixels = getPixSize()
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


local function nextMode()
   if mode == "continuos" then
      mode = "step"
   elseif mode == "step" then
      mode = "continuos"
   end
   sim.setMode(mode)
end





local function checkValidThreadCount(threadCount)


   local prev = 1
   local ok = false
   for k, _ in pairs(mtschemes) do
      if k == threadCount then
         ok = true
         break
      end
      prev = k

   end

   if not ok then
      threadCount = prev
   end

   return threadCount
end













local function printThreadsInfo()
   if threadsInfo then
      for k, v in ipairs(threadsInfo) do
         imgui.Text(string.format("thread %d cells %d meals %d", k, v.cells, v.meals))
         if v.stepsPerSecond then
            imgui.Text(string.format("iteration per second - %d", v.stepsPerSecond))
         end
      end
   else
      imgui.Text(string.format("thread %d cells %d meals %d", -1, -1, -1))
   end
end


local ismodal = false

local presetsNames = {}
local presets = {}
local selectedPreset = 1

local function activatePreset(num)
   commonSetup = shallowCopy(presets[num])
end

local function drawSim()
   imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

   local num, status = imgui.Combo("preset", selectedPreset, presetsNames, #presetsNames)
   if status then
      selectedPreset = num
      activatePreset(num)
   end

   if imgui.Button("save preset") then

   end

   imgui.Text(string.format("mode %s", getMode()))

   if imgui.Button("change mode", getMode()) then
      nextMode()
   end

   commonSetup.nofood = imgui.Checkbox("no food", commonSetup.nofood)

   local status

   commonSetup.cellsNum, status = imgui.SliderFloat("initial population", commonSetup.cellsNum, 0, maxCellsNum)
   commonSetup.cellsNum = math.ceil(commonSetup.cellsNum)

   commonSetup.denergy, status = imgui.SliderFloat("decrease enerby by", commonSetup.denergy, 0, 1)

   commonSetup.foodenergy, status = imgui.SliderFloat("food energy", commonSetup.foodenergy, 0, 10)

   commonSetup.gridSize, status = imgui.SliderInt("grid size", commonSetup.gridSize, 10, 100)

   commonSetup.threadCount, status = imgui.SliderInt("thread count", commonSetup.threadCount, 1, 9)
   commonSetup.threadCount = checkValidThreadCount(commonSetup.threadCount)

   status = imgui.Checkbox("start in step mode", startInStepMode)
   startInStepMode = status

   if startInStepMode then
      commonSetup.mode = "step"
   end

   if imgui.Button("reset silumation") then







      sim.shutdown()

      prof.pop()
      prof.write('prof.mpack')
      print("written")
   end

   if imgui.Button("start") then
      prof.push()
      sim.create(commonSetup)


   end

   if imgui.Button("step") then
      sim.step()
   end








   if sim.getMode() ~= "stop" then
      imgui.Text(string.format("uptime %d sec", sim.getUptime()))
   end

   printThreadsInfo()

   if underCursor then

      local cell = getCell(underCursor)


      drawCellInfo(cell)
      drawCellPath(cell)
   end

   imgui.End()
end

local function drawui()
   drawSim()
end

local function draw()
   if viewState == "sim" then
      cam:attach()
      drawGrid()
      drawCells()


      cam:detach()
   elseif viewState == "graph" then

   end
end

local function checkMouse()
   if love.mouse.isDown(1) then
      if not mouseCapture then
         mouseCapture = {
            x = love.mouse.getX(),
            y = love.mouse.getY(),
            dx = 0,
            dy = 0,
         }
      else
         mouseCapture.dx = mouseCapture.x - love.mouse.getX()
         mouseCapture.dy = mouseCapture.y - love.mouse.getY()
      end
   else
      mouseCapture = nil
   end
end


















































local function update(dt)
   infoTimer:update(dt)

   controlCamera(cam)

   sim.step()




   local isDown = love.keyboard.isDown
   if isDown("z") then

   elseif isDown("x") then

   end
end

function setViewState(stateName)
   viewState = stateName
end

local function keypressed(key)
   if key == "1" then
      setViewState("sim")
   elseif key == "2" then
      setViewState("graph")
   elseif key == "p" then
      nextMode()
   elseif key == "s" then
      sim.doStep()
   elseif key == "space" then


      if sim.getMode() == "stop" then
         sim.create(commonSetup)
      else
         sim.step()
      end
   end
end

local function loadPresets()
   local chunk, errmsg = love.filesystem.load("scenes/automato/presets.lua")
   print("chunk, errmsg", chunk, errmsg)
   local loadedPresets = (chunk)()
   print("presets", inspect(presets))
   for k, v in pairs(loadedPresets) do
      table.insert(presetsNames, k)
      for k1, v1 in pairs(commonSetup) do
         local tmp = v
         if tmp[k1] == nil then
            tmp[k1] = v1
         end
      end
      table.insert(presets, v)
   end
end

local function init()
   math.randomseed(love.timer.getTime())
   local mx, my = love.mouse.getPosition()
   underCursor = { x = mx, y = my }

   keyconfig.bindKeyDown("zoomout", { "z" }, function()
      print("zoout")
      cam:zoom(1.01)
   end, "zoom camera out")

   keyconfig.bindKeyDown("zoomin", { "x" }, function()
      cam:zoom(0.99)
   end, "zoom camera in")

   keyconfig.bindKeyPressed("exit", { "escape" }, function()
      love.event.quit()
   end, "close program")

   threadsInfo = { { cells = 0, meals = 0 } }
   infoTimer:every(0.1, function(_)
      local info = sim.getThreadsInfo()

      if info then
         threadsInfo = info
      else
         print("no info")
      end
   end)

   loadPresets()
end

local function quit()
end

local function mousemoved(x, y, _, _)
   local w, h = gr.getDimensions()
   local tlx, tly, brx, bry = 0, 0, w, h

   if cam then
      tlx, tly = cam:worldCoords(tlx, tly)
      brx, bry = cam:worldCoords(brx, bry)
   end


   underCursor = {
      x = math.floor(x / getPixSize()),
      y = math.floor(y / getPixSize()),
   }
end

local function wheelmoved(x, y)
   if y == -1 then
      keyconfig.send("zoomin")
   else
      keyconfig.send("zoomout")
   end
end

return {
   getPixSize = getPixSize,

   getMode = getMode,
   nextMode = nextMode,

   cam = cam,




   init = init,
   quit = quit,
   draw = draw,
   drawui = drawui,
   update = update,
   keypressed = keypressed,
   mousemoved = mousemoved,
   wheelmoved = wheelmoved,
}

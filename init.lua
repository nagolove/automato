local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table







require("love")
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
package.path = package.path .. ";scenes/automato/?.lua"
require("common")
require("imgui")
require("simulator-render")
require("types")

local camera = require("camera")
local gr = love.graphics
local imgui = require("imgui")
local inspect = require("inspect")
local keyconfig = require("keyconfig")
local mtschemes = require("mtschemes")
local prof = require("jprof")
local sim = require("simulator")
local startInStepMode = false
local timer = require("Timer")


PROF_CAPTURE = true

local ViewState = {}





local viewState = "sim"
local underCursor = {}
local simulatorRender
local cam



print("graphics size", gr.getWidth(), gr.getHeight())











local mode = "continuos"




local commonSetup = {

   gridSize = 50,

   cellsNum = 1000,

   initialEnergy = { 5000, 10000 },

   codeLen = 32,

   threadCount = 1,

   nofood = false,
   denergy = 1,
   foodenergy = 10,
   emitInvSpeed = 1,
}

local maxCellsNum = 5000
local infoTimer = timer.new()
local threadsInfo

local function getMode()
   return mode
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




local presetsNames = {}
local presets = {}
local selectedPreset = 1

local function activatePreset(num)
   commonSetup = shallowCopy(presets[num])
end

local function writeState()
   local res = sim.writeState()
   love.filesystem.write("sim.data", res)
end

local function drawui()
   imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

   local num, status
   num, status = imgui.Combo("preset", selectedPreset, presetsNames, #presetsNames)
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

   commonSetup.cellsNum, status = imgui.SliderFloat("initial population", commonSetup.cellsNum, 0, maxCellsNum)
   commonSetup.cellsNum = math.ceil(commonSetup.cellsNum)

   commonSetup.emitInvSpeed, status = imgui.SliderFloat("inverted emmision speed", commonSetup.emitInvSpeed, 0, 200)
   commonSetup.emitInvSpeed = math.ceil(commonSetup.emitInvSpeed)

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
      simulatorRender = SimulatorRender.new(commonSetup, cam)
      sim.create(commonSetup)


   end

   if imgui.Button("step") then
      sim.step()
   end

   if imgui.Button("write state") then
      writeState()
   end








   if sim.getMode() ~= "stop" then
      imgui.Text(string.format("uptime %d sec", sim.getUptime()))
   end

   printThreadsInfo()

   if underCursor then

      local cell = getCell(underCursor)


      drawCellInfo(cell)
      simulatorRender:drawCellPath(cell)
   end

   imgui.End()
end

local function draw()
   if viewState == "sim" then
      simulatorRender:draw()
   elseif viewState == "graph" then

   end
end




































































local function update(dt)
   infoTimer:update(dt)



   sim.step()



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

   cam = camera.new()
   simulatorRender = SimulatorRender.new(commonSetup, cam)
   bindCameraControl(keyconfig, cam)

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

   print("simulatorRender", inspect(simulatorRender))
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

   print("simulatorRender2", inspect(simulatorRender))

   print(simulatorRender.cam)

   underCursor = {
      x = math.floor(x / simulatorRender:getPixSize()),
      y = math.floor(y / simulatorRender:getPixSize()),
   }
end

local function wheelmoved(_, y)
   if y == -1 then
      keyconfig.send("zoomin")
   else
      keyconfig.send("zoomout")
   end
end

return {
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

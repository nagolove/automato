local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table







require("love")
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
package.path = package.path .. ";scenes/automato/?.lua"
require("common")
require("imgui")
require("simulator-render")
require("types")


local ViewState = {}




PROF_CAPTURE = false

local linesbuf = require('kons').new()
local camera = require("camera")
local gr = love.graphics
local imgui = require("imgui")
local inspect = require("inspect")
local mtschemes = require("mtschemes")

local sim = require("simulator")
local startInStepMode = false
local binds = require("binds")
local i18n = require("i18n")
local profi = require("profi")
local linesbufDelay = 1
local viewState = "sim"
local underCursor = {}
local simulatorRender
local cam
local useProfi = false
local mode = "stop"
local foodProduction = ''
local maxCellsNum = 5000
local snaphotsDirectory = 'snaphots'


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

local function loadLocales()
   local localePath = "scenes/automato/locales"
   local files = love.filesystem.getDirectoryItems(localePath)
   print("locale files", inspect(files))
   for _, v in ipairs(files) do
      i18n.loadFile(localePath .. "/" .. v, function(path)
         local chunk, errmsg = love.filesystem.load(path)
         if not chunk then
            error(errmsg)
         end
         return chunk
      end)
   end
   i18n.setLocale('en')
   print("i18n", inspect(i18n))
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













local prevStat

local function printStat()
   local starr = sim.getStatistic()

   print("starr = ", inspect(starr))
   print("#starr", #starr)
   print("prevStat", inspect(prevStat))


   if #starr ~= 0 then
      prevStat = deepCopy(prevStat)
   elseif #starr == 0 and prevStat then
      starr = prevStat
      print("used prevStat", inspect(prevStat))
   end

   for _, st in ipairs(starr) do
      for k, v in pairs(st) do
         imgui.Text(string.format('%s:' .. formatMods[k], k, v))
      end
   end
end




local presetsNames = {}
local presets = {}
local selectedPreset = 1

local function activatePreset(num)
   commonSetup = shallowCopy(presets[num])
end

local function readState()




end

local function writeState()
   local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
   print('files', inspect(files))
   local res = sim.writeState()
   local fname = snaphotsDirectory .. string.format("/sim-%d.data", #files)
   love.filesystem.write(fname, res)
end

local function start()

   commonSetup.spreadPoint = {
      x = math.floor(commonSetup.gridSize / 2),
      y = math.floor(commonSetup.gridSize / 2),
   }
   commonSetup.spreadRad = math.floor(commonSetup.gridSize / 2)
   commonSetup.mode = 'continuos'
   mode = 'continuos'
   sim.create(commonSetup)
   simulatorRender = SimulatorRender.new(commonSetup, cam)
   simulatorRender:cameraToCenter()

   if useProfi then
      profi:start()
   end
end

local maxEnergy = 100000

local function roundSettings()
   local status

   commonSetup.nofood = imgui.Checkbox(i18n("nofood"), commonSetup.nofood)

   commonSetup.initialEnergy[1], status = imgui.SliderInt('minimum energy', commonSetup.initialEnergy[1], 0, maxEnergy)
   commonSetup.initialEnergy[2], status = imgui.SliderInt('maximum energy', commonSetup.initialEnergy[2], 0, maxEnergy)

   commonSetup.cellsNum, status = imgui.SliderFloat(i18n("initpopulation"), commonSetup.cellsNum, 0, maxCellsNum)
   commonSetup.cellsNum = math.ceil(commonSetup.cellsNum)

   commonSetup.emitInvSpeed, status = imgui.SliderFloat(i18n("invemmspeed"), commonSetup.emitInvSpeed, 0, 200)
   commonSetup.emitInvSpeed = math.ceil(commonSetup.emitInvSpeed)

   commonSetup.denergy, status = imgui.SliderFloat(i18n("decreaseenby"), commonSetup.denergy, 0, 1)

   commonSetup.foodenergy, status = imgui.SliderFloat(i18n("foodenergy"), commonSetup.foodenergy, 0, 10)

   commonSetup.gridSize, status = imgui.SliderInt(i18n("gridsize"), commonSetup.gridSize, 10, 100)
   if simulatorRender and status then
      simulatorRender:cameraToCenter()
      simulatorRender:draw()
   end

   commonSetup.threadCount, status = imgui.SliderInt(i18n("threadcount"), commonSetup.threadCount, 1, 9)
   commonSetup.threadCount = checkValidThreadCount(commonSetup.threadCount)
   if simulatorRender and status then
      simulatorRender:cameraToCenter()
      simulatorRender:draw()
   end

   status = imgui.Checkbox(i18n("startinsmode"), startInStepMode)
   startInStepMode = status

   if startInStepMode then
      commonSetup.mode = "step"
   end
end

local function stop()


   profi:stop()
   profi:setSortMethod("duration")
   profi:writeReport("init-profile-duration.txt")
   profi:setSortMethod("count")
   profi:writeReport("init-profile-count.txt")

   sim.shutdown()
   mode = 'stop'



end

local function drawui()
   linesbuf:draw()

   imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

   local num, status
   num, status = imgui.Combo("preset", selectedPreset, presetsNames, #presetsNames)
   if status then
      selectedPreset = num
      activatePreset(num)
   end





   if mode == "stop" then
      roundSettings()
   end

   if imgui.Button(i18n("start")) then
      start()
   end
   imgui.SameLine()
   if imgui.Button(i18n("stp")) then
      stop()
   end
   imgui.SameLine()
   if imgui.Button(i18n("changemode")) then
      nextMode()
   end

   imgui.Text(string.format("mode %s", mode))

   if imgui.Button(i18n("readstate")) then
      readState()
   end
   imgui.SameLine()
   if imgui.Button(i18n("writestate")) then
      writeState()
   end
   imgui.SameLine()
   if imgui.Button("<<") then

   end
   imgui.SameLine()
   if imgui.Button(">>") then

   end

   foodProduction = imgui.InputTextMultiline("[Lua]: function(iter: number): ", foodProduction, 200, 300, 200);
   imgui.Text(string.format("uptime %d sec", sim.getUptime()))

   printStat()

   imgui.End()
end

local function draw()
   if viewState == "sim" then
      local zazor = 10
      simulatorRender:draw()










      if underCursor then

         local cell = getCell(underCursor)


         drawCellInfo(cell)

         simulatorRender:drawCellPath(cell)

      end

   elseif viewState == "graph" then

   end
end



















local function update(dt)
   linesbuf:pushi(string.format('FPS %d', love.timer.getFPS()))
   linesbuf:update()
   simulatorRender:update(dt)
   sim.update(dt)
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

local function bindKeys()
   binds.bindCameraControl(cam)
   local Shortcut = KeyConfig.Shortcut

   KeyConfig.bind(
   "keypressed",
   { key = "escape" },
   function(sc)
      love.event.quit()
      return false, sc
   end,
   "close program",
   "exit")


   KeyConfig.bind(
   "keypressed",
   { mod = { "alt" }, key = "1" },
   function(sc)
      love.event.quit()
      return false, sc
   end,
   "Show graph1",
   "graph1")


   KeyConfig.bind(
   "keypressed",
   { mod = { "alt" }, key = "2" },
   function(sc)
      love.event.quit()
      return false, sc
   end,
   "Show graph2",
   "graph2")


   KeyConfig.bind(
   "isdown",
   { mod = { "lctrl" }, key = "3" },
   function(sc)
      love.event.quit()
      return false, sc
   end,
   "Show graph3",
   "graph3")


   KeyConfig.bind(
   "isdown",
   { mod = { "lctrl" }, key = "4" },
   function(sc)
      love.event.quit()
      return false, sc
   end,
   "Show graph4",
   "graph4")


   KeyConfig.bind(
   "keypressed",
   { key = 'p' },
   function(sc)
      nextMode()
      return false, sc
   end,
   'switch simulator to next execution mode',
   'nextmode')


   KeyConfig.bind(
   "keypressed",
   { key = 's' },
   function(sc)
      sim.step()
      linesbuf:push(linesbufDelay, 'forward step')
      return false, sc
   end,
   'do a simulation step',
   'step')


   KeyConfig.bind(
   "keypressed",
   { key = 'space' },
   function(sc)
      start()
      return false, sc
   end,
   'start',
   'start')


   KeyConfig.bind(
   'keypressed',
   { key = 'l' },
   function(sc)
      if i18n.getLocale() == 'en' then
         i18n.setLocale('ru')
      elseif i18n.getLocale() == 'ru' then
         i18n.setLocale('en')
      end
      return false, sc
   end,
   'change locale',
   'chlocale')


   KeyConfig.bind(
   'keypressed',
   { mod = { 'lctrl' }, key = 'p' },
   function(sc)
      useProfi = not useProfi
      return false, sc
   end,
   'enable or disable profiler. Dev only',
   'profiler')


   KeyConfig.bind(
   'keypressed',
   { key = '0' },
   function(sc)
      simulatorRender.enabled = not simulatorRender.enabled
      return false, sc
   end,
   'enable or disable rendering. Dev only',
   'enablerender')

end

local function init()
   print("automato init()")
   love.filesystem.createDirectory('snaphots')
   loadLocales()
   local mx, my = love.mouse.getPosition()
   underCursor = { x = mx, y = my }

   cam = camera.new()
   simulatorRender = SimulatorRender.new(commonSetup, cam)

   bindKeys()
   loadPresets()
   print("automato init done.")
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
      x = math.floor(x / simulatorRender:getPixSize()),
      y = math.floor(y / simulatorRender:getPixSize()),
   }
end

local function wheelmoved(_, y)
   if y == -1 then
      KeyConfig.send("zoomin")
   else
      KeyConfig.send("zoomout")
   end
end

return {
   cam = cam,
   init = init,
   quit = quit,
   draw = draw,
   drawui = drawui,
   update = update,
   mousemoved = mousemoved,
   wheelmoved = wheelmoved,
}

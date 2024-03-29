local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table





require("love")
require("log")
love.filesystem.setRequirePath(love.filesystem.getRequirePath() ..

"?.lua;" ..
"?/init.lua;" ..
"scenes/automato/?/init.lua;" ..
"scenes/automato/?.lua")
printLog('[[' .. love.filesystem.getRequirePath() .. ']]')

require("common")
require("imgui")
require("simulator-render")
require("types")



local ViewState = {}




local profi = require("profi")
local gr = love.graphics



local mem = {}

PROF_CAPTURE = false





local binds = require("binds")
local cam
local camera = require("camera")
local cameraZoomTimeout = 0.5
local cellUnderCursor
local i18n = require("i18n")
local inspect = require("inspect")
local linesbuf = require('kons').new()
local linesbufDelay = 1
local maxCellsNum = 5000
local minGridSize, maxGridSize = 10, 100
local mode = "stop"
local mtschemes = require("mtschemes")
local serpent = require("serpent")
local sim = require("simulator")
local simulatorRender
local snaphotsDirectory = 'snaphots'
local startGrap = {}
local startInStepMode = false
local timer = require("Timer").new()
local underCursor = {}
local useProfi = false
local viewState = "sim"

package.path = package.path .. ";../../?/init.lua;../../?.lua"

printLog("package.path", package.path)


local commonSetup = {

   gridSize = 100,

   cellsNum = 1000,

   initialEnergy = { 5000, 10000 },

   codeLen = 32,

   threadCount = 1,

   nofood = false,

   denergy = 1,

   foodenergy = 10,
   emitInvSpeed = 1,
}

local prevStat



local presetsNames = {}
local presets = {}
local selectedPreset = 1

local states
local selectedState = 0


local function loadStates()
   local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
   printLog('loadStates', inspect(files))
   states = files



   selectedState = 0

end


local function getCellUnderCursor(pos)

   if not pos or not pos.x or not pos.y then
      return nil
   end
   local size = sim.getGridSize()
   if size then
      local x, y = pos.x, pos.y
      if x + 1 >= 1 and x <= size and
         y + 1 >= 1 and y <= size then

         local cell = sim.getObject(x + 0, y + 0)
         return cell
      end
   end
   return nil
end

local function replaceCaret(str)
   return string.gsub(str, "\n", "")
end

local function drawCellInfo(pos, cell)
   if not cell then
      return
   end
   local mx, my = love.mouse.getPosition()



   local d = 5
   imgui.SetNextWindowPos(mx + d, my + d)
   imgui.Begin('info', false, "NoTitleBar|NoMove|NoResize|AlwaysAutoResize")
   local msg
   imgui.Text(string.format('at point %d, %d', pos.x, pos.y))
   linesbuf:pushi('cellUnderCursor', inspect(cell))
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
         imgui.Text(k .. " " .. tostring(msg))
      end
   end

   imgui.End()
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













local function printStat()

   local starr = sim.getStatistic()

   if #starr ~= 0 then
      prevStat = deepCopy(prevStat)
   elseif #starr == 0 and prevStat then
      starr = prevStat
      printLog("used prevStat", inspect(prevStat))
   end

   if #starr > 1 then
      table.remove(starr, 2)
   end

   for _, st in ipairs(starr) do
      for k, v in pairs(st) do

         if imgui.CollapsingHeader(string.format('%s:' .. formatMods[k], k, v), true) then

            local someText = "formatMods." .. k
            imgui.Text(i18n(someText))
         end
      end
   end
end

local function activatePreset(num)
   commonSetup = shallowCopy(presets[num])
end

local function readState()
   local fname = snaphotsDirectory .. '/' .. states[selectedState + 1]
   printLog('readState', fname)
   local fileData = love.filesystem.read(fname)
   printLog('#fileData', #fileData)
   if not sim.readState(fileData) then
      linesbuf:push(linesbufDelay, 'could not load state')
   end
end

local function writeState()
   local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
   printLog('files', inspect(files))
   local res = sim.writeState()
   local fname = snaphotsDirectory .. string.format("/sim-%d.data", #files)
   love.filesystem.write(fname, res)

   loadStates()
end

local function start()
   commonSetup.spreadPoint = {
      x = math.floor(commonSetup.gridSize / 2),
      y = math.floor(commonSetup.gridSize / 2),
   }
   commonSetup.spreadRad = math.floor(commonSetup.gridSize / 2)
   commonSetup.mode = 'continuos'
   mode = 'continuos'
   commonSetup.emitFlags = 'normal'

   sim.create(commonSetup)
   cellUnderCursor = getCellUnderCursor()
   simulatorRender = SimulatorRender.new(commonSetup, cam)
   simulatorRender:cameraToCenter()

   if useProfi then

   end
end

local function moveStart()
   commonSetup.spreadPoint = {
      x = math.floor(commonSetup.gridSize / 2),
      y = math.floor(commonSetup.gridSize / 2),
   }
   commonSetup.spreadRad = math.floor(commonSetup.gridSize / 2)
   commonSetup.mode = 'continuos'
   commonSetup.emitFlags = 'directions_only'
   mode = 'continuos'

   sim.create(commonSetup)
   cellUnderCursor = getCellUnderCursor()
   simulatorRender = SimulatorRender.new(commonSetup, cam)
   simulatorRender:cameraToCenter()

   if useProfi then
      profi:start()
   end
end

local function divStart()
   commonSetup.spreadPoint = {
      x = math.floor(commonSetup.gridSize / 2),
      y = math.floor(commonSetup.gridSize / 2),
   }
   commonSetup.spreadRad = math.floor(commonSetup.gridSize / 2)
   commonSetup.mode = 'continuos'
   commonSetup.emitFlags = 'divide_only'
   mode = 'continuos'

   sim.create(commonSetup)
   cellUnderCursor = getCellUnderCursor()
   simulatorRender = SimulatorRender.new(commonSetup, cam)
   simulatorRender:cameraToCenter()

   if useProfi then
      profi:start()
   end
end

local maxEnergy = 100000

local function roundSettings()
   local status

   local function wrap(n, status)
      return math.floor(n), status
   end

   commonSetup.nofood = imgui.Checkbox(i18n("nofood"), commonSetup.nofood)

   commonSetup.initialEnergy[1], status = imgui.SliderInt('minimum energy', commonSetup.initialEnergy[1], 0, maxEnergy)
   commonSetup.initialEnergy[2], status = imgui.SliderInt('maximum energy', commonSetup.initialEnergy[2], 0, maxEnergy)

   commonSetup.cellsNum, status = wrap(imgui.SliderFloat(i18n("initpopulation"), commonSetup.cellsNum, 0, maxCellsNum))


   commonSetup.emitInvSpeed, status = imgui.SliderFloat(i18n("invemmspeed"), commonSetup.emitInvSpeed, 0, 200)
   commonSetup.emitInvSpeed = math.ceil(commonSetup.emitInvSpeed)

   commonSetup.denergy, status = imgui.SliderFloat(i18n("decreaseenby"), commonSetup.denergy, 0, 1)

   commonSetup.foodenergy, status = imgui.SliderFloat(i18n("foodenergy"), commonSetup.foodenergy, 0, 10)

   commonSetup.gridSize, status = wrap(imgui.SliderInt(i18n("gridsize"), commonSetup.gridSize, minGridSize, maxGridSize))
   if simulatorRender and status then
      simulatorRender:cameraToCenter()
      simulatorRender:draw()
   end

   commonSetup.threadCount, status = wrap(imgui.SliderInt(i18n("threadcount"), commonSetup.threadCount, 1, 9))
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

local drFloat = 10.9


local function drawLog()



end

local SimulatorLog = {}




local SimulatorLog_mt = {
   __index = SimulatorLog,
}

function SimulatorLog:new()
   local o = {}
   return setmetatable(o, SimulatorLog_mt)
end

local function drawSim()
   imgui.Begin("sim", false, "AlwaysAutoResize")

   local num, status





   local zerosSeparated, presetNum = separateByZeros(presetsNames)
   num, status = imgui.Combo("preset", selectedPreset, zerosSeparated, presetNum)

   if status then
      selectedPreset = math.modf(num)
      activatePreset((num + 1.0))
   end

   imgui.Spacing()



   if mode == "stop" then
      roundSettings()
   end
   if imgui.Button("collectgarbage") then
      collectgarbage()
   end
   if imgui.Button("get 1GB RAM" .. string.format(" (usage %d mbytes)", (collectgarbage("count")) / 1024)) then
      local t = {}
      for _ = 1, 1000000 * 5 * 3 do
         local k = math.random()










         table.insert(t, k)






      end
      for _ = 1, 100000 do

      end
      mem[#mem + 1] = t
   end
   if imgui.Button(i18n("start")) then
      start()
   end
   if imgui.Button("move_start") then
      moveStart()
   end
   if imgui.Button("div_start") then
      divStart()
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

   local statesByZeros = ""
   for _, v in ipairs(states) do
      statesByZeros = statesByZeros .. v .. "\0"
   end
   num, status = imgui.Combo('state', selectedState, statesByZeros, #states)

   if status then
      selectedState = math.floor(num)
   end
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


   imgui.Text(string.format("uptime %d sec", sim.getUptime()))


   imgui.Bullet()
   drFloat, status = imgui.DragFloat('drug', drFloat, 1, 0, 100)
   drFloat, status = imgui.SliderAngle('resonator', drFloat, 0, 360)





   if underCursor then
      drawCellInfo(underCursor, cellUnderCursor)
   end

   imgui.End()
end

local function drawBrief()

   imgui.Begin('brief', false)
   printStat()
   if imgui.Button('kill colony') then
      sim.killColony()
   end
   imgui.End()
end

local function drawExperimental()
   if imgui.Button("get 1GB RAM") then
      local t = {}
      for _ = 1, 100000 do
         table.insert(t, 1)
      end

   end
end

local function drawui()
   imgui.StyleColorsLight()

   imgui.ShowDemoWindow()
   imgui.ShowUserGuide()

   drawSim()
   drawLog()
   drawBrief()
   drawExperimental()

   if sim.isColonyDied() then
      print('colony died')



      local window_bg = { 1, 0, 0, 1 }
      imgui.PushStyleColor("WindowBg", window_bg[1], window_bg[2], window_bg[3], window_bg[4])
      local windowCapture = 'Колония умерла'
      imgui.Begin(windowCapture, false, "NoMove|NoResize|AlwaysAutoResize")





      local window_w, window_h = imgui.GetWindowSize()
      local w, h = gr.getDimensions()
      local posx, posy = math.ceil((w - window_w) / 2), math.ceil((h - window_h) / 2)
      imgui.SetWindowPos(windowCapture, posx, posy, "Always")

      imgui.PushAllowKeyboardFocus(false)



      print(i18n('nextplay'))
      if imgui.Button(i18n('nextplay')) then
         start()





















      end
      if imgui.Button(i18n('progress')) then

      end
      if imgui.Button(i18n('exit')) then
         love.event.quit()
      end

      imgui.PopAllowKeyboardFocus()
      imgui.End()
      imgui.PopStyleColor()

   end
end

local function draw()
   if viewState == "sim" then





      simulatorRender:draw()



      if underCursor then

      end

   elseif viewState == "graph" then

   end
   linesbuf:draw()

end



















local function updateMouseToCamera()
   if simulatorRender then
      local mx, my = love.mouse.getPosition()
      underCursor = simulatorRender:mouseToCamera(mx, my)
   end
end

local function update(dt)

   linesbuf:pushi(string.format('FPS %d', love.timer.getFPS()))
   linesbuf:pushi(string.format('scale %f, %f', cam.scale, cam.scale))
   linesbuf:update()
   simulatorRender:update(dt)
   cellUnderCursor = getCellUnderCursor(underCursor)
   timer:update(dt)
   binds.cameraControlUpdate(dt)

   sim.update(dt)


   updateMouseToCamera()

   if love.mouse.isDown(1) then
      startGrap = { love.mouse.getPosition() }

   else
      startGrap = nil
   end
end

local function loadPresets()
   local chunk, errmsg = love.filesystem.load("scenes/automato/presets.lua")
   printLog("chunk, errmsg", chunk, errmsg)
   local loadedPresets = (chunk)()
   printLog("presets", inspect(presets))
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
   "isdown",
   { key = "z" },
   function(sc)
      updateMouseToCamera()
      cam:zoom(1.01)
      return false, sc
   end,
   "zoom camera out",
   "zoomout")


   KeyConfig.bind(
   "isdown",
   { key = "x" },
   function(sc)
      updateMouseToCamera()
      cam:zoom(0.99)
      return false, sc
   end,
   "zoom camera in",
   "zoomin")


   KeyConfig.bind(
   "keypressed",
   { key = "q" },
   function(sc)

      printLog('prof.mpack written')
      return false, sc
   end,
   "write profiler report to file",
   "writeprofreport")


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
   { key = 'c' },
   function(sc)

      sim.setMode('continuos')
      linesbuf:push(linesbufDelay, 'continuos ..')
      return false, sc
   end,
   'go to continuos mode',
   'continuos')


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

local function clearLogs()
   love.filesystem.write('printstat.txt', "")
end

local function loadLocales()
   local localePath = "scenes/automato/locales"
   local files = love.filesystem.getDirectoryItems(localePath)
   printLog("locale files", inspect(files))
   for _, v in ipairs(files) do
      i18n.loadFile(localePath .. "/" .. v, function(path)
         local chunk, errmsg = love.filesystem.load(path)
         if not chunk then
            error(errmsg)
         end
         return chunk
      end)
   end

   i18n.setLocale('ru')
   printLog("i18n", inspect(i18n))
end

local function init()
   clearLogs()
   printLog("automato init()")
   love.filesystem.createDirectory('snaphots')
   loadLocales()
   local mx, my = love.mouse.getPosition()
   underCursor = { x = math.floor(mx), y = math.floor(my) }

   cam = camera.new()
   simulatorRender = SimulatorRender.new(commonSetup, cam)

   bindKeys()
   loadPresets()
   loadStates()
   printLog("automato init done.")
end

local function quit()

   printLog('prof.mpack written')
   love.filesystem.write('camera.txt', '')
   if simulatorRender then
      love.filesystem.append('camera.txt', serpent.dump(simulatorRender.cam))
   end
end



















local function mousemoved(_, _, dx, dy)



   if startGrap then
      linesbuf:push(2, 'mousemoved')
      simulatorRender.cam:move(-dx, -dy)
   end
end

local function wheelmoved(_, y)
   if y == -1 then
      timer:during(cameraZoomTimeout, function()
         KeyConfig.send("zoomin")
      end)
   else
      timer:during(cameraZoomTimeout, function()
         KeyConfig.send("zoomout")
      end)
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

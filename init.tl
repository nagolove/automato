--[[ Клеточный автомат-симулятор. Действие происходит на плоском поле в клетку, замкнутом на себя. Создается популяция клеток которые двигаются по 
сгенерированной случайным образом программе из простого языка.
Клетки питаются едой(зеленый цвет) и имеют конечный запас энергии.
Цель игры - создать и развить долгоживущюю популяцию.
--]]

require "love"
require "log"
love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. 
    --";../../?/init.lua;" ..
    "?.lua;" ..
    "?/init.lua;" .. 
    "scenes/automato/?/init.lua;" ..
    "scenes/automato/?.lua")
printLog('[[' .. love.filesystem.getRequirePath() .. ']]')
--package.path = package.path .. ";scenes/automato/?.lua"
require "common"
require "imgui"
require "simulator-render"
require "types"
--require "log"

-- режит отображения
local type ViewState = enum
    "sim"
    "graph"
end

local profi = require "profi"
local gr = love.graphics
--global PROF_CAPTURE = false

-- табличка для экспериментов с выделением памяти
local mem: {{number, {integer}}} = {}

global PROF_CAPTURE = false

--local foodProduction: string = ''
--local gr = love.graphics
--local imgui = require "love-imgui"
--local prof = require "jprof"
local binds = require "binds"
local cam: Camera
local camera = require "camera"
local cameraZoomTimeout = 0.5
local cellUnderCursor: Cell
local i18n = require "i18n"
local inspect = require "inspect"
local linesbuf = require 'kons'.new()
local linesbufDelay = 1
local maxCellsNum = 5000
local minGridSize, maxGridSize = 10, 100
local mode: SimulatorMode = "stop"
local mtschemes = require "mtschemes"
local serpent = require "serpent"
local sim = require "simulator"
local simulatorRender: SimulatorRender
local snaphotsDirectory = 'snaphots'
local startGrap = {}
local startInStepMode = false
local timer: Timer = require "Timer".new()
local underCursor: Pos = {}
local useProfi = false
local viewState: ViewState = "sim"

package.path = package.path .. ";../../?/init.lua;../../?.lua"

printLog("package.path", package.path)

--[[ Начальные установки симуляции ]]
local commonSetup: CommonSetup = {
    -- размер сетки одного потока
    gridSize = 100,
    -- количество клеток создаваемых на один поток
    cellsNum = 1000, 
    -- разброс начальной энергии клеток
    initialEnergy = {5000, 10000},
    -- длина ленты кода
    codeLen = 32,
    -- на сколько потоков запускать
    threadCount = 1,
    -- отключить создание пищи
    nofood = false,
    -- убавлять энергию на это количество
    denergy = 1,
    -- сколько дает энергии клетка пищи
    foodenergy = 10,
    emitInvSpeed = 1
}

local prevStat: {Statistic}
-- открыт ли модальный диалог(пока только сохранение пресета)
--local ismodal = false

local presetsNames: {string} = {}
local presets: {CommonSetup} = {}
local selectedPreset = 1

local states: {string}
local selectedState = 0

local function loadLocales()
    local localePath = "scenes/automato/locales"
    local files = love.filesystem.getDirectoryItems(localePath)
    printLog("locale files", inspect(files))
    for _, v in ipairs(files) do 
        i18n.loadFile(localePath .. "/" .. v, function(path: string): any
            local chunk, errmsg = love.filesystem.load(path)
            if not chunk then
                error(errmsg)
            end
            return chunk
        end) 
    end
    --i18n.setLocale('en')
    i18n.setLocale('ru')
    printLog("i18n", inspect(i18n))
end

local function loadStates()
    local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
    printLog('loadStates', inspect(files))
    states = files
    --if #states ~= 0 then
        --selectedState = 1
    --else
        selectedState = 0
    --end
end

-- возвращает структуру клетки под курсором pos
local function getCellUnderCursor(pos: Pos): Cell
    -- XXX возможно убрать все проверки в sim.getObject()
    if not pos or not pos.x or not pos.y then
        return nil
    end
    local size = sim.getGridSize()
    if size then
        local x, y = pos.x, pos.y
        if x + 1 >= 1 and x <= size and
            y + 1 >= 1 and y <= size then
                --local cell = sim.getObject(x + 1, y + 1)
                local cell = sim.getObject(x + 0, y + 0)
                return cell
            end
        end
    return nil
end

local function replaceCaret(str: string): string
    return string.gsub(str, "\n", "") as string
end

local function drawCellInfo(pos: Pos, cell: Cell)
    if not cell then
        return
    end
    local mx, my = love.mouse.getPosition()

    -- сделать нормальное выделение клетки под курсором

    local d = 5
    imgui.SetNextWindowPos(mx + d, my + d)
    imgui.Begin('info', false, "NoTitleBar|NoMove|NoResize|AlwaysAutoResize")
    local msg: string
    imgui.Text(string.format('at point %d, %d', pos.x, pos.y))
    linesbuf:pushi('cellUnderCursor', inspect(cell))
    for k, v in pairs(cell as {any: any}) do
        if k ~= "code" then
            local fmt: string
            --local functor: function<T>(T): T = nil

            --local function functor(a: number): number return a end
            local a: any = v
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
            imgui.Text(k as string .. " " .. tostring(msg))
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

--[[
Возвращает количество возможно количество потоков по произвольному значению
параметра.--]]
-- TODO
--Подобрать оптимальный алгоритм
--Работает в большую сторону, а не меньшую
local function checkValidThreadCount(threadCount: integer): integer
    --if not mtschemes[commonSetup.threadCount] then
    --local threadCount = commonSetup.threadCount
    local prev = 1
    local ok = false
    for k, _ in pairs(mtschemes as {any:any}) do
        if k as number == threadCount then
            ok = true
            break
        end
        prev = k as integer
        --print(k, v)
    end

    if not ok then
        threadCount = prev
    end

    return threadCount
end

--print("checkValidThreadCount(1)", checkValidThreadCount(1))
--print("checkValidThreadCount(2)", checkValidThreadCount(2))
--print("checkValidThreadCount(3)", checkValidThreadCount(3))
--print("checkValidThreadCount(4)", checkValidThreadCount(4))
--print("checkValidThreadCount(5)", checkValidThreadCount(5))
--print("checkValidThreadCount(6)", checkValidThreadCount(6))
--print("checkValidThreadCount(7)", checkValidThreadCount(7))
--print("checkValidThreadCount(8)", checkValidThreadCount(8))
--print("checkValidThreadCount(9)", checkValidThreadCount(9))
--print("checkValidThreadCount(10)", checkValidThreadCount(10))
--print("checkValidThreadCount(19)", checkValidThreadCount(19))

local function printStat()

    local starr: {Statistic} = sim.getStatistic()

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
        for k, v in pairs(st as {string: number}) do
            --imgui.Text(string.format('%s:' .. formatMods[k as Statistic.Types], k, v))
            if imgui.CollapsingHeader(string.format('%s:' .. formatMods[k as Statistic.Types], k, v), true) then
            --if imgui.CollapsingHeader(string.format('%s:' .. formatMods[k as Statistic.Types], k, v), false) then
                local someText = "formatMods." .. k as Statistic.Types
                imgui.Text(i18n(someText))
            end
        end
    end
end

local function activatePreset(num: integer)
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
    -- update snaphots list
    loadStates()
end

local function start()
    commonSetup.spreadPoint = { 
        x = math.floor(commonSetup.gridSize / 2),
        y = math.floor(commonSetup.gridSize / 2)
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
        --profi:start()
    end
end

local function moveStart()
    commonSetup.spreadPoint = { 
        x = math.floor(commonSetup.gridSize / 2),
        y = math.floor(commonSetup.gridSize / 2)
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
        y = math.floor(commonSetup.gridSize / 2)
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
    local status: boolean

    local function wrap(n: integer|number, status: boolean): integer, boolean
        return math.floor(n), status
    end

    commonSetup.nofood = imgui.Checkbox(i18n("nofood"), commonSetup.nofood)

    commonSetup.initialEnergy[1], status = imgui.SliderInt('minimum energy', commonSetup.initialEnergy[1], 0, maxEnergy)
    commonSetup.initialEnergy[2], status = imgui.SliderInt('maximum energy', commonSetup.initialEnergy[2], 0, maxEnergy)

    commonSetup.cellsNum, status = wrap(imgui.SliderFloat(i18n("initpopulation"), commonSetup.cellsNum, 0, maxCellsNum))
    --commonSetup.cellsNum = math.ceil(commonSetup.cellsNum)

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
    --collectgarbage()

    profi:stop()
    profi:setSortMethod("duration")
    profi:writeReport("init-profile-duration.txt")
    profi:setSortMethod("count")
    profi:writeReport("init-profile-count.txt")

    sim.shutdown()
    mode = 'stop'
    --prof.pop()
    --print("written")
end

local drFloat = 10.9
--local drFloats = {10.9, 0.1}

local function drawLog()
    --imgui.SetNextWindowPos(0, 0)
    --imgui.Begin('log', false, "NoTitleBar|NoMove|NoResize")
    --imgui.End()
end

local type SimulatorLog = record
    new: function(): SimulatorLog
    add: function(string)
end

local SimulatorLog_mt: metatable<SimulatorLog> = {
    __index = SimulatorLog,
}

function SimulatorLog:new(): SimulatorLog
    local o: SimulatorLog = {}
    return setmetatable(o, SimulatorLog_mt)
end

local function drawSim()
    imgui.Begin("sim", false, "AlwaysAutoResize")

    local num, status: number, boolean

    local presetsNamesByZeros = ""
    for _, v in ipairs(presetsNames) do
        presetsNamesByZeros  = presetsNamesByZeros .. v .. "\0"
    end
    num, status = imgui.Combo("preset", selectedPreset, presetsNamesByZeros, #presetsNames)
    if status then
        selectedPreset = math.modf(num)
        activatePreset((num + 1.0) as integer)
    end

    imgui.Spacing()
    --if imgui.Button("save preset") then
    ---- TODO открыть режим модального диалога
    --end
    if mode == "stop" then
        roundSettings()
    end
    if imgui.Button("collectgarbage") then
        collectgarbage()
    end
    if imgui.Button("get 1GB RAM" .. string.format(" (usage %d mbytes)", (collectgarbage("count") as number)/ 1024)) then
        local t: {number, {integer}} = {}
        for _ = 1, 1000000 * 5 * 3 do
            local k = math.random()
            --for _ = 1, 10 do
                --for _ = 1, 10 do
                    --local value = math.sin(love.timer.getTime())
                    ----print("value", value)
                    --local r = math.random()
                    --for _ = 1, 5 do 
                        --k = k * math.pow(value, value) * r
                    --end
                --end
            --end
            table.insert(t, k)
            --for k = 1, #mem do
            --for i = 1, #mem do
                --if mem[i] ~= 0. then
                    --mem[i] = 2.0 / mem[i]
                --end
            --end
        end
        for _ = 1, 100000 do
            --table.insert(t[1][1], j)
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
    -- TODO использовать BeginCombo/EndCombo для создания динамичного списка.
    local statesByZeros = ""
    for _, v in ipairs(states) do
        statesByZeros = statesByZeros .. v .. "\0"
    end
    num, status = imgui.Combo('state', selectedState, statesByZeros, #states)
    --num, status = imgui.Combo('state', selectedState, states, #states)
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
        --writeState()
    end
    imgui.SameLine()
    if imgui.Button(">>") then
        --writeState()
    end

    --foodProduction = imgui.InputTextMultiline("[Lua]: function(iter: number): ", foodProduction, 200, 300);
    imgui.Text(string.format("uptime %d sec", sim.getUptime()))

    --imgui.ArrowButton("hi", "")
    imgui.Bullet()
    drFloat, status = imgui.DragFloat('drug', drFloat, 1, 0, 100)
    drFloat, status = imgui.SliderAngle('resonator', drFloat, 0, 360)

    --local mx, my = love.mouse.getPosition()
    --local x, y, w, h = simulatorRender:getRect()

    --if underCursor and pointInRect(mx, my, x, y, w, h) then
    if underCursor then
        drawCellInfo(underCursor, cellUnderCursor)
    end

    imgui.End()
end

local function drawBrief()
    --imgui.Begin('brief', false, 'AlwaysAutoResize')
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
        --mem[#mem + 1] = t
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
       --if imgui.BeginPopupModal('Колония умерла') then
       --imgui.Begin('Колония умерла', false, "NoTitleBar|NoMove|NoResize|AlwaysAutoResize")
       --imgui.Begin('Колония умерла', false, "NoTitleBar|NoMove|NoResize")
       local window_bg = { 1, 0, 0, 1 }
       imgui.PushStyleColor("WindowBg", window_bg[1], window_bg[2], window_bg[3], window_bg[4])
       local windowCapture = 'Колония умерла'
       imgui.Begin(windowCapture, false, "NoMove|NoResize|AlwaysAutoResize")
       --print('imgui.GetWindowSize()', imgui.GetWindowSize())

       --local window_w, window_h = 900, 300
       --imgui.SetWindowSize(windowCapture, window_w, window_h, "Always")

       local window_w, window_h = imgui.GetWindowSize()
       local w, h = gr.getDimensions()
       local posx, posy: integer = math.ceil((w - window_w) / 2), math.ceil((h - window_h) / 2)
       imgui.SetWindowPos(windowCapture, posx, posy, "Always")

       imgui.PushAllowKeyboardFocus(false)


       --imgui.PushItemWidth(100)
       print(i18n('nextplay'))
       if imgui.Button(i18n('nextplay')) then
            start()
           --local button_w, button_h = 100, 100
           --if imgui.Button('nextplay') then
           --if imgui.Button('nextplay', button_w, button_h) then


           --if imgui.BeginPopupModal("blahblah") then
               --imgui.EndPopup()
           --end

           --imgui.PopItemWidth()
           --if imgui.BeginPopupModal('Colony died', false, 'MenuBar') then
           --if imgui.BeginPopupModal('Colony died', false, 'MenuBar') then
           --local r1, r2 = imgui.BeginPopupModal('Colony died', false, 'Modal|AlwaysAutoResize|Popup') 
           --local r1, r2 = imgui.Begin('Colony died', false, 'Modal|AlwaysAutoResize|Popup') 
           --local r1, r2 = imgui.BeginPopupModal('Colony died', false, 'Modal|AlwaysAutoResize|Popup')  
           --print('BeginPopupModal', r1, r2)
           --if r1 then
           --imgui.Text('some text')
           --if imgui.Button('OK') then
           ---- рестар
           --end
           end
           if imgui.Button(i18n('progress')) then

           end
           if imgui.Button(i18n('exit')) then
               love.event.quit()
           end
           --imgui.EndPopup()
           imgui.PopAllowKeyboardFocus()
           imgui.End()
           imgui.PopStyleColor()
       --end
   end
end

local function draw()
    if viewState == "sim" then
        --local zazor: number = 10

        --profi:start()

        -- рисовать несколько симуляторов разных поколений
        simulatorRender:draw()

        --profi:stop()

        if underCursor then
            --simulatorRender:drawCellPath(cellUnderCursor)
        end

    elseif viewState == "graph" then
--        drawGraphs()
    end
    linesbuf:draw()
    --prof.pop("frame")
end

--local function checkMouse()
    --if love.mouse.isDown(1) then
        --if not mouseCapture then
            --mouseCapture = { 
                --x = love.mouse.getX(),
                --y = love.mouse.getY(),
                --dx = 0,
                --dy = 0,
            --}
        --else
            --mouseCapture.dx = mouseCapture.x - love.mouse.getX()
            --mouseCapture.dy = mouseCapture.y - love.mouse.getY()
        --end
    --else
        --mouseCapture = nil
    --end
--end

local function updateMouseToCamera()
    if simulatorRender then
        local mx, my = love.mouse.getPosition()
        underCursor = simulatorRender:mouseToCamera(mx, my)
    end
end

local function update(dt: number)
    --prof.push("frame")
    linesbuf:pushi(string.format('FPS %d', love.timer.getFPS()))
    linesbuf:pushi(string.format('scale %f, %f', cam.scale, cam.scale))
    linesbuf:update()
    simulatorRender:update(dt)
    cellUnderCursor = getCellUnderCursor(underCursor)
    timer:update(dt)
    binds.cameraControlUpdate(dt)
    --prof.push("sim.update")
    sim.update(dt)
    --prof.pop("sim.update")

    updateMouseToCamera()

    if love.mouse.isDown(1) then
        startGrap = {love.mouse.getPosition()}
        --linesbuf:push(2, 'startGrap ' .. inspect(startGrap))
    else
        startGrap = nil
    end
end

local function loadPresets()
    local chunk, errmsg = love.filesystem.load("scenes/automato/presets.lua")
    printLog("chunk, errmsg", chunk, errmsg)
    local loadedPresets = (chunk as function)() as {string: CommonSetup}
    printLog("presets", inspect(presets))
    for k, v in pairs(loadedPresets) do
        table.insert(presetsNames, k)
        for k1, v1 in pairs(commonSetup as {string: any}) do
            local tmp: {string: any} = v as {string: any}
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
        function(sc: Shortcut): boolean, Shortcut
            updateMouseToCamera()
            cam:zoom(1.01)
            return false, sc
        end,
        "zoom camera out",
        "zoomout"
    )

    KeyConfig.bind(
        "isdown",
        { key = "x" },
        function(sc: Shortcut): boolean, Shortcut
            updateMouseToCamera()
            cam:zoom(0.99)
            return false, sc
        end,
        "zoom camera in",
        "zoomin"
    )

    KeyConfig.bind(
        "keypressed",
        { key = "q" }, 
        function(sc: Shortcut): boolean, Shortcut
            --prof.write("prof.mpack")
            printLog('prof.mpack written')
            return false, sc
        end, 
        "write profiler report to file",
        "writeprofreport"
    )

    KeyConfig.bind(
        "keypressed",
        { key = "escape" }, 
        function(sc: Shortcut): boolean, Shortcut
            love.event.quit()
            return false, sc
        end, 
        "close program",
        "exit"
    )

    KeyConfig.bind(
        "keypressed",
        { mod = { "alt" }, key = "1" }, 
        function(sc: Shortcut): boolean, Shortcut
            love.event.quit()
            return false, sc
        end, 
        "Show graph1",
        "graph1"
    )

    KeyConfig.bind(
        "keypressed",
        { mod = { "alt" }, key = "2" }, 
        function(sc: Shortcut): boolean, Shortcut
            love.event.quit()
            return false, sc
        end, 
        "Show graph2",
        "graph2"
    )

    KeyConfig.bind(
        "isdown",
        { mod = { "lctrl" }, key = "3" }, 
        function(sc: Shortcut): boolean, Shortcut
            love.event.quit()
            return false, sc
        end, 
        "Show graph3",
        "graph3"
    )

    KeyConfig.bind(
        "isdown",
        { mod = { "lctrl" }, key = "4" }, 
        function(sc: Shortcut): boolean, Shortcut
            love.event.quit()
            return false, sc
        end, 
        "Show graph4",
        "graph4"
    )

    KeyConfig.bind(
        "keypressed",
        { key = 'p' },
        function(sc: Shortcut): boolean, Shortcut
            nextMode()
            return false, sc
        end,
        'switch simulator to next execution mode',
        'nextmode'
    )

    KeyConfig.bind(
        "keypressed",
        { key = 's' },
        function(sc: Shortcut): boolean, Shortcut
            sim.step()
            linesbuf:push(linesbufDelay, 'forward step')
            return false, sc
        end,
        'do a simulation step',
        'step'
    )

    KeyConfig.bind(
        "keypressed",
        { key = 'c' },
        function(sc: Shortcut): boolean, Shortcut
            --sim.step()
            sim.setMode('continuos')
            linesbuf:push(linesbufDelay, 'continuos ..')
            return false, sc
        end,
        'go to continuos mode',
        'continuos'
    )

    KeyConfig.bind(
        "keypressed",
        { key = 'space' },
        function(sc: Shortcut): boolean, Shortcut
            start()
            return false, sc
        end,
        'start',
        'start'
    )
    
    KeyConfig.bind(
        'keypressed',
        { key = 'l' },
        function(sc: Shortcut): boolean, Shortcut
            if i18n.getLocale() == 'en' then
                i18n.setLocale('ru')
            elseif i18n.getLocale() == 'ru' then
                i18n.setLocale('en')
            end
            return false, sc
        end,
        'change locale',
        'chlocale'
    )

    KeyConfig.bind(
        'keypressed',
        { mod = { 'lctrl' }, key = 'p' },
        function(sc: Shortcut): boolean, Shortcut
            useProfi = not useProfi 
            return false, sc
        end,
        'enable or disable profiler. Dev only',
        'profiler'
    )

    KeyConfig.bind(
        'keypressed',
        { key = '0' },
        function(sc: Shortcut): boolean, Shortcut
            simulatorRender.enabled = not simulatorRender.enabled
            return false, sc
        end,
        'enable or disable rendering. Dev only',
        'enablerender'
    )
end

local function clearLogs()
    love.filesystem.write('printstat.txt', "")
end

local function init()
    clearLogs()
    printLog("automato init()")
    love.filesystem.createDirectory('snaphots')
    loadLocales()
    local mx, my = love.mouse.getPosition()
    underCursor = {x = math.floor(mx), y = math.floor(my)}

    cam = camera.new()
    simulatorRender = SimulatorRender.new(commonSetup, cam)

    bindKeys()
    loadPresets()
    loadStates()
    printLog("automato init done.")
end

local function quit()
    --prof.write('prof.mpack')
    printLog('prof.mpack written')
    love.filesystem.write('camera.txt', '')
    if simulatorRender then
        love.filesystem.append('camera.txt', serpent.dump(simulatorRender.cam))
    end
end

--[[
local function checkCursorBounds(x: integer, y: integer): integer, integer
    if x <= 0 then 
        x = 1
    end
    if x > commonSetup.gridSize then
        x = commonSetup.gridSize
    end
    if y <= 0 then 
        y = 1
    end
    if y > commonSetup.gridSize then
        y = commonSetup.gridSize
    end
    return x, y
end
--]]

local function mousemoved(_: number, _: number, dx: number, dy: number)
    --underCursor = simulatorRender:mouseToCamera(x, y)
    --linesbuf:push(1, string.format('underCursor %d, %d', underCursor.x, underCursor.y))
    --underCursor.x, underCursor.y = checkCursorBounds(underCursor.x, underCursor.y)
    if startGrap then
        linesbuf:push(2, 'mousemoved')
        simulatorRender.cam:move(-dx, -dy)
    end
end

local function wheelmoved(_: number, y: number)
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
    wheelmoved = wheelmoved
}

--[[ Клеточный автомат-симулятор. Действие происходит на плоском поле в клетку, замкнутом на себя. Создается популяция клеток которые двигаются по 
сгенерированной случайным образом программе из простого языка.
Клетки питаются едой(зеленый цвет) и имеют конечный запас энергии.
Цель игры - создать и развить долгоживущюю популяцию.
--]]

require "love"
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
package.path = package.path .. ";scenes/automato/?.lua"
require "common"
require "imgui"
require "simulator-render"
require "types"

-- режит отображения
local type ViewState = enum
    "sim"
    "graph"
end

global PROF_CAPTURE = false

local serpent = require "serpent"
local linesbuf = require 'kons'.new()
local camera = require "camera"
--local gr = love.graphics
--local imgui = require "love-imgui"
local inspect = require "inspect"
local mtschemes = require "mtschemes"
local prof = require "jprof"
local sim = require "simulator"
local startInStepMode = false
local binds = require "binds"
local i18n = require "i18n"
local profi = require "profi"
local linesbufDelay = 1
local viewState: ViewState = "sim"
local underCursor: Pos = {}
local simulatorRender: SimulatorRender
local cam: Camera
local useProfi = false
local mode: SimulatorMode = "stop"
--local foodProduction: string = ''
local maxCellsNum = 5000
local snaphotsDirectory = 'snaphots'
local cellUnderCursor: Cell
local timer: Timer = require "Timer".new()
local cameraZoomTimeout = 0.5
local startGrap = {}

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
    print("locale files", inspect(files))
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
    print("i18n", inspect(i18n))
end

local function loadStates()
    local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
    print('loadStates', inspect(files))
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
    --linesbuf:pushi('drawCellInfo')
    local mx, my = love.mouse.getPosition()

    -- сделать нормальное выделение клетки под курсором

    imgui.SetNextWindowPos(mx, my)
    imgui.Begin('info', false, "NoTitleBar|NoMove|NoResize|AlwaysAutoResize")
    local msg: string
    --print('drawCellInfo', inspect(cell))
    --[[
    --]]
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
            print('drawCellInfo', msg)
            --imgui.LabelText(k as string, tostring(msg))
            imgui.Text(k as string .. " " .. tostring(msg))
        end
    end
    --]]

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
local function checkValidThreadCount(threadCount: number): number
    --if not mtschemes[commonSetup.threadCount] then
    --local threadCount = commonSetup.threadCount
    local prev = 1
    local ok = false
    for k, _ in pairs(mtschemes as {any:any}) do
        if k as number == threadCount then
            ok = true
            break
        end
        prev = k as number
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

    print("starr = ", inspect(starr))
    --print("#starr", #starr)
    --print("prevStat", inspect(prevStat))

    -- XXX работает ли такая подмена массива?
    if #starr ~= 0 then
        prevStat = deepCopy(prevStat)
    elseif #starr == 0 and prevStat then
        starr = prevStat
        print("used prevStat", inspect(prevStat))
    end

    -- XXX hack
    if #starr > 1 then
        table.remove(starr, 2)
    end

    love.filesystem.append('printstat.txt', string.format("starr = %s\n", inspect(starr)))

    for _, st in ipairs(starr) do
        for k, v in pairs(st as {string: number}) do
            --imgui.Text(string.format('%s:' .. formatMods[k as Statistic.Types], k, v))
            if imgui.CollapsingHeader(string.format('%s:' .. formatMods[k as Statistic.Types], k, v), true) then
            --if imgui.CollapsingHeader(string.format('%s:' .. formatMods[k as Statistic.Types], k, v), false) then
                --imgui.Text(string.format('%s:' .. formatMods[k as Statistic.Types], k, v))
                --imgui.SameLine()
                --imgui.Text(string.format('%s:' .. formatMods[k as Statistic.Types], k, v))
                --print(k, v)
                local someText = "formatMods." .. k as Statistic.Types
                print('someText', someText)
                imgui.Text(i18n(someText))
            end
            --print('CollapsingHeader', r1, r2)
            --if (ImGui::CollapsingHeader("Window options"))
        end
    end
end

local function activatePreset(num: number)
    commonSetup = shallowCopy(presets[num])
end

local function readState()
    local fname = snaphotsDirectory .. '/' .. states[selectedState + 1]
    print('readState', fname)
    local fileData = love.filesystem.read(fname)
    print('#fileData', #fileData)
    if not sim.readState(fileData) then
        linesbuf:push(linesbufDelay, 'could not load state')
    end
end

local function writeState()
    local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
    print('files', inspect(files))
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
local drFloats = {10.9, 0.1}

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
        selectedPreset = num
        activatePreset(num + 1)
    end

    imgui.Spacing()
    --if imgui.Button("save preset") then
    ---- TODO открыть режим модального диалога
    --end
    if mode == "stop" then
        roundSettings()
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
        selectedState = num
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

    local mx, my = love.mouse.getPosition()
    local x, y, w, h = simulatorRender:getRect()

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
    imgui.End()
end

local function drawui()
    imgui.StyleColorsLight()

    imgui.ShowDemoWindow()
    imgui.ShowUserGuide()

    drawSim()
    drawLog()
    drawBrief()

    if sim.isColonyDied() then
        --imgui.BeginPopupModal('Колония умерла')
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
        --end
            --imgui.EndPopup()
        --imgui.End()
    end
end

local function draw()
    if viewState == "sim" then
        --local zazor: number = 10

        -- рисовать несколько симуляторов разных поколений
        simulatorRender:draw()

        --[[
        gr.push()
        simulatorRender.cam:attach()
        local canvasx, canvasy = simulatorRender.fieldWidthPixels + zazor, 0
        gr.draw(simulatorRender.canvas as love.graphics.Drawable, canvasx, canvasy)
        simulatorRender.cam:detach()
        gr.pop()
        --]]
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

local function update(dt: number)
    --prof.push("frame")
    linesbuf:pushi(string.format('FPS %d', love.timer.getFPS()))
    linesbuf:update()
    simulatorRender:update(dt)
    cellUnderCursor = getCellUnderCursor(underCursor)
    timer:update(dt)
    sim.update(dt)

    if simulatorRender then
        local mx, my = love.mouse.getPosition()
        underCursor = simulatorRender:mouseToCamera(mx, my)
    end

    if love.mouse.isDown(1) then
        startGrap = {love.mouse.getPosition()}
        --linesbuf:push(2, 'startGrap ' .. inspect(startGrap))
    else
        startGrap = nil
    end
end

local function loadPresets()
    local chunk, errmsg = love.filesystem.load("scenes/automato/presets.lua")
    print("chunk, errmsg", chunk, errmsg)
    local loadedPresets = (chunk as function)() as {string: CommonSetup}
    print("presets", inspect(presets))
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
        "keypressed",
        { key = "q" }, 
        function(sc: Shortcut): boolean, Shortcut
            --prof.write("prof.mpack")
            print('prof.mpack written')
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
    print("automato init()")
    love.filesystem.createDirectory('snaphots')
    loadLocales()
    local mx, my = love.mouse.getPosition()
    underCursor = {x = mx, y = my}

    cam = camera.new()
    simulatorRender = SimulatorRender.new(commonSetup, cam)

    bindKeys()
    loadPresets()
    loadStates()
    print("automato init done.")
end

local function quit()
    --prof.write('prof.mpack')
    print('prof.mpack written')
    love.filesystem.write('camera.txt', '')
    if simulatorRender then
        love.filesystem.append('camera.txt', serpent.dump(simulatorRender.cam))
    end
end

local function checkCursorBounds(x: number, y: number): number, number
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

local function mousemoved(x: number, y: number, dx: number, dy: number)
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

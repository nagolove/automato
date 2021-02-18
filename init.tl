--[[
Клеточный автомат-симулятор. Действие происходит на плоском поле в клетку, 
замкнутом на себя. Создается популяция клеток которые двигаются по 
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

local linesbuf = require 'kons'.new()
local camera = require "camera"
local gr = love.graphics
local imgui = require "imgui"
local inspect = require "inspect"
local mtschemes = require "mtschemes"
--local prof = require "jprof"
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
local foodProduction: string = ''
local maxCellsNum = 5000
local snaphotsDirectory = 'snaphots'

--[[ Начальные установки симуляции ]]
local commonSetup: CommonSetup = {
    -- размер сетки одного потока
    gridSize = 50,
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
    denergy = 1,
    foodenergy = 10,
    emitInvSpeed = 1
}

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
    i18n.setLocale('en')
    print("i18n", inspect(i18n))
end

-- возвращает структуру клетки под курсором pos
local function getCell(pos: Pos): Cell
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

local function replaceCaret(str: string): string
    return string.gsub(str, "\n", "") as string
end

local function drawCellInfo(cell: Cell)
    if not cell then
        return
    end

    -- сделать нормальное выделение клетки под курсором
    if next(cell as {any:any}) ~= nil then
        local mx, my = love.mouse.getPosition()
        gr.setColor(1, 0, 0)
        --gr.circle("line", mx, my, pixSize * cam.scale)
        gr.circle("line", mx, my, 5)
    end

    local msg: string
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
            imgui.LabelText(k as string, msg)
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

local prevStat: {Statistic}

local function printStat()
    local starr: {Statistic} = sim.getStatistic()

    print("starr = ", inspect(starr))
    print("#starr", #starr)
    print("prevStat", inspect(prevStat))

    -- XXX работает ли такая подмена массива?
    if #starr ~= 0 then
        prevStat = deepCopy(prevStat)
    elseif #starr == 0 and prevStat then
        starr = prevStat
        print("used prevStat", inspect(prevStat))
    end

    for _, st in ipairs(starr) do
        for k, v in pairs(st as {string: number}) do
            imgui.Text(string.format('%s:' .. formatMods[k as Statistic.Types], k, v))
        end
    end
end

-- открыт ли модальный диалог(пока только сохранение пресета)
--local ismodal = false

local presetsNames: {string} = {}
local presets: {CommonSetup} = {}
local selectedPreset = 1

local function activatePreset(num: number)
    commonSetup = shallowCopy(presets[num])
end

local function readState()
    -- тут какой-то список сохраненных на диске состояний
    -- как отображать список? ограниченное количество сохранений?
    -- инкрементальное именование числами?
    --sim.readState()
end

local function writeState()
    local files = love.filesystem.getDirectoryItems(snaphotsDirectory)
    print('files', inspect(files))
    local res = sim.writeState()
    local fname = snaphotsDirectory .. string.format("/sim-%d.data", #files)
    love.filesystem.write(fname, res)
end

local function start()
    --if sim.getMode() == "stop" then
    commonSetup.spreadPoint = { 
        x = math.floor(commonSetup.gridSize / 2),
        y = math.floor(commonSetup.gridSize / 2)
    }
    commonSetup.spreadRad = math.floor(commonSetup.gridSize / 2)
    commonSetup.mode = 'continuos'
    mode = 'continuos'
    sim.create(commonSetup)
    simulatorRender = SimulatorRender.new(commonSetup, cam)
    simulatorRender:cameraToCenter()
    --end
    if useProfi then
        profi:start()
    end
end

local function roundSettings()
    local _, status: number, boolean

    commonSetup.nofood = imgui.Checkbox(i18n("nofood"), commonSetup.nofood)

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
    --prof.write('prof.mpack')
    --print("written")
end

local function drawui()
    linesbuf:draw()

    imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

    local num, status: number, boolean
    num, status = imgui.Combo("preset", selectedPreset, presetsNames, #presetsNames)
    if status then
        selectedPreset = num
        activatePreset(num)
    end

    --if imgui.Button("save preset") then
        ---- TODO открыть режим модального диалога
    --end

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
        --writeState()
    end
    imgui.SameLine()
    if imgui.Button(">>") then
        --writeState()
    end

    foodProduction = imgui.InputTextMultiline("[Lua]: function(iter: number): ", foodProduction, 200, 300, 200);
    imgui.Text(string.format("uptime %d sec", sim.getUptime()))

    printStat()

    imgui.End()
end

local function draw()
    if viewState == "sim" then
        local zazor: number = 10
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
            -- XXX FIXME Not work
            local cell = getCell(underCursor)
            --print("cell", inspect(cell))

            drawCellInfo(cell)
            --simulatorRender.cam:attach()
            simulatorRender:drawCellPath(cell)
            --simulatorRender.cam:detach()
        end

    elseif viewState == "graph" then
--        drawGraphs()
    end
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
    linesbuf:pushi(string.format('FPS %d', love.timer.getFPS()))
    linesbuf:update()
    simulatorRender:update(dt)
    sim.update(dt)
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
end

local function init()
    print("automato init()")
    love.filesystem.createDirectory('snaphots')
    loadLocales()
    local mx, my = love.mouse.getPosition()
    underCursor = {x = mx, y = my}

    cam = camera.new()
    simulatorRender = SimulatorRender.new(commonSetup, cam)

    bindKeys()
    loadPresets()
    print("automato init done.")
end

local function quit()
end

local function mousemoved(x: number, y: number, _: number, _: number)
    local w, h = gr.getDimensions()
    local tlx, tly, brx, bry = 0, 0, w, h

    if cam then
        tlx, tly = cam:worldCoords(tlx, tly)
        brx, bry = cam:worldCoords(brx, bry)
    end

    underCursor = {
        x = math.floor(x / simulatorRender:getPixSize()),
        y = math.floor(y / simulatorRender:getPixSize())
    }
end

local function wheelmoved(_: number, y: number)
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
    wheelmoved = wheelmoved
}

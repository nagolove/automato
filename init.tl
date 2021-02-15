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

local camera = require "camera"
local gr = love.graphics
local imgui = require "imgui"
local inspect = require "inspect"
local keyconfig = require "keyconfig"
local mtschemes = require "mtschemes"
local prof = require "jprof"
local sim = require "simulator"
local startInStepMode = false
local timer = require "Timer"
local binds = require "binds"
--local profi = require "profi"

global PROF_CAPTURE = true

local type ViewState = enum
    "sim"
    "graph"
end

-- режит отображения "sim" или "graph"
local viewState: ViewState = "sim"
local underCursor: Pos = {}
local simulatorRender: SimulatorRender
local cam: Camera

-- канва для рисования графиков
-- проверить на максильный размер при запуске на телефоне
print("graphics size", gr.getWidth(), gr.getHeight())
--local graphCanvas = gr.newCanvas(gr.getWidth(), gr.getHeight())

-- цвета графиков
--local MAX_ENERGY_COLOR = {1, 0.5, 0.7, 1}
--local MID_ENERGY_COLOR = {0.8, 0.3, 0.7, 1}
--local MIN_ENERGY_COLOR = {0.6, 0.1, 1, 1}

-- ?? инфа с последним изменением статистики 
--local lastGraphicPoint

-- режим работы - непрерывный или пошаговый continuos, bystep
local mode: SimulatorMode = "continuos"

--[[
--Начальные установки симуляции
--]]
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

local maxCellsNum = 5000
local infoTimer: Timer = timer.new()
local threadsInfo: {ThreadInfo}
--local simulatorCanvas: love.graphics.Canvas

local function getMode(): SimulatorMode
    return mode
end

--[[
local function drawStatisticTable()
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
--]]

--function drawAxises()
    --gr.setColor(0, 1, 0)
    --local w, h = gr.getDimensions()
    --gr.setLineWidth(3)
    --gr.line(0, h, 0, 0)
    --gr.line(0, h, w, h)
    --gr.setLineWidth(1)
--end

--local function drawLegends()
    --local y0 = 0

    --gr.setColor(MAX_ENERGY_COLOR)
    --gr.print("max energy", 0, y0)
    --y0 = y0 + gr.getFont():getHeight()

    --gr.setColor(MID_ENERGY_COLOR)
    --gr.print("mid energy", 0, y0)
    --y0 = y0 + gr.getFont():getHeight()

    --gr.setColor(MIN_ENERGY_COLOR)
    --gr.print("min energy", 0, y0)
    --y0 = y0 + gr.getFont():getHeight()
--end

--local function drawGraphs()
    --drawAxises()
    --drawLegends()
    --gr.draw(graphCanvas as gr.Drawable)
--end

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
Подобрать оптимальный алгоритм
Работает в большую сторону, а не меньшую
--]]
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

-- открыт ли модальный диалог(пока только сохранение пресета)
--local ismodal = false

local presetsNames: {string} = {}
local presets: {CommonSetup} = {}
local selectedPreset = 1

local function activatePreset(num: number)
    commonSetup = shallowCopy(presets[num])
end

local function writeState()
    local res = sim.writeState()
    love.filesystem.write("sim.data", res)
end

local function start()
    simulatorRender = SimulatorRender.new(commonSetup, cam)
    sim.create(commonSetup)
end

local function drawui()
    imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

    local num, status: number, boolean
    num, status = imgui.Combo("preset", selectedPreset, presetsNames, #presetsNames)
    if status then
        selectedPreset = num
        activatePreset(num)
    end

    if imgui.Button("save preset") then
        -- TODO открыть режим модального диалога
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
    if simulatorRender and status then
        simulatorRender:draw()
        simulatorRender:cameraToCenter()
    end

    commonSetup.threadCount, status = imgui.SliderInt("thread count", commonSetup.threadCount, 1, 9)
    commonSetup.threadCount = checkValidThreadCount(commonSetup.threadCount)
    if simulatorRender and status then
        simulatorRender:draw()
        simulatorRender:cameraToCenter()
    end

    status = imgui.Checkbox("start in step mode", startInStepMode)
    startInStepMode = status

    if startInStepMode then
        commonSetup.mode = "step"
    end

    if imgui.Button("reset silumation") then
        --collectgarbage()

        --profi:stop()
        --profi:setSortMethod("duration")
        --profi:writeReport("init-profile-1.txt")
        --profi:setSortMethod("count")
        --profi:writeReport("init-profile-2.txt")
        sim.shutdown()

        prof.pop()
        prof.write('prof.mpack')
        print("written")
    end

    if imgui.Button("start") then
        start()
        --profi:start()
        --sim.setMode("step")
    end

    if imgui.Button("step") then
        sim.step()
    end

    if imgui.Button("write state") then
        writeState()
    end

    --imgui.Text(replaceCaret(inspect(sim.getStatistic)) as string)

    --if sim.getStatistic() and sim.getStatistic().allEated then
        --imgui.LabelText(sim.getStatistic().allEated, "all eated")
    --end

    imgui.Text(string.format("uptime %d sec", sim.getUptime()))
    -- можно запрашивать не каждый кадр
    local st: Statistic = sim.getStatistic()

    for k, v in pairs(st as {Statistic.Types:number}) do
        imgui.Text(string.format("%s: %d", st[k], v))
    end

    printThreadsInfo()

    if underCursor then
        -- XXX FIXME Not work
        local cell = getCell(underCursor)
        --print("cell", inspect(cell))

        drawCellInfo(cell)
        simulatorRender:drawCellPath(cell)
    end

    imgui.End()
end

local function draw()
    if viewState == "sim" then
        local zazor: number = 10
        simulatorRender:draw()

        gr.push()
        simulatorRender.cam:attach()
        local canvasx, canvasy = simulatorRender.fieldWidthPixels + zazor, 0
        gr.draw(simulatorRender.canvas as love.graphics.Drawable, canvasx, canvasy)
        simulatorRender.cam:detach()
        gr.pop()
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

--[[
local function updateGraphic()
    local statistic = sim.getStatistic()
    if not lastGraphicPoint then
        if statistic then
            lastGraphicPoint = {
                max = statistic.maxEnergy,
                mid = statistic.midEnergy,
                min = statistic.minEnergy,
            }
        end
    end
    local getIter = sim.getIter

    gr.setCanvas(graphCanvas)
    local w, h = graphCanvas:getDimensions()

    if lastGraphicPoint then
        if lastGraphicPoint.max then
            gr.setColor(MAX_ENERGY_COLOR)
            gr.line(getIter() - 1, h - lastGraphicPoint.max, 
            getIter(), h - statistic.maxEnergy)
        end

        if lastGraphicPoint.mid then
            gr.setColor(MID_ENERGY_COLOR)
            gr.line(getIter() - 1, h - lastGraphicPoint.mid, 
            getIter(), h - statistic.midEnergy)
        end

        if lastGraphicPoint.min then
            gr.setColor(MIN_ENERGY_COLOR)
            gr.line(getIter() - 1, h - lastGraphicPoint.min, 
            getIter(), h - statistic.minEnergy)
        end
    end

    gr.setCanvas()

    if statistic and statistic.maxEnergy and statistic.midEnergy and statistic.minEnergy then
        lastGraphicPoint = {
            max = statistic.maxEnergy,
            mid = statistic.midEnergy,
            min = statistic.minEnergy,
        }
    end
end
--]]

local function update(dt: number)
    infoTimer:update(dt)

    --controlCamera(cam)
    simulatorRender:update(dt)
    sim.step()
    
    --updateGraphic()
    --checkMouse()
end

function setViewState(stateName: ViewState)
    viewState = stateName
end

local function keypressed(key: string)
    if key == "1" then
        setViewState("sim")
    elseif key == "2" then
        setViewState("graph")
    elseif key == "p" then
        nextMode()
    elseif key == "s" then
        sim.doStep()
    elseif key == "space" then
        --[[ TODO Запуск и пауза/продолжение ]]
        --if sim.getMode() == "stop" then
            --sim.create(commonSetup)
        --else
            --sim.step()
        --end
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

end

local function init()
    math.randomseed(love.timer.getTime())
    local mx, my = love.mouse.getPosition()
    underCursor = {x = mx, y = my}

    cam = camera.new()
    simulatorRender = SimulatorRender.new(commonSetup, cam)

    bindKeys()

    threadsInfo = {{cells = 0, meals = 0}}

    infoTimer:every(0.1, function(_: number)
        local info = sim.getThreadsInfo()
        --print("infO", inspect(info))
        if info then
            threadsInfo = info
        else
            print("no info")
        end
    end)

    --print("simulatorRender", inspect(simulatorRender))
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

    --print("simulatorRender2", inspect(simulatorRender))
    --simulatorRender:p()
    --print(simulatorRender.cam)
    -- не приводятся координаты при движении камеры и масштабировании
    underCursor = {
        x = math.floor(x / simulatorRender:getPixSize()),
        y = math.floor(y / simulatorRender:getPixSize())
    }
end

local function wheelmoved(_: number, y: number)
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

    --PIX2M = PIX2M,
    --M2PIX = M2PIX,

    init = init,
    quit = quit,
    draw = draw,
    drawui = drawui,
    update = update,
    keypressed = keypressed,
    mousemoved = mousemoved,
    wheelmoved = wheelmoved
}
--]]

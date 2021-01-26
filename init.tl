--[[
--Клеточный автомат-симулятор. Действие происходит на плоском поле в клетку,
--замкнутом на себя.
--Создается популяция клеток которые двигаются по сгенерированной случайным
--образом программе из простого языка.
--Клетки питаются едой(зеленый цвет) и имеют конечный запас энергии.
--]]
require "love"
love.filesystem.setRequirePath("scenes/automato/?.lua")

require "external"
require "types"

package.path = package.path .. ";scenes/automato/?.lua"

local imgui = require "imgui"
local cam = require "camera".new()
local inspect = require "inspect"
local gr = love.graphics
local sim = require "simulator"

global type ViewState = enum
    "sim"
    "graph"
end

-- режит отображения "sim" или "graph"
local viewState: ViewState = "sim"

-- если ~= nil, то содержит табличку с координатами клетки под курсором
local record MouseCapture
    x: number
    y: number
    dx: number
    dy: number
end

local mouseCapture: MouseCapture
local underCursor = {}

-- канва для рисования графиков
local graphCanvas = gr.newCanvas(gr.getWidth() * 4, gr.getHeight())

-- цвета графиков
local MAX_ENERGY_COLOR = {1, 0.5, 0.7, 1}
local MID_ENERGY_COLOR = {0.8, 0.3, 0.7, 1}
local MIN_ENERGY_COLOR = {0.6, 0.1, 1, 1}

-- ?? инфа с последним изменением статистики 
--local lastGraphicPoint

-- режим работы - непрерывный или пошаговый continuos, bystep
local mode: SimulatorMode = "continuos"

-- размер клетки поля в пикселях
local pixSize: number = 10

--[[
--Начальные установки симуляции
--]]
local commonSetup: CommonSetup = {
    -- размер сетки одного потока
    gridSize = 100,
    -- количество клеток создаваемых на один поток
    cellsNum = 2000, 
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
}
local maxCellsNum = 5000

local gridLineWidth = 1

local function getMode(): SimulatorMode
    return mode
end

function drawCells()
    local drawlist = sim.getDrawLists()
    if drawlist then
        for _, v in ipairs(drawlist) do
            if v.food then
                gr.setColor(0, 1, 0)
                local x, y = (v.x - 1)* pixSize, (v.y - 1) * pixSize
                local w, h = pixSize, pixSize
                gr.rectangle("fill", x, y, w, h)
            else
                gr.setColor(0.5, 0.5, 0.5)
                local x, y = (v.x - 1)* pixSize, (v.y - 1) * pixSize
                local w, h = pixSize, pixSize
                gr.rectangle("fill", x, y, w, h)
            end
        end
    end
end

function drawGrid()
    --if sim.getMode() == "stop" then
        --gr.setColor(1, 1, 1)
        --gr.print("No simulation", 100, 100)
    --else
    do
        gr.setColor(0.5, 0.5, 0.5)
        local gridSize = commonSetup.gridSize

        if not gridSize then
            return
        end

        --local schema = sim.getSchema()
        local schema: MtSchema
        local ok, errmsg: boolean, string = pcall(function()
            schema = require "mtschemes"[commonSetup.threadCount]
        end)
        if not ok then
            print("Could'not require 'mtschemes'")
        end

        local oldWidth = {gr.getColor()}
        gr.setLineWidth(gridLineWidth)
        if schema then
            for _, v in pairs(schema as {any: any}) do
                local dx, dy = (v as MtSchema).draw[1] * pixSize * gridSize, (v as MtSchema).draw[2] * pixSize * gridSize
                for i = 0, gridSize do
                    -- vert
                    local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
                    local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
                    gr.line(x1, y1, x2, y2)
                    -- hor
                    x1, y1 = dx + 0, dy + i * pixSize
                    x2, y2= dx + gridSize * pixSize, dy + i * pixSize
                    gr.line(x1, y1, x2, y2)
                end
            end
        else
            local dx, dy = 0, 0
            for i = 0, gridSize do
                -- vert
                gr.line(dx + i * pixSize, dy + 0, dx + i * pixSize, dy + gridSize * pixSize)
                -- hor
                gr.line(dx + 0, dy + i * pixSize, dx + gridSize * pixSize, dy + i * pixSize)
            end
        end
        gr.setLineWidth(table.unpack(oldWidth))
    end
end

function drawStatisticTable()
    local y0 = 0
    gr.setColor(1, 0, 0)
--    gr.print(string.format("iteration %d", sim.getIter()), 0, y0)
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
    gr.draw(graphCanvas as gr.Drawable)
end

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

    local msg: string
    for k, v in pairs(cell as {any: any}) do
        if k ~= "code" then
            local fmt: string
            --local functor: function<T>(T): T = nil

            --local function functor(a: number): number return a end
            local a: any
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

local function getPixSize(): number
    return pixSize
end

local function drawCellPath(cell: Cell)
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

local function drawSim()
    imgui.Begin("sim", false, "ImGuiWindowFlags_AlwaysAutoResize")

    imgui.Text(string.format("mode %s", getMode()))

    if imgui.Button("change mode", getMode()) then
        nextMode()
    end

    commonSetup.nofood = imgui.Checkbox("no food", commonSetup.nofood)

    local status: boolean

    commonSetup.cellsNum, status = imgui.SliderFloat("initial population", commonSetup.cellsNum, 0, maxCellsNum)
    commonSetup.cellsNum = math.ceil(commonSetup.cellsNum)

    commonSetup.denergy, status = imgui.SliderFloat("decrease enerby by", commonSetup.denergy, 0, 1)

    commonSetup.foodenergy, status = imgui.SliderFloat("food energy", commonSetup.foodenergy, 0, 10)

    if imgui.Button("reset silumation") then
        collectgarbage()
        sim.create(commonSetup)
    end

    if imgui.Button("start") then
        sim.create(commonSetup)
        --sim.setMode("step")
    end

    if imgui.Button("step") then
        sim.step()
    end

    imgui.Text(replaceCaret(inspect(sim.getStatistic)) as string)

    if sim.getStatistic() and sim.getStatistic().allEated then
        imgui.LabelText(sim.getStatistic().allEated, "all eated")
    end

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
        --drawStatisticTable()
        cam:detach()
    elseif viewState == "graph" then
--        drawGraphs()
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

local function update()
    controlCamera(cam)

    sim.step()
    
    --updateGraphic()
    checkMouse()

    local isDown = love.keyboard.isDown
    if isDown("z") then
        cam:zoom(1.01)
    elseif isDown("x") then
        cam:zoom(0.99)
    end
end

function setViewState(stateName: ViewState)
    viewState = stateName
end

local function keypressed(key: string)
    if key == "1" then
        setViewState("sim")
    elseif key == "2" then
        setViewState("graph")
    end
    if key == "p" then
        nextMode()
    elseif key == "s" then
        sim.doStep()
    end
end

local function init()
    math.randomseed(love.timer.getTime())
    local mx, my = love.mouse.getPosition()
    underCursor = {x = mx, y = my}
end

local function quit()
end

local function mousemoved(x: number, y: number, dx: number, dy: number)
    local w, h = gr.getDimensions()
    local tlx, tly, brx, bry = 0, 0, w, h

    if cam then
        tlx, tly = cam:worldCoords(tlx, tly)
        brx, bry = cam:worldCoords(brx, bry)
    end

    underCursor = {
        x = math.floor(x / getPixSize()),
        y = math.floor(y / getPixSize())
    }
end

return {
    getPixSize = getPixSize,

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
}


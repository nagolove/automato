love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
require "love"
package.path = package.path .. ";scenes/automato/?.lua"
require "imgui"
require "common"
require "types"

--local inspect = require "inspect"
--local keyconfig = require "keyconfig"
--local prof = require "jprof"
--local profi = require "profi"
local gr = love.graphics
local mtschemes = require "mtschemes"
local sim = require "simulator"

global record SimulatorRender
    new: function(commonSetup: CommonSetup, Camera): SimulatorRender

    draw: function(SimulatorRender)
    drawCellPath: function(SimulatorRender, cell: Cell)
    prerender: function(SimulatorRender)
    drawGrid: function(SimulatorRender)
    drawCells: function(SimulatorRender)
    presentList: function(SimulatorRender, list: {DrawNode})
    
    cameraToCenter: function(SimulatorRender)
    mouseToCamera: function(SimulatorRender, x: number, y: number): Pos
    getRect: function(SimulatorRender): number, number, number, number
    update: function(SimulatorRender, number)

    getPixSize: function(SimulatorRender): number
    computeGrid: function(SimulatorRender)
    bakeCanvas: function(SimulatorRender)

    enabled: boolean
    commonSetup: CommonSetup
    cam: Camera
    fieldWidthPixels: number
    fieldHeightPixels: number
    canvas: love.graphics.Canvas
    cellCanvas: love.graphics.Canvas
    mealCanvas: gr.Canvas
end

local SimulatorRender_mt: metatable<SimulatorRender> = {
    __index = SimulatorRender,
}

-- размер клетки поля суб канваса в пикселях
--local pixSize: number = 20
--local pixSize: number = 160
local pixSize: integer = 10
-- ширина линий сетки
local gridLineWidth = 3
-- во сколько раз полотно больше размера картинки
local canvasmultfactor = 1

local gridColor = {0.5, 0.5, 0.5}
local mealcolor = {0, 1, 0, 1}
local cellcolor1 = {0.5, 0.5, 0.5, 1}
local cellcolor2 = {0, 0, 1, 1}
--local black = {0, 0, 0, 1}

local function clearCanvases(canvases: {love.graphics.Canvas}, color: {number})
    for _, canvas in ipairs(canvases) do
        gr.setCanvas(canvas)
        gr.clear(color)
        gr.setCanvas()
    end
end

function SimulatorRender.new(commonSetup: CommonSetup, cam: Camera): SimulatorRender
    local self: SimulatorRender = {
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
    print("fieldWidthPixels, fieldHeightPixels", self.fieldWidthPixels, self.fieldHeightPixels)

    self.canvas = gr.newCanvas(
        self.fieldWidthPixels * canvasmultfactor, 
        self.fieldHeightPixels * canvasmultfactor
    )

    clearCanvases(
        { self.canvas, self.cellCanvas, self.mealCanvas },
        { 0.5, 0, 0, 1}
    )

    self:prerender()
    self:cameraToCenter()
    self:draw()

    self.canvas:newImageData():encode('png', "simulator-render-canvas.png")
    self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas.png')
    self.mealCanvas:newImageData():encode('png', 'simulator-render-meal-canvas.png')

    return self
end

function SimulatorRender:getRect(): number, number, number, number
    local x, y = self.cam:cameraCoords(0, 0)
    local w = self.commonSetup.gridSize * self.cam.scale * pixSize 
    local h = self.commonSetup.gridSize * self.cam.scale * pixSize
    return x, y, w, h
end

function SimulatorRender:mouseToCamera(x: number, y: number): Pos
    local nx, ny: number, number = self.cam:worldCoords(x, y)
    return {
        x = math.ceil((nx / self:getPixSize()) * self.cam.scale),
        y = math.ceil((ny / self:getPixSize()) * self.cam.scale)
        --x = math.floor((nx / self:getPixSize()) * self.cam.scale),
        --y = math.floor((ny / self:getPixSize()) * self.cam.scale)
    }
end

function SimulatorRender:cameraToCenter()
    local w, h = gr.getDimensions()
    --print(self.canvas)
    --local w, h = (self.canvas as gr.Texture):getDimensions()
    print('w, h', w, h)
    -- TODO разобрать формулу, не работает как надо, на половину ширины
    print('self.fieldWidthPixels', self.fieldWidthPixels, self.fieldHeightPixels)
    local dx = (w - (self.canvas as gr.Texture):getWidth()) / 2
    local dy = (h - (self.canvas as gr.Texture):getHeight()) / 2
    --local dx = (w - self.fieldWidthPixels) / 2
    --local dy = (h - self.fieldHeightPixels) / 2
    print("camera position", self.cam:position())
    print("lookAt", dx, dy)
    self.cam.scale = 1.
    self.cam:lookAt(dx, dy)
    print("camera position2", self.cam:position())

    --self.cam:lookAt(w / 2, h / 2)
    --self.cam:lookAt(200, 0)

    --self.cam:lookAt(-dx, -dy)
    --self.cam:move(dx, dy)
end

function SimulatorRender:bakeCanvas()
    gr.setColor{1, 1, 1, 1}
    gr.setCanvas(self.canvas)
    --gr.clear{1, 1, 1, 1}
    gr.clear{0, 0, 0, 1}
    self:drawGrid()
    self:drawCells()
    gr.setCanvas()
end

--local testing = require 'testing'

function SimulatorRender:draw()
    if not self.enabled then
        return
    end

    -- TODO запекать только есть есть события отрисовки клеток или поля
    -- с предыдущего кадра.
    self:bakeCanvas()
    --print("SimulatorRender:draw() self.canvas", self.canvas)

    gr.setColor{1, 1, 1, 1}
    --local sx, sy = 0.5, 0.5
    local sx, sy = 1, 1 

    print('self.camera.position', self.cam:position())
    -- 710, 290
    self.cam:attach()
    gr.draw(
        self.canvas as love.graphics.Drawable,
        0, 
        0, 
        0.0,
        sx,
        sy
    )
    self.cam:detach()

    --testing.writeCanvas2Disk(self.canvas, 'SimulatorRender.canvas-%d.png', 100)

    --[[
    -- XXX загружается каждый кадр
    local font = love.graphics.newFont("fonts/DroidSansMono.ttf", 32)
    gr.setFont(font)
    gr.setColor(1, 1, 1)
    gr.print('привет галактика!', 100, 100)
    --]]
end

function SimulatorRender:update(_: number)
end

function SimulatorRender:prerender()
    if not self.cellCanvas and not self.mealCanvas then
        error("No cellCanvas created!")
    end

    gr.setCanvas(self.mealCanvas)
    gr.clear(0, 0, 0, 1)
    gr.setColor(mealcolor)
    gr.rectangle("fill", 0, 0, pixSize, pixSize)
    gr.setCanvas()

    local tmpImage = gr.newImage("scenes/automato/cell.png") as gr.Texture
    local n = 2
    gr.setCanvas(self.cellCanvas)
    gr.clear(cellcolor1)
    gr.setColor(cellcolor2)
    gr.rectangle("fill", n, n, pixSize - 2 * n, pixSize - 2 * n)
    gr.draw(
        tmpImage as gr.Drawable, 0, 0, 0,
        (self.cellCanvas as gr.Texture):getWidth() / tmpImage:getWidth(),
        (self.cellCanvas as gr.Texture):getHeight() / tmpImage:getHeight()
    )
    gr.setCanvas()

    --gr.setCanvas(self.cellCanvas)
    --gr.setCanvas()
    self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas-1.png')

end

function SimulatorRender:presentList(list: {DrawNode})
    for _, node in ipairs(list) do
        local x, y = (node.x - 1) * pixSize, (node.y - 1) * pixSize
        if node.food then
            gr.setColor(1, 1, 1, 1)
            gr.draw(self.mealCanvas as love.graphics.Drawable, x, y)
        else
            if node.color then
                gr.setColor(node.color)
            else
                gr.setColor(1, 1, 1, 1)
            end
            gr.draw(self.cellCanvas as love.graphics.Drawable, x, y)
        end
    end
end

function SimulatorRender:drawCells()
    local drawlists: {{DrawNode}} = sim.getDrawLists()
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

    local schema: MtSchema
    local ok, errmsg: boolean, string = pcall(function()
        schema = mtschemes[self.commonSetup.threadCount]
    end)
    if not ok then
        print("Could'not require 'mtschemes'", errmsg)
    end

    if schema then
        for _, v in pairs(schema as {any: any}) do
            local dx, dy = (v as MtSchema).draw[1] * pixSize * gridSize, (v as MtSchema).draw[2] * pixSize * gridSize
            for i = 0, gridSize do
                local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
                local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
                self.fieldHeightPixels = y2 - y1
                x1, y1 = dx + 0, dy + i * pixSize
                x2, y2= dx + gridSize * pixSize, dy + i * pixSize
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

    local schema: MtSchema
    local ok, errmsg: boolean, string = pcall(function()
        schema = mtschemes[self.commonSetup.threadCount]
    end)
    if not ok then
        print("Could'not require 'mtschemes'", errmsg)
    end

    local prevwidth = {gr.getColor()}

    gr.setLineWidth(gridLineWidth)
    gr.setColor(gridColor)

    if schema then
        for _, v in pairs(schema as {any: any}) do
            local dx, dy = (v as MtSchema).draw[1] * pixSize * gridSize, (v as MtSchema).draw[2] * pixSize * gridSize
            for i = 0, gridSize do
                -- vert
                local x1, y1 = math.floor(dx + i * pixSize), math.floor(dy + 0)
                local x2, y2 = math.floor(dx + i * pixSize), math.floor(dy + gridSize * pixSize)
                self.fieldHeightPixels = y2 - y1
                gr.line(x1, y1, x2, y2)
                -- hor
                x1, y1 = dx + 0, dy + i * pixSize
                x2, y2= dx + gridSize * pixSize, dy + i * pixSize
                self.fieldWidthPixels = x2 - x1
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
    gr.setLineWidth(table.unpack(prevwidth))
end

function SimulatorRender:getPixSize(): number
    return pixSize
end

function SimulatorRender:drawCellPath(cell: Cell)
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

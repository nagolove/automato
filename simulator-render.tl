require "love"
love.filesystem.setRequirePath("?.lua;scenes/automato/?.lua")
package.path = package.path .. ";scenes/automato/?.lua"
require "imgui"
require "common"
require "types"

local gr = love.graphics
local inspect = require "inspect"
--local keyconfig = require "keyconfig"
local mtschemes = require "mtschemes"
--local prof = require "jprof"
local sim = require "simulator"
--local profi = require "profi"

global record SimulatorRender
    new: function(commonSetup: CommonSetup, Camera): SimulatorRender

    draw: function(SimulatorRender)
    drawGrid: function(SimulatorRender)
    drawCells: function(SimulatorRender)
    cameraToCenter: function(SimulatorRender)

    update: function(SimulatorRender, number)

    getPixSize: function(): number
    computeGrid: function

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
local pixSize: number = 10
-- ширина линий сетки
local gridLineWidth = 2
-- во сколько раз полотно больше размера картинки
local canvasmultfactor = 4

function SimulatorRender.new(commonSetup: CommonSetup, cam: Camera): SimulatorRender
    local self: SimulatorRender = {
        commonSetup = shallowCopy(commonSetup),
        cam = cam,
        fieldWidthPixels = 0,
        fieldHeightPixels = 0,
        canvas = nil,
        cellCanvas = gr.newCanvas(pixSize, pixSize),
        mealCanvas = gr.newCanvas(pixSize, pixSize),
    }
    self = setmetatable(self, SimulatorRender_mt)
    self:computeGrid()
    self:cameraToCenter()
    print("fieldWidthPixels, fieldHeightPixels", self.fieldWidthPixels, self.fieldHeightPixels)

    self.canvas = gr.newCanvas(
        self.fieldWidthPixels * canvasmultfactor, 
        self.fieldHeightPixels * canvasmultfactor
    )

    self.canvas:newImageData():encode('png', "simulator-render-canvas.png")
    self.cellCanvas:newImageData():encode('png', 'simulator-render-cell-canvas.png')
    self.mealCanvas:newImageData():encode('png', 'simulator-render-meal-canvas.png')

    self:draw()
    assert(self.canvas)
    return self
end

function SimulatorRender:cameraToCenter()
    local w, h = gr.getDimensions()
    -- TODO разобрать формулу, не работает как надо, на половину ширины
    local dx, dy = - (w - self.fieldWidthPixels) / 4, - (h - self.fieldHeightPixels) / 4
    print("camera position", self.cam:position())
    print("dx, dy", dx, dy)
    --self.cam:lookAt(0, 0)
    self.cam:move(dx, dy)
end

function SimulatorRender:draw()
    --if not self.canvas then
        self:drawGrid()
        self:drawCells()
    --else
    do
        --
        gr.setColor{1, 1, 1, 1}
        gr.setCanvas(self.canvas)
        --gr.clear{1, 1, 1, 1}
        gr.clear{0, 0, 0, 1}

        self:drawGrid()
        self:drawCells()

        gr.setCanvas()
        print("SimulatorRender:draw() self.canvas", self.canvas)

        self.cam:attach()
        gr.setColor{1, 1, 1, 1}
        --local sx, sy = 0.5, 0.5
        local sx, sy = 1, 1 

        --
        gr.draw(
            self.canvas as love.graphics.Drawable,
            0, 
            0, 
            0.0,
            sx,
            sy
        )
        --]]

        self.cam:detach()
        --]]

        --[[
        --gr.setCanvas(self.canvas)
        gr.setColor{1, 1, 1, 1}
        self.cam:attach()
        self:drawGrid()
        self:drawCells()
        self.cam:detach()
        --gr.setCanvas()
        --print("SimulatorRender:draw() self.canvas", self.canvas)
        ----if self.canvas then
        --gr.draw(self.canvas as love.graphics.Drawable, 0, 0)
        ----end
        --]]
    end
end

function SimulatorRender:update(_: number)
end

local mealcolor = {0, 1, 0, 1}
--local cellcolor = {0.5, 0.5, 0.5, 1}
local cellcolor = {1, 0, 0, 1}

function SimulatorRender:setupCanvases()
    if not self.cellCanvas and not self.mealCanvas then
        error("No cellCanvas created!")
    end

    gr.setCanvas(self.mealCanvas)
    gr.setColor(mealcolor)
    gr.clear(0, 0, 0, 1)
    gr.rectangle("fill", 0, 0, pixSize, pixSize)
    gr.setCanvas()

    gr.setCanvas(self.cellCanvas)
    gr.clear(0, 0, 0, 1)
    gr.setColor(cellcolor)
    gr.rectangle("fill", 0, 0, pixSize, pixSize)
    gr.setCanvas()
end

function SimulatorRender:drawCells()
    local drawlist: {DrawNode} = sim.getDrawLists()
    --print("SimulatorRender:drawCells")
    --print("drawlist", inspect(drawlist))
    if not drawlist then
        return
    end

    for _, node in ipairs(drawlist) do
        local x, y = (node.x - 1) * pixSize, (node.y - 1) * pixSize
        if node.food then
            gr.setColor(1, 1, 1, 1)
            gr.draw(self.mealCanvas as love.graphics.Drawable, x, y)
        else
            if node.color then
                gr.setColor(node.color)
            else
                gr.setColor(cellcolor)
            end
            gr.draw(self.cellCanvas as love.graphics.Drawable, x, y)
        end
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
    gr.setColor(0.5, 0.5, 0.5)
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

    local oldWidth = {gr.getColor()}
    gr.setLineWidth(gridLineWidth)
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
    gr.setLineWidth(table.unpack(oldWidth))
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
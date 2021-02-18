-- канва для рисования графиков
-- проверить на максильный размер при запуске на телефоне
--print("graphics size", gr.getWidth(), gr.getHeight())
--local graphCanvas = gr.newCanvas(gr.getWidth(), gr.getHeight())

-- цвета графиков
--local MAX_ENERGY_COLOR = {1, 0.5, 0.7, 1}
--local MID_ENERGY_COLOR = {0.8, 0.3, 0.7, 1}
--local MIN_ENERGY_COLOR = {0.6, 0.1, 1, 1}

-- ?? инфа с последним изменением статистики 
--local lastGraphicPoint

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


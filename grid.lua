local ffi = require("ffi")

pcall(ffi.cdef, [[
typedef struct Grid_Data
{
    /*
    state bits [0, 1, 2, 3, 4, 5, 6, 7, 8]
    0 - food
    1 - cell
    */
    uint8_t state;
} Grid_Data;
]])

local gridptr = ffi.typeof("Grid_Data*")

local Grid = {}
Grid.__index = Grid

function Grid.new(size)
    self.ptr = ffi.new("Grid_Data[?]", size * size)
    if not self.ptr then
        error("Not memory for self.ptr")
    end
end
function Grid:fillZero()
end
function Grid:isFood(i, j)
end
function Grid:setFood(i, j)
end

-- заполнить решетку пустыми значениями. В качестве значений используются
-- пустые таблицы {}
function Grid:getFalseGrid()
    --[[
       [local res = {}
       [for i = 1, gridSize do
       [    local t = {}
       [    for j = 1, gridSize do
       [        t[#t + 1] = {}
       [    end
       [    res[#res + 1] = t
       [end
       [return res
       ]]
end

function Grid:updateGrid()
    --[[
       [for _, v in pairs(cells) do
       [    grid[v.pos.x][v.pos.y] = v
       [end
       [for _, v in pairs(meal) do
       [    grid[v.pos.x][v.pos.y] = v
       [end
       ]]
end

function newGrid(size)
    return setmetatable({}, Grid)
end

return {
    new = Grid.new,
}


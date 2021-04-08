local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; require("types")
require("common")

local inspect = require("inspect")
local istate
local stat
local actions
local rng


local function getCodeValues()
   local codeValues = {}
   for k, _ in pairs(actions) do
      table.insert(codeValues, k)
   end
   return codeValues
end

local codeValues
printLog("codeValues", inspect(codeValues))


function genCode()
   local code = {}
   local len = #codeValues
   for _ = 1, istate.codeLen do
      table.insert(code, codeValues[math.floor(rng:random(1, len))])
   end
   return code
end

function Cell.new(t)
   local self = setmetatable({}, { __index = Cell })
   self.pos = {}
   t = t or {}
   if t.pos and t.pos.x then
      self.pos.x = t.pos.x
   else
      self.pos.x = math.floor(istate.rng:random(1, istate.gridSize))
   end
   if t.pos and t.pos.y then
      self.pos.y = t.pos.y
   else
      self.pos.y = math.floor(istate.rng:random(1, istate.gridSize))
   end
   if t.wantdivide then
      self.wantdivide = t.wantdivide
   end
   if t.code then
      self.code = shallowCopy(t.code)
   else
      self.code = genCode()

   end
   if t.generation then
      self.generation = self.generation + 1
   else
      self.generation = 1
   end
   if t.energy then
      self.energy = t.energy
   end
   self.ip = 1
   self.id = istate.cellId
   istate.cellId = istate.cellId + 1





   self:print()
   self.energy = istate.rng:random(istate.initialEnergy[1], istate.initialEnergy[2])

   return self
end

function Cell:print()

end


function Cell:update()
   local isalive = true


   if self.ip >= #self.code then
      self.ip = 1
   end

   if self.energy > 0 then
      local code = self.code[self.ip]


      isalive = actions[code](self)
      self.ip = self.ip + 1
      self.energy = self.energy - istate.denergy


      if self.wantdivide and self.wantdivide - 1 >= 0 then
         self.wantdivide = self.wantdivide - 1
      end
   else
      isalive = false

      stat.died = stat.died + 1
   end

   return isalive
end

function cellInitInternal(state, s)
   istate = shallowCopy(state)
   actions = state.cellActions
   rng = state.rng
   stat = s
   codeValues = getCodeValues()
end

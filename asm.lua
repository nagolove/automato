require("types")

local inspect = require("inspect")

local OpCodes = {}



















































local Assembler = {Expression = {}, }















local ByteCode = {}



function Assembler.new()
   local self = {}
   self = setmetatable(self, { __index = Assembler })
end

local VirtualMachine = {}










local asm = Assembler.new()
local bcode = asm:build()
local vm = VirtualMachine.new(bcode)

local err = vm:run()

print(err)

local cell = {
   energy = 6864,
   id = 29,
   ip = 2,
   moves = { 47, 50 },
   pos = {
      x = 46,
      y = 50,
   },
}

print(inspect(cell))

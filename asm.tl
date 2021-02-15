require "types"
require "common"

local inspect = require "inspect"

local type OpCodes = enum
    "up"
    "down"
    "left"
    "right"

    "cross"

    'push'
    'pop'

    "eat8move"
    'eat8'

    'cmp'
    'jmp'
    'sub'
    'add'
    'mul'
    'div'
    'je'
    'jne'
    'jlt'
    'const'
end

local record Operand
    enum Source
        'operand'
        'memory'
    end
    source: Source
    value: any
    address: number
end

local record Expression
    opcode: OpCodes
    operand: Operand
end

local type Assembler = record
    build: function(Assembler, code: {string}): {Expression}
    new: function(): Assembler
end

function Assembler.new()
    local self: Assembler = {}
    self = setmetatable(self, { __index = Assembler })
end

local type VirtualMachine = record

    enum ErrorCode
        'ok'
        'fail'
    end

    new: function(bytecode: {Expression}): VirtualMachine
    run: function(VirtualMachine): ErrorCode, any...

    code: {Expression}
end

function VirtualMachine.new(bytecode: {Expression}): VirtualMachine
    local self: VirtualMachine = {
        code = shallowCopy(bytecode),
    }
    self = setmetatable(self, { __index = VirtualMachine })
end

function VirtualMachine:run(): VirtualMachine.ErrorCode, any...
    local ip = 1
    while true do
        local exp = self.code[ip]
    end
end

local asm: Assembler = Assembler.new()
local bcode: {Expression} = asm:build()
local vm: VirtualMachine = VirtualMachine.new(bcode)

local err: VirtualMachine.ErrorCode = vm:run()

print(err)

local cell: Cell = {
    energy = 6864,
    id = 29,
    ip = 2,
    moves = { 47, 50 },
    pos = {
        x = 46,
        y = 50
    }
}

print(inspect(cell))

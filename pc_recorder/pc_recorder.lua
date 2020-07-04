-- Author: thonic
-- Mail: thonic@foxmail.com
-- Description: a tool to record ProgramCounter and other infos at FCEUX.
local Q_SIZE = 200

local function repr_node(node)
    local res = string.format("PC=%X,A=%X,X=%X,Y=%X,P=", node.pc, node.a, node.x, node.y)
    local p = node.p
    if AND(p, BIT(7)) ~= 0 then res = res .. 'N' else res = res .. '-' end
    if AND(p, BIT(6)) ~= 0 then res = res .. 'V' else res = res .. '-' end
    if AND(p, BIT(5)) ~= 0 then res = res .. 'U' else res = res .. '-' end
    if AND(p, BIT(4)) ~= 0 then res = res .. 'B' else res = res .. '-' end
    if AND(p, BIT(3)) ~= 0 then res = res .. 'D' else res = res .. '-' end
    if AND(p, BIT(2)) ~= 0 then res = res .. 'I' else res = res .. '-' end
    if AND(p, BIT(1)) ~= 0 then res = res .. 'Z' else res = res .. '-' end
    if AND(p, BIT(0)) ~= 0 then res = res .. 'C' else res = res .. '-' end
    return res
end

local function make_q(q_size)
    local q = {}
    local next = 1

    for i=1,q_size do
        q[i] = {}
    end

    function q:append(pc, a, x, y, p)
        local next_node = self[next]
        next_node.pc = pc
        next_node.a = a
        next_node.x = x
        next_node.y = y
        next_node.p = p
        next = next + 1
        if next > q_size then
            next = 1
        end
    end

    function q:print()
        emu.print("------------")
        for i=next,q_size do
            emu.print(repr_node(self[i]))
        end
        for i=1,next-1 do
            emu.print(repr_node(self[i]))
        end
    end

    return q
end

--------------------------------

g_last_pc = 0

local pc_q = make_q(Q_SIZE)

local function addr_exec_cb()
    local pc = memory.getregister("pc")
    if pc ~= g_last_pc then
        g_last_pc = pc
        local a = memory.getregister("a")
        local x = memory.getregister("x")
        local y = memory.getregister("y")
        local p = memory.getregister("p")
        pc_q:append(pc, a, x, y, p)
    end
end

-- memory.registerexec(int address, [int size,] function func)
memory.registerexec(0x8000, 0x10000 - 0x8000, addr_exec_cb)

-- OUTPUT trigger
memory.registerwrite(0x0464, 
    function()
        pc_q:print()
        emu.pause()
    end
)


---------------------------------

while (true) do
	emu.frameadvance()
end
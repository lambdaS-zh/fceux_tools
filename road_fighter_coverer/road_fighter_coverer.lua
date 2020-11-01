-- Author: thonic
-- Mail: thonic@foxmail.com

-- Emulator: FCEUX
-- ROM Name: Road Fighter (J).nes
-- ROM SHA1: 4A94A717F4171B566273FE269A5EE504EB68E28E

local COVERER_Y = 150

local ADDR_CHECKPOINT = 0X00E8  -- =1: racing, =2: met checkpoint

local ADDR_HERO_CD = 0x00CD  -- =1 means no collision detection
local ADDR_HERO_X = 0x0065
local ADDR_HERO_SPEED_LO8 = 0x0068

local ADDR_COVERER_X = 0x0345
local ADDR_COVERER_Y = 0x0346
local ADDR_COVERER_STATE = 0x034F

local NPC_STATE = {
    NONE =          0,  -- for reading
    SUPER_MAN =     0,  -- for writing
    ICON =          1,
    HERO =          2,
    FOOL_BLUE =     3,
    YELLOW =        4,
    FUCK_BLUE =     5,
    FUCK_RED =      6,
    BLUE =          7,
    FUEL =          8,
    PIT =           9,
    TRUCK =         11,
    BARRIER =       12,
    BLAST =         24,
}
local TARGET = NPC_STATE.BARRIER

local function hero_silent()
    return memory.readbyteunsigned(ADDR_HERO_SPEED_LO8) == 0 or 
        memory.readbyteunsigned(ADDR_CHECKPOINT) == 2
end

local function on_move_hero_x(addr)
    if hero_silent() then return end

    local x = memory.readbyteunsigned(addr)
    memory.writebyte(ADDR_COVERER_X, x)
end

local function on_reset_coverer(addr)
    --if hero_silent() then return end

    local state = memory.readbyteunsigned(addr)
    if state == NPC_STATE.BLAST or state == TARGET then
        return
    end
    memory.writebyte(addr, TARGET)
end

local function on_move_coverer_y(addr)
    if hero_silent() then return end

    local y = memory.readbyteunsigned(addr)
    if y == COVERER_Y then
        return
    end
    memory.writebyte(addr, COVERER_Y)
end

memory.registerwrite(ADDR_HERO_X, on_move_hero_x)
memory.registerwrite(ADDR_COVERER_STATE, on_reset_coverer)
memory.registerwrite(ADDR_COVERER_Y, on_move_coverer_y)

while true do
    emu.frameadvance()
end
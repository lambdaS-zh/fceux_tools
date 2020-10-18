-- Author: thonic
-- Mail: thonic@foxmail.com

-- Emulator: FCEUX
-- ROM Name: Dr. Mario (JU).nes
-- ROM SHA1: 01DE1E04C396298358E86468BA96148066688194


---- constants ----
local FIELD_W = 8
local FIELD_H = 16

-- field values in the RAM
local RAM_FV_NO = 0xFF  -- none
local RAM_FV_YB = 0x60  -- yellow brick
local RAM_FV_RB = 0x61  -- red brick
local RAM_FV_BB = 0x62  -- blue brick
local RAM_FV_YV = 0xD0  -- yellow virus
local RAM_FV_RV = 0xD1  -- red virus
local RAM_FV_BV = 0xD2  -- blue virus

-- rotate order of capsule: (0|1)
local RO_ODR_H_01 = 0  -- L 0, R 1
local RO_ODR_V_01 = 3  -- U 0, D 1
local RO_ODR_H_10 = 2  -- L 1, R 0
local RO_ODR_V_10 = 1  -- U 1, D 0


---- helper ----
-- x means v(virus) or b(brick)

local function is_v(a)
    -- a is virus
    if a == nil or a == RAM_FV_NO then return false end
    return AND(a, 0xD0) == 0xD0
end

local function b_to_v(a)
    -- brick to virus
    if a == nil or a == RAM_FV_NO then
        return a
    end
    return 0xD0 + AND(a, 0x0F)
end

local function eq_v_x(a, b)
    if a == nil or b == nil then return false end
    -- requires at least 1 virus
    if not is_v(a) and not is_v(b) then
        -- no virus in a,b
        return false
    end
    return AND(a, 0x0F) == AND(b, 0x0F)
end

local function eq_x_x(a, b)
    if a == nil or b == nil then return false end
    return AND(a, 0x0F) == AND(b, 0x0F)
end

local function is_no(a)
    return a == RAM_FV_NO
end


---- system context ----
local function sys_ctx_new(
    level_addr,
    playing_addr
)
    local sys = {
        level_addr=level_addr,
        playing_addr=playing_addr,
    }

    function sys:level()
        return memory.readbyteunsigned(self.level_addr)
    end

    function sys:level_viruses()
        return (self:level() + 1) * 4
    end

    function sys:playing()
        return memory.readbyteunsigned(self.playing_addr) == 1
    end

    return sys
end


---- turbo button simulator ----
local function turbo_pad_new(player)
    local frames_delay = 5
    local pad = {
        player=player,

        count=frames_delay,
    }

    function pad:press_left()
        self.count = self.count - 1
        if self.count <= 0 then
            self.count = frames_delay
            joypad.set(self.player, {left=true})
        end
    end

    function pad:press_right()
        self.count = self.count - 1
        if self.count <= 0 then
            self.count = frames_delay
            joypad.set(self.player, {right=true})
        end
    end

    function pad:press_a()
        self.count = self.count - 1
        if self.count <= 0 then
            self.count = frames_delay
            joypad.set(self.player, {A=true})
        end
    end

    return pad
end


---- player context ----
local function player_ctx_new(
    sys_ctx,
    player,
    field_start_addr,
    cur_l_cap_colo_addr,
    cur_r_cap_colo_addr,
    cur_cap_y_addr,
    cur_cap_x_addr,
    cur_cap_rotate_addr,
    rest_virus_y_addr,
    rest_virus_r_addr,
    rest_virus_b_addr,
    game_over_addr
)
    local pl = {
        sys_ctx=sys_ctx,
        player=player,
        field_start_addr=field_start_addr,
        cur_l_cap_colo_addr=cur_l_cap_colo_addr,
        cur_r_cap_colo_addr=cur_r_cap_colo_addr,
        cur_cap_y_addr=cur_cap_y_addr,
        cur_cap_x_addr=cur_cap_x_addr,
        cur_cap_rotate_addr=cur_cap_rotate_addr,
        rest_virus_y_addr=rest_virus_y_addr,
        rest_virus_r_addr=rest_virus_r_addr,
        rest_virus_b_addr=rest_virus_b_addr,
        game_over_addr=game_over_addr,

        capsule_impulse=false,
        going_x=-1,
        rotating_order=-1,
        last_y=0,
        _playing=true, -- in case that script starts when capsule playing
        turbo_pad=turbo_pad_new(player),
    }

    function pl:current_capsule_state()
        local c0 = memory.readbyteunsigned(self.cur_l_cap_colo_addr)
        local c1 = memory.readbyteunsigned(self.cur_r_cap_colo_addr)
        local colo_map = {
            [0] = RAM_FV_YB,
            [1] = RAM_FV_RB,
            [2] = RAM_FV_BB,
        }
        c0 = colo_map[c0]
        c1 = colo_map[c1]
        return {
            [0] = c0,
            [1] = c1,
        }
    end

    function pl:get_field()
        local res = {}
        local cur = self.field_start_addr

        for i=1, FIELD_H do
            local line = {}
            for j=1, FIELD_W do
                line[j] = memory.readbyteunsigned(cur)
                cur = cur + 1
            end
            res[i] = line
        end

        return res
    end

    function pl:get_field_column_tops()
        local tops_real, tops_cast = {}, {}

        for j=1, FIELD_W do
            local col_cur = self.field_start_addr + j - 1  -- for mem addr
            local top = RAM_FV_NO

            for i=1, FIELD_H do
                local ram_v = memory.readbyteunsigned(col_cur)
                if ram_v ~= RAM_FV_NO then
                    top = ram_v
                    break
                end
                col_cur = col_cur + FIELD_W
            end

            tops_real[j], tops_cast[j] = top, top
        end

        -- try to cast virus value to the top to give the
        -- column higher priority matching capsule.
        for j=1, FIELD_W do
            local col_cur = self.field_start_addr + j - 1  -- for mem addr
            local top = RAM_FV_NO

            for i=1, FIELD_H do
                local ram_v = memory.readbyteunsigned(col_cur)
                if ram_v ~= RAM_FV_NO and is_v(ram_v) then
                    tops_cast[j] = b_to_v(tops_cast[j])
                    break
                end
                col_cur = col_cur + FIELD_W
            end
        end

        return tops_real, tops_cast
    end

    function pl:got_capsule_impulse()
        local res = self.capsule_impulse
        self.capsule_impulse = false
        return res
    end

    function pl:rotate_set(order)
        -- for testing only
        memory.writebyte(self.cur_cap_rotate_addr, order)
    end

    function pl:rotate_to(order)
        self.rotating_order = order
    end

    function pl:set_x(x)
        -- for testing only
        memory.writebyte(self.cur_cap_x_addr, x)
    end

    function pl:cap_goto_x(x)
        self.going_x = x
    end

    function pl:drive_capsule(rotate_order, x)
        -- test code
        --self:set_x(x)
        --self:rotate_set(rotate_order)
        --return
        -- real code
        self:cap_goto_x(x)
        self:rotate_to(rotate_order)
    end

    function pl:y()
        return memory.readbyteunsigned(self.cur_cap_y_addr)
    end

    function pl:x()
        return memory.readbyteunsigned(self.cur_cap_x_addr)
    end

    function pl:rot_pos()
        -- current rotate-order
        return memory.readbyteunsigned(self.cur_cap_rotate_addr)
    end

    function pl:rc_y()
        -- rest count of yellow viruses
        return memory.readbyteunsigned(self.rest_virus_y_addr)
    end

    function pl:rc_r()
        -- rest count of red viruses
        return memory.readbyteunsigned(self.rest_virus_r_addr)
    end

    function pl:rc_b()
        -- rest count of blue viruses
        return memory.readbyteunsigned(self.rest_virus_b_addr)
    end

    function pl:rest_viruses()
        return self:rc_y() + self:rc_r() + self:rc_b()
    end

    function pl:game_over()
        return memory.readbyteunsigned(self.game_over_addr) ~= 0
    end

    function pl:on_each_frame()
        if not self.sys_ctx:playing() then
            self._playing = false
            self.last_y = 0
            return
        end
        if self:game_over() then
            self._playing = false
            self.last_y = 0
            return
        end

        local viruses = self:rest_viruses()
        if viruses == self.sys_ctx:level_viruses() then
            -- a new level round starts
            self._playing = true
        end
        if viruses == 0 then
            -- viruses clear, round's over
            self._playing = false
            self.last_y = 0
        end

        if not self._playing then
            return
        end

        -- upper capsule, bigger y
        local cur_y = self:y()
        if cur_y == 15 then
            -- sometimes it can't get the real capsule while
            -- y is 15, and I can't find a way to fix this
            -- problem, so here ignore y==15.
            cur_y = self.last_y
        end
        if self.last_y < cur_y then
            -- make an impulse
            self.capsule_impulse = true
        end
        self.last_y = cur_y

        -- capsule's moving task consumer

        if self.rotating_order > -1 then
            local cur_odr = self:rot_pos()
            if self.rotating_order == cur_odr then
                self.rotating_order = -1
            else
                --joypad.set(self.player, {A='invert'})
                self.turbo_pad:press_a()
            end
            return
        end

        -- move horizontally after rotating
        if self.going_x > -1 then
            local cur_x = self:x()
            if self.going_x > cur_x then
                --joypad.set(self.player, {right=true})
                self.turbo_pad:press_right()
            elseif self.going_x < cur_x then
                --joypad.set(self.player, {left=true})
                self.turbo_pad:press_left()
            else
                self.going_x = -1
            end
            return
        end

        -- fall after moving horizontally
        joypad.set(self.player, {down=true})
    end

    return pl
end


---- AI strategy ----
local function ai_new(sys_ctx, player_ctx)
    local ai = {
        sys_ctx=sys_ctx,
        player_ctx=player_ctx,

        searching=false,
    }

    function ai:start_search()
        self.searching = true
    end

    -- strategy functions for matching, some principles:
    --- * empty columns($TOP==RAM_FV_NO) match any colors.
    --- * make best effort to avoid putting unmatched colors onto
    ---- viruses in those '1x' functions(e.g.. h_1v0b)

    function ai:match_h_2v(cur_cap, tops)
        -- horizontally match 2 viruses
        local v0, v1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            if eq_v_x(v0, fv) and eq_v_x(v1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            if eq_v_x(v1, fv) and eq_v_x(v0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_v_1v_both(cur_cap, tops)
        -- vertically match 1 virus with both sides of the capsule.
        if cur_cap[0] ~= cur_cap[1] then
            return false, 0, 0
        end
        val = cur_cap[0]

        for idx, fv in ipairs(tops) do
            if eq_v_x(val, fv) then
                return true, RO_ODR_V_01, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_h_1v1b(cur_cap, tops)
        -- horizontally match 1 virus 1 brick
        local v0, v1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            if eq_v_x(v0, fv) and eq_x_x(v1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            if eq_x_x(v0, fv) and eq_v_x(v1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end

            if eq_v_x(v1, fv) and eq_x_x(v0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
            if eq_x_x(v1, fv) and eq_v_x(v0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_h_1v1n(cur_cap, tops)
        -- horizontally match 1 virus 1 empty column
        local v0, v1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            -- |ry|
            -- |R |
            -- +--+
            if eq_v_x(v0, fv) and is_no(tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            -- |ry|
            -- | Y|
            -- +--+
            if is_no(fv) and eq_v_x(v1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end

            -- ry -rotate-> yr
            -- |yr|
            -- |Y |
            -- +--+
            if eq_v_x(v1, fv) and is_no(tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
            -- ry -rotate-> yr
            -- |yr|
            -- | R|
            -- +--+
            if is_no(fv) and eq_v_x(v0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_h_1v0b(cur_cap, tops)
        -- horizontally match 1 virus 0 brick
        -- this shall be conflicted with v_1v
        local c0, c1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            if eq_v_x(c0, fv) or eq_v_x(c1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            if eq_v_x(c1, fv) or eq_v_x(c0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_v_1v(cur_cap, tops)
        -- vertically match 1 virus with a side of the capsule
        -- NOT USED
        return false, 0, 0
    end

    function ai:match_h_2b(cur_cap, tops)
        -- horizontally match 2 bricks
        local c0, c1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            if eq_x_x(c0, fv) and eq_x_x(c1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            if eq_x_x(c1, fv) and eq_x_x(c0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_v_1b_both(cur_cap, tops)
        -- vertically match 1 brick with both sides of the capsule.
        if cur_cap[0] ~= cur_cap[1] then
            return false, 0, 0
        end
        val = cur_cap[0]

        for idx, fv in ipairs(tops) do
            if eq_x_x(val, fv) then
                return true, RO_ODR_V_01, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_h_1b1n(cur_cap, tops)
        -- horizontally match 1 brick 1 empty column
        local v0, v1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            -- |ry|
            -- |r |
            -- +--+
            if eq_x_x(v0, fv) and is_no(tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            -- |ry|
            -- | y|
            -- +--+
            if is_no(fv) and eq_x_x(v1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end

            -- ry -rotate-> yr
            -- |yr|
            -- |y |
            -- +--+
            if eq_x_x(v1, fv) and is_no(tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
            -- ry -rotate-> yr
            -- |yr|
            -- | r|
            -- +--+
            if is_no(fv) and eq_x_x(v0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_h_2n(cur_cap, tops)
        -- horizontally find 2 empty columns
        for idx, fv in ipairs(tops) do
            if is_no(fv) and is_no(tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
        end
        return false, 0, 0
    end

    function ai:match_v_1n(cur_cap, tops)
        -- vertically find an empty column
        for idx, fv in ipairs(tops) do
            if is_no(fv) then
                return true, RO_ODR_V_01, idx - 1 -- fuck Lua
            end
        end
        return false, 0, 0
    end

    function ai:match_h_1b(cur_cap, tops)
        -- horizontally match only 1 brick
        local c0, c1 = cur_cap[0], cur_cap[1]

        for idx, fv in ipairs(tops) do
            if eq_x_x(c0, fv) or eq_x_x(c1, tops[idx+1]) then
                return true, RO_ODR_H_01, idx - 1 -- fuck Lua
            end
            if eq_x_x(c1, fv) or eq_x_x(c0, tops[idx+1]) then
                return true, RO_ODR_H_10, idx - 1 -- fuck Lua
            end
        end

        return false, 0, 0
    end

    function ai:match_v_1b(cur_cap, tops)
        -- vertically match 1 brick with a side of the capsule
        -- NOT USED
        return false, 0, 0
    end

    local real, cast = 0, 1 -- determines which top data to use
    local strategies = {
        {ai.match_h_2v,         real},
        {ai.match_v_1v_both,    real},
        {ai.match_h_1v1b,       real},
        {ai.match_h_1v1n,       real},

        {ai.match_h_2v,         cast},
        {ai.match_v_1v_both,    cast},
        {ai.match_h_1v1b,       cast},
        {ai.match_h_1v1n,       cast},

        {ai.match_h_2b,         real},
        {ai.match_v_1b_both,    real},
        {ai.match_h_1b1n,       real},
        {ai.match_h_2n,         real},
        {ai.match_v_1n,         real},
        {ai.match_h_1v0b,       real},
        {ai.match_h_1v0b,       cast},
        {ai.match_h_1b,         real},
    }
    local strategies_sprint = {
        {ai.match_h_2v,         cast},
        {ai.match_v_1v_both,    cast},
        {ai.match_h_1v1b,       cast},
        {ai.match_h_1v1n,       cast},
        {ai.match_h_1v0b,       cast},

        {ai.match_h_2b,         real},
        {ai.match_v_1b_both,    real},
        {ai.match_h_1b1n,       real},
        {ai.match_h_2n,         real},
        {ai.match_v_1n,         real},
        {ai.match_h_1b,         real},
    }

    function ai:on_once_search()
        local cur_cap = self.player_ctx:current_capsule_state()
        local tops_real, tops_cast = self.player_ctx:get_field_column_tops()
        local viruses = self.player_ctx:rest_viruses()

        local func, func_type = nil, nil
        local found, rotate_order, x = false, 0, 0

        local stg = nil
        if viruses > 1 then
            stg = strategies
        else
            stg = strategies_sprint
        end

        for idx, functor in ipairs(strategies) do
            func, func_type = functor[1], functor[2]
            if func_type == real then
                found, rotate_order, x = func(self, cur_cap, tops_real)
            else
                found, rotate_order, x = func(self, cur_cap, tops_cast)
            end

            if found then
                --emu.print('tops_real: ', tops_real)
                --emu.print('tops_cast: ', tops_cast)
                emu.print(
                    string.format('%X %X - ', cur_cap[0], cur_cap[1]),
                    idx, found, rotate_order, x
                )
                self.player_ctx:drive_capsule(rotate_order, x)
                return
            end
        end

        emu.print('not found')
        if AND(viruses, 0x1) ~= 0 then
            self.player_ctx:drive_capsule(RO_ODR_V_01, 0)
        else
            self.player_ctx:drive_capsule(RO_ODR_V_10, FIELD_W - 1)
        end
    end

    function ai:on_each_frame()
        if self.player_ctx:got_capsule_impulse() then
            self:start_search()
        end
        if self.searching then
            self:on_once_search()
            self.searching = false
        end
    end

    return ai
end


---------------------------------
local sys = sys_ctx_new(
    0x0316,  -- level_addr
    0x005D   -- playing_addr
)
local p1 = player_ctx_new(
    sys,     -- sys_ctx
    1,       -- player(id)
    0x0400,  -- field_start_addr
    0x0301,  -- cur_l_cap_colo_addr
    0x0302,  -- cur_r_cap_colo_addr
    0x0306,  -- cur_cap_y_addr
    0x0305,  -- cur_cap_x_addr
    0x0325,  -- cur_cap_rotate_addr
    0x0072,  -- rest_virus_y_addr
    0x0073,  -- rest_virus_r_addr
    0x0074,  -- rest_virus_b_addr
    0x0309   -- game_over_addr
)
local p1_ai = ai_new(sys, p1)

while (true) do
    p1:on_each_frame()
    p1_ai:on_each_frame()

	emu.frameadvance()
end

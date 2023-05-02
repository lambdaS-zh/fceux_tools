-- Author: thonic
-- Mail: thonic@foxmail.com
-- Description: show crosshair to help aiming at the bees before firing.

-- bullet top y: $0280, moves upward 4 pixels each frame
-- bees move by 1 pixel horizontally each frame
-- bees horizontal distance = 15-17pixels, b: vertical distance = 12pixels
-- a: distance from idle-bullet-top to bottom-bees-center = 96pixels
-- bottom bees center y = 108
-- player center x = $00E4 + 128
-- $079F: move left=128, move right=0
-- crosshair_x = vb/vr * (a+Nb)
-- vb/vr = 1/20, a = 96, b = 12

-- each crosshair xy:
-- (96+5*12)/20=8.05
local ch5 = {8, 48}
-- (96+4*12)/20=7.4
local ch4 = {7, 60}
-- (96+3*12)/20=6.75
local ch3 = {7, 72}
-- (96+2*12)/20=6.1
local ch2 = {6, 84}
-- (96+1*12)/20=5.45
local ch1 = {5, 96}
-- (96+0*12)/20=4.8
local ch0 = {5, 108}


local function draw_dot(x, y, invert)
    if x < 0 or x > 255 then return end
    if y < 8 or y > 231 then return end
 
    if not invert then
        gui.setpixel(x, y, {128, 128, 128, 255})
        return
    end

    local r, g, b, pal = emu.getscreenpixel(x, y, true)
    gui.setpixel(x, y, {255-r, 255-g, 255-b, 255})
end

local function draw_cross(x, y, invert)
    draw_dot(x, y, invert)

    draw_dot(x - 1, y, invert)
    draw_dot(x - 2, y, invert)
    draw_dot(x - 3, y, invert)
    --draw_dot(x - 4, y, invert)
    --draw_dot(x - 5, y, invert)
    draw_dot(x + 1, y, invert)
    draw_dot(x + 2, y, invert)
    draw_dot(x + 3, y, invert)
    --draw_dot(x + 4, y, invert)
    --draw_dot(x + 5, y, invert)
    
    draw_dot(x, y - 1, invert)
    draw_dot(x, y - 2, invert)
    draw_dot(x, y - 3, invert)
    draw_dot(x, y + 1, invert)
    draw_dot(x, y + 2, invert)
    draw_dot(x, y + 3, invert)
end

local getu = memory.readbyteunsigned

local function main()
    local px = (getu(0x00E4) + 128) % 255
    local move_right = (getu(0x079F) == 0)

    if move_right then
        draw_cross(px-ch0[1], ch0[2], true)
        draw_cross(px-ch1[1], ch1[2], true)
        draw_cross(px-ch2[1], ch2[2], true)
        draw_cross(px-ch3[1], ch3[2], true)
        draw_cross(px-ch4[1], ch4[2], true)
        draw_cross(px-ch5[1], ch5[2], true)
        draw_cross(px+ch0[1], ch0[2], false)
        draw_cross(px+ch1[1], ch1[2], false)
        draw_cross(px+ch2[1], ch2[2], false)
        draw_cross(px+ch3[1], ch3[2], false)
        draw_cross(px+ch4[1], ch4[2], false)
        draw_cross(px+ch5[1], ch5[2], false)
    else
        draw_cross(px-ch0[1], ch0[2], false)
        draw_cross(px-ch1[1], ch1[2], false)
        draw_cross(px-ch2[1], ch2[2], false)
        draw_cross(px-ch3[1], ch3[2], false)
        draw_cross(px-ch4[1], ch4[2], false)
        draw_cross(px-ch5[1], ch5[2], false)
        draw_cross(px+ch0[1], ch0[2], true)
        draw_cross(px+ch1[1], ch1[2], true)
        draw_cross(px+ch2[1], ch2[2], true)
        draw_cross(px+ch3[1], ch3[2], true)
        draw_cross(px+ch4[1], ch4[2], true)
        draw_cross(px+ch5[1], ch5[2], true)
    end
end

while (true) do
    main()
	emu.frameadvance()
end

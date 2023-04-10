-- Sleeve badge and captain armband server for PES 2021
-- by Hawke and juce
-- originally released on EvoWeb.uk in April 2023

local m = { version = "v1.1" }

local map
local map_count
local content_root
local patterns
local armband_patch_addr
local badge_patch_addr
local badge_patch_addr2
local badge0_left_ftex
local messages = {}
local frame_count = 0

local reload_button = {
    vkey = 0x30, label = "[0]"
}

local empty = {}
local function get_common_lib(ctx)
    return ctx.common_lib or empty
end

local function len(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function get_tid(ctx)
    local tid = ctx.tournament_id
    if tid == 65535 then
        -- exhibition mode. Maybe teams are from the same league
        if get_common_lib(ctx).tid_same_league then
            tid = get_common_lib(ctx).tid_same_league(ctx.home_team, ctx.away_team) or tid
        end
    end
    return tid
end

function m.get_filepath(ctx, filename)
    for p,f in pairs(patterns) do
        local str = string.match(filename, p)
        if str then
            local tid = get_tid(ctx)
            local folder = map[tid]
            if not folder then
                -- nothing mapped for this tournament id
                return 
            end
            local path = f(ctx, folder, str)
            log(filename .. " => " .. tostring(path))
            return path
        end
    end
end

local function set_uefa_armband()
    log("applying armband patch at " .. memory.hex(armband_patch_addr))
    memory.write(armband_patch_addr, "\x90\x90\x90\xeb")
end

local function unset_uefa_armband()
    log("removing armband patch at " .. memory.hex(armband_patch_addr))
    memory.write(armband_patch_addr, "\x83\xfb\x21\x74")
end

local function set_badge()
    log("applying badge patch at " .. memory.hex(badge_patch_addr))
    memory.write(badge_patch_addr, "\x90\x90\x90\x90\x90")
end

local function unset_badge()
    log("removing badge patch at " .. memory.hex(badge_patch_addr))
    memory.write(badge_patch_addr, "\x66\x85\xff\x74\x52")
end

local function set_badge_left()
    --[[
    0000000141EAD060 | 83E7 01                         | and edi,1                               |
    0000000141EAD063 | 66:83C7 62                      | add di,62                               |
    0000000141EAD067 | 90                              | nop                                     |
    0000000141EAD068 | 90                              | nop                                     |
    0000000141EAD069 | 90                              | nop                                     |
    --]]
    log("applying badge-left patch at " .. memory.hex(badge_patch_addr2))
    memory.write(badge_patch_addr2, "\x83\xe7\x01\x66\x83\xc7\x62\x90\x90\x90")
end

local function unset_badge_left()
    --[[
    0000000141EAD060 | 0FB77C24 7C                     | movzx edi,word ptr ss:[rsp+7C]          |
    0000000141EAD065 | 66:85FF                         | test di,di                              |
    0000000141EAD068 | 74 53                           | je pes2021.141EAD0BD                    |
    --]]
    log("removing badge-left patch at " .. memory.hex(badge_patch_addr2))
    memory.write(badge_patch_addr2, "\x0f\xb7\x7c\x24\x7c\x66\x85\xff\x74\x53")
    badge0_left_ftex = nil
end

local function get_armband(ctx, folder, basename)
    return content_root .. "\\" .. folder .. "\\cap\\" .. basename
end

local function get_badge(ctx, folder, badge_id)
    badge_id = tonumber(badge_id)
    if badge_id == 0 then
        return content_root .. "\\" .. folder .. "\\badge\\badge0.ftex"
    elseif badge_id == 98 then
        if badge0_left_ftex then
            return content_root .. "\\" .. folder .. "\\badge\\badge0-left.ftex"
        end
        return content_root .. "\\" .. folder .. "\\badge\\badge2-left.ftex"
    elseif badge_id == 99 then
        return content_root .. "\\" .. folder .. "\\badge\\badge1-left.ftex"
    end
    -- one of the two badges is typically a champions badge
    if badge_id and badge_id % 2 == 0 then
        -- 2nd badge
        return content_root .. "\\" .. folder .. "\\badge\\badge2.ftex"
    elseif badge_id then
        -- 1st badge
        return content_root .. "\\" .. folder .. "\\badge\\badge1.ftex" 
    end
end

local function get_respect_badge(ctx, folder)
    return content_root .. "\\" .. folder .. "\\badge\\respect_badge.ftex"
end

local function load_map(filename)
    local map = {}
    local delim = ","
    local f = io.open(filename)
    if not f then
        error("unable to open " .. filename .. " for reading")
    end
    f:close()
    for line in io.lines(filename) do
        -- trim comments and whitespace
        line = line:gsub("#.*$", "")
        local tournament_id, folder = string.match(line, "%s*(.+)%s*,%s*[\"]([^\"]+)[\"]")
        tournament_id = tonumber(tournament_id)
        if tournament_id and folder then
            map[tournament_id] = folder
            log(string.format("map: tournament %d => %s", tournament_id, folder))
        end
    end
    log("total entries in map: " .. len(map)) 
    return map
end

function m.overlay_on(ctx)
    frame_count = (frame_count + 1) % 120
    if frame_count == 0 then
        messages = {}  -- clear the messages after 2 seconds
    end
    return string.format("%s | map size: %d | Press %s - to reload map\n\n%s",
        m.version, len(map), reload_button.label, table.concat(messages, "\n"))
end

function m.key_down(ctx, vkey)
    if vkey == reload_button.vkey then
        map = load_map(content_root .. "map.txt")
        messages[#messages + 1] = "map reloaded"
        frame_count = 0
    end
end

function m.set_teams(ctx)
    -- start with both patches removed
    unset_uefa_armband()
    unset_badge()
    unset_badge_left()
    local tid = get_tid(ctx)
    local folder = map[tid]
    if not folder then
        -- nothing mapped for this tournament id
        -- unpatch the exe to disable armband enforcement
        return 
    end
    local armband = get_armband(ctx, folder, "CL_captainmark_00.ftex")
    if armband then
        local f = io.open(armband)
        if f then
            f:close()
            log(string.format("current tournament id %d has a custom armband: %s", tid, armband))
            -- we have a custom armband for this tournament, so patch the exe
            -- to enforce the loading of it
            set_uefa_armband()
        end
    end
    local badge = get_badge(ctx, folder, 0)
    if badge then
        local f = io.open(badge)
        if f then
            f:close()
            log(string.format("current tournament id %d has a custom badge: %s", tid, badge))
            -- we have a custom badge for this tournament, so patch the exe
            -- to enforce the loading of it
            set_badge()
        end
        badge = string.gsub(badge, "badge0.ftex", "badge0-left.ftex")
        f = io.open(badge)
        if f then
            f:close()
            badge0_left_ftex = true
            log(string.format("current tournament id %d has a custom left sleeve badge: %s", tid, badge))
            -- we have a custom badge for this tournament, so patch the exe
            -- to enforce the loading of it
            set_badge_left()
        end
    end
    -- check licensed case
    local badge_left
    if not badge0_left_ftex then
        badge_left = get_badge(ctx, folder, 98)
    end
    if not badge_left then
        badge_left = get_badge(ctx, folder, 99)
    end
    if badge_left then
        local f = io.open(badge_left)
        if f then
            f:close()
            log(string.format("current tournament id %d has a custom badge for left sleeve: %s", tid, badge_left))
            -- we have a custom left sleeve badge for this tournament, so patch the exe
            -- to enforce the loading of it
            set_badge_left()
        end
    end
end

function m.init(ctx)
    --[[
    0000000141EAAA48 | 83FB 21                         | cmp ebx,21                              | 21:'!'
    0000000141EAAA4B | 74 59                           | je pes2021.141EAAAA6                    |
    0000000141EAAA4D | 48:C747 18 0F000000             | mov qword ptr ds:[rdi+18],F             |
    --]]
    armband_patch_addr = memory.search_process("\x83\xfb\x21\x74\x59\x48\xc7\x47\x18\x0f\x00\x00\x00")
    if not armband_patch_addr then
        error("unable to find code location for armband logic")
    end
    log("armband logic found at: " .. memory.hex(armband_patch_addr))

    --[[
    0000000141EAD009 | 66:85FF                         | test di,di                              |
    0000000141EAD00C | 74 52                           | je pes2021.141EAD060                    |
    0000000141EAD00E | 4C:8BCB                         | mov r9,rbx                              |
    0000000141EAD011 | 4C:8D85 C8000000                | lea r8,qword ptr ss:[rbp+C8]            |
    --]]
    badge_patch_addr = memory.search_process("\x66\x85\xff\x74\x52\x4c\x8b\xcb\x4c\x8d\x85\xc8\x00\x00\x00")
    if not badge_patch_addr then
        error("unable to find code location for badge logic")
    end
    log("badge logic found at: " .. memory.hex(badge_patch_addr))

    --[[
    0000000141EAD060 | 0FB77C24 7C                     | movzx edi,word ptr ss:[rsp+7C]          |
    0000000141EAD065 | 66:85FF                         | test di,di                              |
    --]]
    badge_patch_addr2 = badge_patch_addr + 0x60 - 0x09
    log("badge (left shoulder) logic found at: " .. memory.hex(badge_patch_addr2))

    -- check for CommonLib
    if not ctx.common_lib then
        log("WARN: CommonLib is missing. Badge/Armband mappings will not work in exhibition mode")
    end

    content_root = ctx.sider_dir .. "content\\badge-server\\"
    map = load_map(content_root .. "map.txt")
    patterns = {
        ["Asset\\model\\character\\uniform\\badge\\#windx11\\badge(%d+)%.ftex"] = get_badge,
        ["Asset\\model\\character\\uniform\\badge\\#windx11\\respect_badge%.ftex"] = get_respect_badge,
        ["Asset\\model\\character\\uniform\\cap\\#windx11\\(CL_captainmark.+)"] = get_armband,
    }
    ctx.register("livecpk_get_filepath", m.get_filepath)
    ctx.register("set_teams", m.set_teams)
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
end

return m

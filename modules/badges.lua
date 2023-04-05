-- badges.lua

local m = { version = "v0.2" }

local map
local map_count
local content_root
local patterns
local armband_patch_addr
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
        tid = get_common_lib(ctx).tid_same_league(ctx.home_team, ctx.away_team) or tid
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

local function get_armband(ctx, folder, basename)
    return content_root .. "\\" .. folder .. "\\cap\\" .. basename
end

local function get_badge(ctx, folder, badge_id)
    badge_id = tonumber(badge_id)
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
    local tid = get_tid(ctx)
    local folder = map[tid]
    if not folder then
        -- nothing mapped for this tournament id
        -- unpatch the exe to disable armband enforcement
        unset_uefa_armband()
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

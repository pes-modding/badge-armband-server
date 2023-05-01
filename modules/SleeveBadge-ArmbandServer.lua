-- Sleeve badge and captain armband server for PES 2021
-- by Hawke and juce
-- originally released on EvoWeb.uk in April 2023

local m = { version = "v3.4" }

local map
local map_count
local team_map
local content_root
local patterns
local armband_patch_addr
local badge_patch_addr
local badge_patch_addr2
local hard_patch_addr
local hard_patch_codecave_addr
local badge_patch_map
local messages = {}
local frame_count = 0

local reload_button = {
    vkey = 0x30, label = "[0]"
}

local empty = {}
local function get_common_lib(ctx)
    return ctx.common_lib or empty
end

if ffi ~= nil then
    -- bind VirtualAlloc, unless it is already bound
    ffi.cdef[[
    typedef uint64_t LPVOID;
    typedef uint64_t SIZE_T;
    typedef uint32_t DWORD;
    typedef uint8_t BYTE;

    BYTE* VirtualAlloc(LPVOID lpAddress, SIZE_T dwSize, DWORD  flAllocationType, DWORD  flProtect);
    ]]
end

local function len(t)
    local count = 0
    for _, _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function get_tournament_id_for_team_id(ctx, team_id)
    if not ctx.common_lib or not ctx.common_lib.has_value then
        log("WARN: CommonLib missing or incompatible version")
        return
    end
    for index, t in pairs(ctx.common_lib.teams_in_playable_leagues_map or empty) do
        if ctx.common_lib.has_value and ctx.common_lib.has_value(t, team_id) then
            return (ctx.common_lib.compID_to_tournamentID_map or empty)[index]
        end
    end
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
    log("applying badge-left patch at " .. memory.hex(badge_patch_addr2))
    memory.write(badge_patch_addr2, "\x90\x90\x90\x90\x90")
end

local function unset_badge_left()
    log("removing badge-left patch at " .. memory.hex(badge_patch_addr2))
    memory.write(badge_patch_addr2, "\x66\x85\xff\x74\x53")
end

local function set_harl()
    --[[
    0000000141EAD731 | 48:B8 0000450C00000000          | mov rax,C450000                         |
    0000000141EAD73B | FFD0                            | call rax                                |
    0000000141EAD73D | 90                              | nop                                     |
    0000000141EAD73E | 90                              | nop                                     |
    0000000141EAD73F | 90                              | nop                                     |
    --]]
    log("applying home-away-right-left patch at " .. memory.hex(harl_patch_addr))
    memory.write(harl_patch_addr, "\x48\xb8" .. memory.pack("u64", harl_patch_codecave_addr) .. "\xff\xd0\x90\x90\x90")
end

local function write_harl_code()
    --[[
    000000000C450000 | 41:80FC 01                      | cmp r12b,1                              |
    000000000C450004 | 75 05                           | jne C45000B                             |
    000000000C450006 | 66:81C1 0010                    | add cx,1000                             |
    000000000C45000B | 48:B8 80D0EA4101000000          | mov rax,pes2021.141EAD080               |
    000000000C450015 | 48:398424 80000000              | cmp qword ptr ss:[rsp+80],rax           |
    000000000C45001D | 72 05                           | jb C450024                              |
    000000000C45001F | 66:81C1 0020                    | add cx,2000                             |
    000000000C450024 | 48:33C0                         | xor rax,rax                             |
    000000000C450027 | 0FB7C1                          | movzx eax,cx                            |
    000000000C45002A | 05 00400000                     | add eax,4000                            |
    000000000C45002F | 894424 28                       | mov dword ptr ss:[rsp+28],eax           |
    000000000C450033 | 4C:8BC3                         | mov r8,rbx                              |
    000000000C450036 | 48:8D4C24 38                    | lea rcx,qword ptr ss:[rsp+38]           |
    000000000C45003B | 8D53 21                         | lea edx,qword ptr ds:[rbx+21]           |
    000000000C45003E | C3                              | ret                                     |
    --]]
    log("writing home-away-right-left code snippet at " .. memory.hex(harl_patch_codecave_addr))
    memory.write(harl_patch_codecave_addr,
        "\x41\x80\xfc\01" ..
        "\x75\x05" ..
        "\x66\x81\xc1\x00\x10" ..
        "\x48\xb8" .. memory.pack("u64", badge_patch_addr2 + 0x80 - 0x65) ..
        "\x48\x39\x84\x24\x80\x00\x00\x00" ..
        "\x72\x05" ..
        "\x66\x81\xc1\x00\x20" ..
        "\x48\x33\xc0" ..
        "\x0f\xb7\xc1" ..
        "\x05\x00\x40\x00\x00" ..
        "\x89\x44\x24\x28" ..
        "\x4c\x8b\xc3" ..
        "\x48\x8d\x4c\x24\x38" ..
        "\x8d\x53\x21" ..
        "\xc3")
end

local function unset_harl()
    --[[
    0000000141EAD731 | 894424 20                       | mov dword ptr ss:[rsp+20],eax           |
    0000000141EAD735 | 4C:8BC3                         | mov r8,rbx                              | r8:"badge00"
    0000000141EAD738 | 48:8D4C24 30                    | lea rcx,qword ptr ss:[rsp+30]           |
    0000000141EAD73D | 8D53 21                         | lea edx,qword ptr ds:[rbx+21]           |
    --]]
    log("removing home-away-right-left patch at " .. memory.hex(harl_patch_addr))
    memory.write(harl_patch_addr, "\x89\x44\x24\x20\x4c\x8b\xc3\x48\x8d\x4c\x24\x30\x8d\x53\x21")
end

badge_patch_map = {
    ["badge.ftex"] = set_badge,
    ["badge-left.ftex"] = set_badge_left,
}

local function get_armband(ctx, folder, basename)
    return content_root .. folder .. "\\cap\\" .. basename
end

local function get_full_pathname(ctx, folder, is_away, badge_file, suffix)
    local team_id
    if is_away then
        team_id = ctx.away_team
    else
        team_id = ctx.home_team
    end
    local team_folder = team_map[team_id]
    -- check mapping
    if not team_folder then
        return content_root .. folder .. "\\badge\\" .. badge_file .. suffix
    end
    -- check file existence
    local pathname = content_root .. folder .. "\\badge\\" .. team_folder .. "\\" .. badge_file .. suffix
    local f = io.open(pathname)
    if f then
        f:close()
        return pathname
    end
    return content_root .. folder .. "\\badge\\" .. badge_file .. suffix
end

local function get_badge(ctx, folder, badge_id, is_left, is_away)
    local suffix = is_left and "-left.ftex" or ".ftex"
    return get_full_pathname(ctx, folder, is_away, "badge", suffix)
end

local function get_respect_badge(ctx, folder)
    return content_root .. folder .. "\\badge\\respect_badge.ftex"
end

local function load_map(filename, required)
    local map = {}
    local delim = ","
    local f = io.open(filename)
    if not f then
        if required then
            error("unable to open " .. filename .. " for reading")
        end
        log("WARN: unable to open " .. filename .. " for reading. Skipping")
    end
    f:close()
    for line in io.lines(filename) do
        -- trim comments and whitespace
        line = line:gsub("#.*$", "")
        local id, folder = string.match(line, "%s*(.+)%s*,%s*[\"]([^\"]+)[\"]")
        id = tonumber(id)
        if id and folder then
            map[id] = folder
            log(string.format("map: id %d => %s", id, folder))
        end
    end
    log("total entries in map: " .. len(map))
    return map
end

function m.get_filepath(ctx, filename)
    local badge_id = string.match(filename, "Asset\\model\\character\\uniform\\badge\\#windx11\\badge(%d+)%.ftex")
    if badge_id then
        log("Loading: " .. filename)
        local is_away, is_left = false, false
        badge_id = tonumber(badge_id)
        if badge_id >= 0x4000 then
            badge_id = badge_id - 0x4000
        end
        if badge_id >= 0x2000 then
            badge_id = badge_id - 0x2000
            is_left = true
        end
        if badge_id >= 0x1000 then
            badge_id = badge_id - 0x1000
            is_away = true
        end

        local tid = ctx.tournament_id or 0
        local folder = map[tid]
        if not folder and (tid == 65535 or tid == 0) then
            -- Exhibition or Edit Mode, not mapped
            tid = get_tid(ctx) or tid
            if tid == 65535 or tid == 0 then
                -- Exhibition, not mapped, and not the same league
                if is_away then
                    tid = get_tournament_id_for_team_id(ctx, ctx.away_team) or tid
                else
                    tid = get_tournament_id_for_team_id(ctx, ctx.home_team) or tid
                end
            end
        end
        log(string.format("Loading badge: %d, is_left=%s, is_away=%s (tid=%d)", badge_id, is_left, is_away, tid))

        folder = map[tid]
        if not folder then
            -- nothing mapped for this tournament id
            return
        end
        local path = get_badge(ctx, folder, badge_id, is_left, is_away)
        log(filename .. " => " .. tostring(path))
        return path
    end

    for p,f in pairs(patterns) do
        local str = string.match(filename, p)
        if str then
            log("Loading: " .. filename)
            local tid = ctx.tournament_id or 0
            local folder = map[tid]
            if not folder and (tid == 65535 or tid == 0) then
                -- Exhibition or Edit Mode, not mapped
                tid = get_tid(ctx) or tid
                folder = map[tid]
            end
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
        map = load_map(content_root .. "map.txt", true)
        team_map = load_map(content_root .. "map_teams.txt")
        messages[#messages + 1] = "map reloaded"
        frame_count = 0
    end
end

local function set_patches(ctx, team_id, is_edit_mode)
    -- start with all patches removed
    unset_uefa_armband()
    unset_badge()
    unset_badge_left()
    unset_harl()

    local tid = ctx.tournament_id
    if not tid and is_edit_mode then
        -- special tid for Edit Mode: 0
        tid = 0
        log("We are in edit mode. Using tid=0")
    end
    local folder = map[tid]
    if not folder then
        -- Not mapped. Get a league tid
        tid = get_tid(ctx)
        if not tid then
            tid = get_tournament_id_for_team_id(ctx, team_id)
        end
    end

    folder = folder or map[tid]
    if folder then
        -- a mapped tournament, or exhibition with teams from the same league
        local armband = get_armband(ctx, folder, "CL_captainmark_00.ftex")
        if armband then
            local f = io.open(armband)
            if f then
                f:close()
                log(string.format("current tournament id %s has a custom armband: %s", tid, armband))
                -- we have a custom armband for this tournament, so patch the exe
                -- to enforce the loading of it
                set_uefa_armband()
            end
        end
    end

    if ctx.tournament_id == 65535 or is_edit_mode then
        set_badge()
        set_badge_left()
        set_harl()
        return
    end

    local team_folders = {
        comp = "",
        home = team_map[ctx.home_team],
        away = team_map[ctx.away_team],
    }
    for filename, patch_func in pairs(badge_patch_map) do
        for _, team_folder in pairs(team_folders) do
            team_folder = team_folder == "" and "" or team_folder .. "\\"
            local fname = content_root .. folder .. "\\badge\\" .. team_folder .. filename
            local f = io.open(fname)
            if f then
                f:close()
                log(string.format("current tournament id %d has a custom badge: %s", tid, fname))
                patch_func()
                has_a_badge = true
            end
        end
    end
    -- if we have a badge, then install harl-patch
    if has_a_badge then
        set_harl()
    end
end

function m.set_teams(ctx)
    set_patches(ctx)
end

function m.set_home_team_for_kits(ctx, team_id, is_edit_mode)
    if is_edit_mode then
        set_patches(ctx, team_id, true)
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
    badge_patch_addr2 = badge_patch_addr + 0x65 - 0x09
    log("badge (left shoulder) logic found at: " .. memory.hex(badge_patch_addr2))

    --[[
    0000000141EAD717 | 49:8BF8                         | mov rdi,r8                              | rdi:"badge00", r8:"badge00"
    0000000141EAD71A | 48:8BF2                         | mov rsi,rdx                             |
    0000000141EAD71D | 66:83F9 64                      | cmp cx,64                               | 64:'d'
    0000000141EAD721 | 73 6F                           | jae pes2021.141EAD792                   |
    0000000141EAD723 | 0FB7C1                          | movzx eax,cx                            |
    --]]
    harl_patch_addr = memory.search_process("\x49\x8b\xf8\x48\x8b\xf2\x66\x83\xf9\x64\x73\x6f\x0f\xb7\xc1")
    if not harl_patch_addr then
        error("unable to find code location for harl patch")
    end
    harl_patch_addr = harl_patch_addr + 0x31 - 0x17
    log("harl patch location found at: " .. memory.hex(harl_patch_addr))

    -- allocate a code-cave
    if ffi then
        local allocationFlags = 0x1000 + 0x2000
        local protection_execute_readwrite = 0x40
        harl_patch_codecave_addr = ffi.C.VirtualAlloc(nil, 512, allocationFlags, protection_execute_readwrite)
        if not harl_patch_codecave_addr then
            error("unable to allocate memory with VirtualAlloc")
        end
        log("harl_patch_codecave_addr allocated at: " .. memory.hex(harl_patch_codecave_addr))
        write_harl_code()
    else
        error("ffi module must be enabled for this module to work. To enable, set luajit.ext.enabled = 1 in sider.ini")
    end

    -- check for CommonLib
    if not ctx.common_lib then
        log("WARN: CommonLib is missing. Badge/Armband mappings will not work in exhibition mode")
    end

    content_root = ctx.sider_dir .. "content\\badge-server\\"
    map = load_map(content_root .. "map.txt", true)
    team_map = load_map(content_root .. "map_teams.txt")
    patterns = {
        ["Asset\\model\\character\\uniform\\badge\\#windx11\\respect_badge%.ftex"] = get_respect_badge,
        ["Asset\\model\\character\\uniform\\cap\\#windx11\\(CL_captainmark.+)"] = get_armband,
    }
    ctx.register("livecpk_get_filepath", m.get_filepath)
    ctx.register("set_teams", m.set_teams)
    ctx.register("set_home_team_for_kits", m.set_home_team_for_kits)
    ctx.register("overlay_on", m.overlay_on)
    ctx.register("key_down", m.key_down)
end

return m

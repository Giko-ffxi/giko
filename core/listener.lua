local timer         = require('lib.ashita.timer')
local config        = require('lib.giko.config')
local cache         = require('lib.giko.cache')
local common        = require('lib.giko.common')
local death         = require('lib.giko.death')
local monster       = require('lib.giko.monster')
local chat          = require('lib.giko.chat')
local listener      = { channel = {}, reply = {} }

local channel       = { tell = tonumber(0xC), linkshell_out = tonumber(0xE), linkshell_in = tonumber(0x6) }
local userlist      = string.format('%s\\..\\giko-cache\\cache\\giko.userlist.csv', _addon.path)
local whitelist     = string.format('%s\\..\\giko-cache\\cache\\giko.whitelist.csv', _addon.path)
local all_names_map = {}

local function initialize_name_map()
    all_names_map = {}
    if monster and monster.notorious then
        for _, mob in ipairs(monster.notorious) do
            local names_to_flatten = (mob.names and common.flatten(mob.names)) or {}
            for _, name in ipairs(names_to_flatten) do
                if name and #name > 0 then
                    table.insert(all_names_map, { name_str = name, mob_data = mob })
                end
            end
        end
        table.sort(all_names_map, function(a, b)
            return #a.name_str > #b.name_str
        end)
    else
        print('[Giko] Error: monster.notorious data not found during initialization.')
    end
end
initialize_name_map()

local function parse_monster_from_input(input_string)
    if not input_string or #input_string == 0 then return nil, nil end
    local lower_input = string.lower(input_string)
    for _, name_entry in ipairs(all_names_map) do
        local name = name_entry.name_str
        local mob = name_entry.mob_data
        local lower_name = string.lower(name)

        if string.find(lower_input, lower_name, 1, true) then
            return name, mob
        end
    end

    return nil, nil
end

listener.listen = function(mode, input, m_mode, m_message, blocked)
    local channels = {
        [channel['tell']]          = listener.channel.tell,
        [channel['linkshell_out']] = listener.channel.linkshell,
        [channel['linkshell_in']]  = listener.channel.linkshell
    }
    if channels[mode] then
        channels[mode](input)
    end
    return false
end

listener.channel.linkshell = function(input)
    local replies = { 'sync', 'enable', 'disable', 'get-tod', 'set-tod', 'get-day', 'set-day' }
    local username = string.sub(input, string.find(input, '%a+'))
    if not username then return end

    local tell = {}
    local linkshell = {}

    if not common.in_array_key(cache.get_all(whitelist), username) then
        cache.set(whitelist, username, os.date('%Y-%m-%d %H:%M:%S', os.time()))
    end

    local command_part = string.match(input, '@giko%s+(.+)$')
    if command_part then
        for _, command_name in ipairs(replies) do
            local pattern = string.format('^%s[\\s]*(.*)$', string.gsub(command_name, '-', '%%-'))
            local args = string.match(command_part, pattern)

            if args ~= nil then
                tell, linkshell = listener.reply[command_name](username, args)
                break
            end
        end

        for _, msg in ipairs(tell) do chat.tell(username, msg) end
        for _, msg in ipairs(linkshell) do chat.linkshell(msg) end
    end
end

listener.channel.tell = function(input)
    local replies = { 'sync', 'enable', 'disable', 'get-tod', 'set-tod', 'get-day', 'set-day' }
    local username = string.sub(input, string.find(input, '%a+'))
    if not username then return end

    local tell = {}
    local linkshell = {}

    local command_part = string.match(input, '@giko%s+(.+)$')
    if command_part and (common.in_array(config.whitelist, username) or common.in_array_key(cache.get_all(whitelist), username)) then
        for _, command_name in ipairs(replies) do
            local pattern = string.format('^%s[\\s]*(.*)$', string.gsub(command_name, '-', '%%-'))
            local args = string.match(command_part, pattern)
            if args ~= nil then
                tell, linkshell = listener.reply[command_name](username, args)
                break
            end
        end

        for _, msg in ipairs(tell) do chat.tell(username, msg) end
        for _, msg in ipairs(linkshell) do chat.linkshell(msg) end
    end
end

listener.reply['sync'] = function(username, input)
    local tell = {}
    local tods = {}
    local t = {}
    local l = 0

    if not common.in_array_key(cache.get_all(userlist), username) then
        cache.set(userlist, username, os.date('%Y-%m-%d %H:%M:%S', os.time()))
    end

    for _, set_name in ipairs(config.sets) do
        local v_tod = ''
        for _, mob in ipairs(monster.notorious) do
            if mob.sets and common.in_array(mob.sets, set_name) then
                local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
                if primary_nq_name then
                    local tod = death.get_tod(primary_nq_name)
                    local time_val = (tod and tod.gmt) and common.gmt_to_local_time(tod.gmt) or 0
                    local day_val = (tod and tod.day) or 0

                    local time_hex = common.int_to_hex(time_val)
                    local day_hex = (mob.names and mob.names.hq and mob.names.hq[1]) and common.int_to_hex(day_val, 1) or
                        ''

                    v_tod = v_tod .. day_hex .. time_hex
                end
            end
        end
        table.insert(tods, string.format('[%s][%s]', set_name, v_tod))
    end

    for _, tod_str in ipairs(tods) do
        l = l + #tod_str
        if l <= 125 then
            table.insert(t, tod_str)
        else
            table.insert(tell, string.format('[ToD]%s', table.concat(t, '')))
            t = { tod_str }
            l = #tod_str
        end
    end
    if #t > 0 then table.insert(tell, string.format('[ToD]%s', table.concat(t, ''))) end

    return tell, {}
end

listener.reply['get-tod'] = function(username, input)
    local tell = {}
    local name, mob = parse_monster_from_input(input)

    if name and mob then
        local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
        if primary_nq_name then
            local tod = death.get_tod(primary_nq_name)
            if tod and tod.gmt and tod.day then
                table.insert(tell,
                    string.format("[ToD][%s][%s][%s]", primary_nq_name, common.gmt_to_local_date(tod.gmt), tod.day))
            else
                table.insert(tell, string.format('[ToD][%s][ToD Unknown][-]', primary_nq_name))
            end
        else
            table.insert(tell,
                string.format('[Error] Found mob matching "%s", but it has no primary NQ name defined.', name))
        end
    else
        table.insert(tell, string.format('[Error] Could not find a known monster name in "%s".', input))
    end

    return tell, {}
end

listener.reply['set-tod'] = function(username, input)
    local tell = {}
    local linkshell = {}
    local force_overwrite = false
    local cleaned_input = input
    if string.find(cleaned_input, '%-%-force') then
        force_overwrite = true
        cleaned_input = string.gsub(cleaned_input, '%-%-force', '')
        cleaned_input = string.gsub(cleaned_input, '%s+$', '')
    end
    local time, loc_date, gmt_date = nil, nil, nil
    if string.find(cleaned_input, '%f[%w]now%f[%W]') then
        time = os.time()
        local current_offset_seconds = common.offset_to_seconds(os.date('%z', time))
        loc_date = os.date('%Y-%m-%d %H:%M:%S %z', time)
        gmt_date = os.date('%Y-%m-%d %H:%M:%S', time - current_offset_seconds)
    else
        local Y, m, d, H, M, S, z = string.match(cleaned_input,
            '(%d%d%d%d)-(%d%d)-(%d%d)%s+(%d%d):(%d%d):(%d%d)%s+([%-%+]%d%d%d%d)')
        if Y then
            time = os.time({
                year = tonumber(Y),
                month = tonumber(m),
                day = tonumber(d),
                hour = tonumber(H),
                min =
                    tonumber(M),
                sec = tonumber(S)
            })
            local provided_offset_seconds = common.offset_to_seconds(z)
            local server_offset_seconds = common.offset_to_seconds(os.date('%z', os.time()))
            gmt_date = os.date('%Y-%m-%d %H:%M:%S', time - provided_offset_seconds)
            loc_date = os.date('%Y-%m-%d %H:%M:%S %z', time - provided_offset_seconds + server_offset_seconds)
        end
    end

    if time and loc_date and gmt_date then
        local name, mob = parse_monster_from_input(cleaned_input)
        if name and mob then
            local lower_cleaned_input = string.lower(cleaned_input)
            local D = nil
            local d_match = string.match(lower_cleaned_input, '%s[dD]%s+(%d+)') or
                string.match(lower_cleaned_input, '%s[dD]ay%s+(%d+)')
            if d_match then D = tonumber(d_match) end

            local win = death.get_window(name)

            if win == nil or win.count > 1 or force_overwrite then
                if mob.names.hq and common.in_array(mob.names.hq, name) then
                    tod.day = 0
                end
                if death.set_tod(name, gmt_date) then
                    local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
                    local primary_hq_name = (mob.names and mob.names.hq and mob.names.hq[1])
                    local config_key = primary_nq_name and string.lower(primary_nq_name) or nil
                    local display_name = (primary_nq_name and common.in_array(mob.names.nq, name)) or
                        primary_hq_name or name
                    local tod_data = death.get_tod(name)
                    local day_value = (tod_data and tod_data.day)
                    local day_display_value = (primary_nq_name and common.in_array(mob.names.nq, name)) and day_value or
                        0
                    local day_info = (day_value ~= nil) and string.format('[%s]', day_display_value) or ''
                    local message = string.format('[ToD][%s][%s]%s', display_name, loc_date, day_info)

                    if config_key and config.monsters[config_key] and config.monsters[config_key].enabled then
                        table.insert(linkshell, message)
                        if screamer and screamer.reload then screamer.reload() end
                    else
                        for user, t in pairs(cache.get_all(userlist)) do chat.tell(user, message) end
                    end
                else
                    table.insert(tell, string.format('Failed to set ToD for [%s].', name))
                end
            else
                local tod_data = death.get_tod(name)
                if tod_data and tod_data.gmt then
                    local existing_tod_gmt_epoch = common.gmt_to_local_time(tod_data.gmt)
                    if math.abs(time - existing_tod_gmt_epoch) > 2 then
                        table.insert(tell,
                            string.format(
                                'Unable to save ToD, incompatible with previous ToD of [%s]. Use --force to overwrite.',
                                common.gmt_to_local_date(tod_data.gmt)))
                    else
                        -- table.insert(tell,
                        --     string.format('ToD for [%s] already recorded recently at [%s]. No update needed.', name,
                        --         common.gmt_to_local_date(tod_data.gmt)))
                    end
                else
                    table.insert(tell,
                        string.format('Could not retrieve existing ToD for [%s].', name))
                end
            end
        else
            table.insert(tell,
                string.format("Valid time found, but couldn't identify a known monster in the input: %s", cleaned_input))
        end
    else
        table.insert(tell,
            string.format(
                'Unable to parse a valid timestamp from input "%s". Use "now" or format "YYYY-MM-DD HH:MM:SS +/-ZZZZ".',
                cleaned_input))
    end

    return tell, linkshell
end

listener.reply['get-day'] = function(username, input)
    local tell = {}
    local name, mob = parse_monster_from_input(input)

    if name and mob then
        local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
        if primary_nq_name then
            local win = death.get_window(primary_nq_name)
            if win then
                table.insert(tell, string.format("[Day][%s][%s]", primary_nq_name, win.day or 'Day Unknown / No HQ?'))
            else
                table.insert(tell, string.format('[Day][%s][Window/ToD Unknown]', primary_nq_name))
            end
        else
            table.insert(tell,
                string.format('[Error] Found mob matching "%s", but it has no primary NQ name defined.', name))
        end
    else
        table.insert(tell, string.format('[Error] Could not find a known monster name in "%s".', input))
    end

    return tell, {}
end

listener.reply['set-day'] = function(username, input)
    local tell = {}
    local linkshell = {}
    local day_number = nil
    local input_for_name_parse = input

    local day_match = string.match(input, '(%d+)')
    if day_match then
        day_number = tonumber(day_match)
        input_for_name_parse = string.gsub(input, '%s+%d+$', '')
    else
        day_match = string.match(input, '^(%d+)%s+')
        if day_match then
            day_number = tonumber(day_match)
            input_for_name_parse = string.gsub(input, '^%d+%s+', '')
        end
    end

    if day_number == nil then
        table.insert(tell, "[Error] Could not find day number in input.")
        return tell, linkshell
    end

    local name, mob = parse_monster_from_input(input_for_name_parse)

    if name and mob then
        local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
        if primary_nq_name then
            if death.set_day(name, math.max(day_number - 1, 0)) then
                table.insert(linkshell, string.format('[Day][%s][%s]', primary_nq_name, day_number))
                if screamer and screamer.reload then screamer.reload() end
            else
                table.insert(tell, string.format('[Error] Failed to set day for [%s].', name))
            end
        else
            table.insert(tell,
                string.format('[Error] Found mob matching "%s", but it has no primary NQ name defined.', name))
        end
    else
        table.insert(tell,
            string.format('[Error] Found day number %d, but could not find a known monster name in "%s".', day_number,
                input_for_name_parse))
    end

    return tell, linkshell
end

listener.reply['enable'] = function(username, input)
    local linkshell = {}
    local name, mob = parse_monster_from_input(input)

    if name and mob then
        local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
        if primary_nq_name then
            local lower_nq_name = string.lower(primary_nq_name)
            if config.monsters and config.monsters[lower_nq_name] then
                config.monsters[lower_nq_name].enabled = true
                config.save()
                table.insert(linkshell, string.format('[Alerts][%s][Enabled]', primary_nq_name))
                if screamer and screamer.reload then screamer.reload() end
            else
                table.insert(linkshell,
                    string.format('[Error] No configuration found for [%s] to enable.', primary_nq_name))
            end
        else
            table.insert(linkshell,
                string.format('[Error] Found mob matching "%s", but it has no primary NQ name defined for config.', name))
        end
    else
        table.insert(linkshell, string.format('[Error] Could not find a known monster name in "%s" to enable.', input))
    end

    return {}, linkshell
end

listener.reply['disable'] = function(username, input)
    local linkshell = {}
    local name, mob = parse_monster_from_input(input)

    if name and mob then
        local primary_nq_name = (mob.names and mob.names.nq and mob.names.nq[1])
        if primary_nq_name then
            local lower_nq_name = string.lower(primary_nq_name)
            if config.monsters and config.monsters[lower_nq_name] then
                config.monsters[lower_nq_name].enabled = false
                config.save()
                table.insert(linkshell, string.format('[Alerts][%s][Disabled]', primary_nq_name))
                if screamer and screamer.reload then screamer.reload() end
            else
                table.insert(linkshell,
                    string.format('[Error] No configuration found for [%s] to disable.', primary_nq_name))
            end
        else
            table.insert(linkshell,
                string.format('[Error] Found mob matching "%s", but it has no primary NQ name defined for config.', name))
        end
    else
        table.insert(linkshell, string.format('[Error] Could not find a known monster name in "%s" to disable.', input))
    end

    return {}, linkshell
end


return listener

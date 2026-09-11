#!/usr/bin/lua

local nixio = require "nixio"
local mtwifi_utils = {}

function mtwifi_utils.esc(x)
    return (x:gsub('%%', '%%%%')
             :gsub('^%^', '%%^')
             :gsub('%$$', '%%$')
             :gsub('%(', '%%(')
             :gsub('%)', '%%)')
             :gsub('%.', '%%.')
             :gsub('%[', '%%[')
             :gsub('%]', '%%]')
             :gsub('%*', '%%*')
             :gsub('%+', '%%+')
             :gsub('%-', '%%-')
             :gsub('%?', '%%?'))
end

function mtwifi_utils.trim(s)
    if s then return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

function mtwifi_utils.exists(path)
    local fp = io.open(path, "rb")
    if fp then fp:close() end
    return fp ~= nil
end

function mtwifi_utils.read_pipe(pipe)
    local retry_count = 10
    local fp, txt, err
    repeat
        fp = io.popen(pipe)
        txt, err = fp:read("*a")
        fp:close()
        retry_count = retry_count - 1
    until err == nil or retry_count == 0
    return txt
end

function mtwifi_utils.__cfg2list(str)
    -- delimeter == ";"
    local i = 1
    local list = {}
    for k in string.gmatch(str, "([^;]+)") do
        list[i] = k
        i = i + 1
    end
    return list
end

function mtwifi_utils.token_set(str, n, v)
    -- n start from 1
    -- delimeter == ";"
    if not str then return end
    if v == nil then return end
    local tmp = mtwifi_utils.__cfg2list(str)
    if type(v) ~= type("") and type(v) ~= type(0) then
        nixio.syslog("err", "invalid value type in token_set, "..type(v))
        return
    end
    if #tmp < tonumber(n) then
        for i=#tmp, tonumber(n) do
            if not tmp[i] then
                tmp[i] = v -- pad holes with v !
            end
        end
    else
        tmp[n] = v
    end
    return table.concat(tmp, ";"):gsub("^;*(.-);*$", "%1"):gsub(";+",";")
end

function mtwifi_utils.token_get(str, n, v)
    -- n starts from 1
    -- v is the backup in case token n is nil
    if not str then return v end
    local tmp = mtwifi_utils.__cfg2list(str)
    return tmp[tonumber(n)] or v
end

function mtwifi_utils.sleep(s)
    local seconds = math.floor(s)
    local nanoseconds = math.floor((s - seconds) * 1000000000)
    while true do
        local ok, remaining_seconds, remaining_nanoseconds = nixio.nanosleep(seconds, nanoseconds)
        if ok then return end
        if ok == nil then error("mtwifi-cfg: nanosleep failed") end
        -- nixio returns false plus the remaining duration on EINTR.
        seconds, nanoseconds = remaining_seconds, remaining_nanoseconds
    end
end

function mtwifi_utils.log_config_changes(diff)
    local fields = {}
    for field in pairs(diff) do
        fields[#fields + 1] = field
    end
    table.sort(fields)
    -- Only log field names, never configuration values or old/new secrets.
    -- Use the system log's bounded storage instead of an append-only /tmp file.
    nixio.syslog("info", "mtwifi-cfg: changed fields (" .. #fields .. "): " ..
        table.concat(fields, ", "):sub(1, 1024))
end

return mtwifi_utils

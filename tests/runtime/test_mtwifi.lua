-- Host-side regression tests; all router I/O and native modules are mocked.
local base = "package/mtk/applications/mtwifi-cfg/files/mtwifi-cfg/"
package.path = base .. "?.lua;" .. package.path
local case = arg[1]
local logs, commands, saved, sleeps = {}, {}, nil, {}
local secret, old_secret = "fixture-secret-NEW", "fixture-secret-OLD"
local fixture = {
    device = "radio5",
    config = {band = "5g", htmode = "EHT160", channel = "36"},
    interfaces = {["0"] = {
        mtwifi_ifname = "rai0",
        config = {mode = "ap", encryption = "sae", ssid = "fixture", key = secret}
    }}
}
local decode_error, missing_profile, empty_input, interface_error
if case == "invalid-json" then decode_error = true
elseif case == "missing-profile" then missing_profile = true
elseif case == "empty-input" then empty_input = true
elseif case == "invalid-encryption" then fixture.interfaces["0"].config.encryption = "unsupported"
elseif case == "invalid-structure" then fixture = false
elseif case == "unknown-device" then fixture.device = "absent"
elseif case == "no-interfaces" then fixture.interfaces = {}
elseif case == "invalid-mode" then fixture.config.band = "bad"
elseif case == "invalid-htmode" then fixture.config.htmode = nil
elseif case == "interface-failure" then interface_error = true
elseif case == "too-many-stations" then
    fixture.interfaces["0"].config.mode = "sta"
    fixture.interfaces["1"] = {config = {mode = "sta", encryption = "sae"}}
end

local nixio = {
    syslog = function(level, message) logs[#logs + 1] = message end,
    nanosleep = function(seconds, nanoseconds)
        sleeps[#sleeps + 1] = {seconds, nanoseconds}
        if case == "sleep-error" then return nil, "error", 22 end
        if #sleeps == 1 then return false, 0, 250000000 end
        return true
    end
}
package.preload.nixio = function() return nixio end
local utils = require "mtwifi_utils"

if case == "sleep" then
    utils.sleep(1.5)
    assert(#sleeps == 2)
    assert(sleeps[1][1] == 1 and sleeps[1][2] == 500000000)
    assert(sleeps[2][1] == 0 and sleeps[2][2] == 250000000)
elseif case == "sleep-error" then
    assert(not pcall(utils.sleep, 1))
    assert(#sleeps == 1)
elseif case == "bounded-log" then
    local diff = {}
    for i = 1, 1000 do diff["WPAPSK" .. i] = {old_secret, secret} end
    utils.log_config_changes(diff)
    assert(#logs == 1 and #logs[1] < 1100)
else
    package.preload.cjson = function() return {decode = function()
        if decode_error then error(secret) end
        return fixture
    end} end
    package.preload.l1dat_parser = function() return {
        load_l1_profile = function() return {devname_ridx = {radio5 = {
            profile_path = "/fixture/profile.dat", main_ifname = "rai0",
            ext_ifname = "rai", apcli_ifname = "apclii", wds_ifname = "wdsi",
            mesh_ifname = "meshi"
        }}} end
    } end
    package.preload.datconf = function() return {openfile = function()
        if missing_profile then return nil end
        return {
            getall = function() return {BssidNum = "4", WdsEnable = "0", WPAPSK1 = old_secret} end,
            merge = function(self, values) saved = values end,
            close = function() end
        }
    end} end

    io.read = function() if not empty_input then return "fixture-json" end end
    io.open = function() error("unexpected file I/O") end
    io.popen = function(command)
        return {read = function()
            if command:find("/flags", 1, true) then return "0" end
            return "rai0"
        end, close = function() end}
    end
    os.execute = function(command)
        commands[#commands + 1] = command
        if interface_error and command == "ifconfig rai0 up" then return 256 end
        return 0
    end
    local exit_code
    os.exit = function(code) exit_code = code; error("EXIT") end
    arg = {"setup"}
    local ok = pcall(dofile, base .. "mtwifi_cfg")
    if case == "success" then
        assert(ok and exit_code == nil, table.concat(logs, "\n"))
        assert(saved.AuthMode == "WPA3PSK" and saved.EncrypType == "AES")
        assert(saved.PMFMFPC == "1" and saved.PMFMFPR == "1")
        assert(saved.WPAPSK1 == secret)
        assert(table.concat(commands, "\n"):find("ifconfig rai0 up", 1, true))
    else
        assert(not ok and exit_code == 1, "failure was not propagated: " .. case)
        if case ~= "interface-failure" then
            assert(saved == nil and #commands == 0, "invalid input changed router state")
        end
    end
end

for _, message in ipairs(logs) do
    assert(not message:find(secret, 1, true), "new secret in log")
    assert(not message:find(old_secret, 1, true), "old secret in log")
end
print("PASS " .. case)

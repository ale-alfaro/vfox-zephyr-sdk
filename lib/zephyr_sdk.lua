---@nodoc
require("utils.core")

--- nrfutil launcher download URLs keyed by platform
---@class Utils
---@module 'utils.inspect'
---@module 'utils.fs'
---@module 'utils.sh'
---@module 'utils.net'
---@module 'strings'
---@module 'semver'
Utils._submodules = {
    inspect = true,
    fs = true,
    sh = true,
    net = true,
    store = true,
    semver = true,
}

Utils._mise_submods = {
    strings = true,
    file = true,
    http = true,
    cmd = true,
}
-- These are for loading runtime modules in the vim namespace lazily.
setmetatable(Utils, {
    --- @param t table<any,any>
    __index = function(t, key)
        if Utils._submodules[key] then
            t[key] = require("utils." .. key)
            return t[key]
        elseif Utils._mise_submods[key] then
            t[key] = require(key)
            return t[key]
        end
    end,
})

_G.ZephyrSdk = _G.ZephyrSdk or {}
---@class ZephyrSDK._tools : table<string, ZephyrTool>
ZephyrSdk._tools = {
    toolchain = true,
    ncs_toolchain = true,
    west = true,
}
---@class ZephyrSDK._tools_alias : table<string, string>
ZephyrSdk._tools_alias = {
    ["zephyr-sdk"] = "toolchain",
    ["arm-zephyr-eabi"] = "toolchain",
    ["gnu_zephyr"] = "toolchain",
    ["llvm"] = "toolchain",
    ["hosttools"] = "toolchain",
    ["ncs"] = "ncs_toolchain",
}

-- These are for loading runtime modules in the vim namespace lazily.
setmetatable(ZephyrSdk, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
        if ZephyrSdk._tools_alias[key] then
            key = ZephyrSdk._tools_alias[key]
        end
        if ZephyrSdk._tools[key] then
            t[key] = require(key)
            return t[key]
        end
    end,
})

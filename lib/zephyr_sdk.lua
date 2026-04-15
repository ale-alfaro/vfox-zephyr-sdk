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
}

Utils._mise_submods = {
    strings = true,
    semver = true,
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

---@class ZephyrTool
---@field list_versions? fun(): string[]
---@field install fun(version: string,install_path:string, install_path:string): nil
---@field envs fun(version: string,install_path:string):EnvKey[]

_G.ZephyrSDK = _G.ZephyrSDK or {}
---@class ZephyrSDK._tools : table<string, ZephyrTool>
ZephyrSDK._tools = {
    gnu_zephyr = true,
    llvm = true,
    hosttools = true,
    west = true,
}
---@class ZephyrSDK._tools_alias : table<string, string>
ZephyrSDK._tools_alias = {
    ["toolchain"] = "gnu_zephyr",
    ["arm-zephyr-eabi"] = "gnu_zephyr",
}

-- These are for loading runtime modules in the vim namespace lazily.
setmetatable(ZephyrSDK, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
        if ZephyrSDK._tools_alias[key] then
            key = ZephyrSDK._tools_alias[key]
        end
        if ZephyrSDK._tools[key] then
            t[key] = require(key)
            return t[key]
        end
    end,
})

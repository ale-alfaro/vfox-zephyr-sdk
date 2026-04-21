---@nodoc
require("utils.core")
---@class ZephyrSdk
_G.ZephyrSdk = _G.ZephyrSdk or {}

---@class ZephyrSdk._tools : table<string, ZephyrTool>
ZephyrSdk._tools = {
    toolchain = true,
    ncs_toolchain = true,
    west = true,
}

---@type ToolOptions[]
ZephyrSdk.tool_options = {}
-- These are for loading runtime modules in the vim namespace lazily.
setmetatable(ZephyrSdk, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
        if not ZephyrSdk._tools[key] then
            error("Tool not registered " .. key)
        end
        t[key] = require(key)
        return t[key]
    end,
})

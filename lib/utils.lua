---@nodoc
require("utils.core")

Utils._submodules = {
    inspect = true,
    fs = true,
    sh = true,
}

Utils._mise_submods = {
    strings = true,
    semver = true,
    file = true,
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

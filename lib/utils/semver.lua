local M = require("semver")
local semver_pattern = "^v([0-9]+%.[0-9]+%.[0-9]+)$"
local semver_prerelease_pattern = "^v([0-9]+%.[0-9]+%.[0-9]+)%-(%w+)$"

---@param version string
---@param constraints ReleasesConstraints
---@return boolean
function M.check_version(version, constraints)
    Utils.validate("version", version, "string")
    Utils.validate("constraints", constraints, "table")
    local pattern = constraints.prereleases and semver_prerelease_pattern or semver_pattern
    local semver = version:match(pattern) or ""
    if semver == "" then
        return false
    end
    if constraints.version then
        local min, max = constraints.version.min, constraints.version.max

        if min and Utils.semver.compare(semver, min) < 0 then
            return false
        end
        if max and Utils.semver.compare(semver, max) > 0 then
            return false
        end
    end
    return true
end

--- Enumerates key-value pairs of a table, ordered by key using semver sort
---
---@see Based on https://github.com/premake/premake-core/blob/master/src/base/table.lua
---
---      for _, msg in vim.spairs(report) do -- luacheck: ignore
---        return msg
---      end
---    end
---
---@generic T: table, K, V
---@param t T Dict-like table
---@return fun(table: table<K, V>, index?: K):K, V # |for-in| iterator over sorted keys and their values
---@return T
function M.spairs(t)
    Utils.validate("t", t, "table")
    --- @cast t table<any,any>
    local semver = require("semver")
    -- collect the keys
    local keys = semver.sort(Utils.tbl_keys(t)) --- @type string[]
    -- Return the iterator function.
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end,
        t
end
return M

--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook

---@class ZephyrSdkReleaseCache
---@field releases ZephyrSdkRelease[]
---@field timestamp number
local cache = {}
local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds

local function get_releases()
    local zephyr_sdk = require("zephyr_sdk")
    local now = os.time()

    if cache.releases and cache.timestamp and (now - cache.timestamp) < cache_ttl then
        return cache.releases
    end

    local releases = zephyr_sdk.fetch_releases()
    cache.releases = releases
    cache.timestamp = now

    return releases
end

--- @param ctx AvailableCtx
--- @return AvailableVersion[]
function PLUGIN:Available(ctx)
    local releases = get_releases()
    local semver = require("semver")
    local result = {}

    for _, release in ipairs(releases) do
        if release.tag_name then
            local version = release.tag_name:gsub("^v", "")
            table.insert(result, {
                version = version,
            })
        end
    end

    return semver.sort_by(result, "version")
end

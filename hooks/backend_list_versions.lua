--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions

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

--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    local releases = get_releases()
    local semver = require("semver")
    local versions = {}

    for _, release in ipairs(releases) do
        if release.tag_name then
            local version = release.tag_name:gsub("^v", "")
            table.insert(versions, version)
        end
    end

    return { versions = semver.sort(versions) }
end

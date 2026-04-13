--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions

local cache = {} ---@type ZephyrSdkReleaseCache
local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds

local function get_releases()
    local now = os.time()

    if cache.releases and cache.timestamp and (now - cache.timestamp) < cache_ttl then
        return cache.releases
    end

    local releases = require("gh").fetch_releases()
    cache.releases = releases
    cache.timestamp = now

    return releases
end

--- @param _ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(_ctx)
    require("utils")
    local semver = require("semver")
    local releases = get_releases()

    return {
        versions = Utils.list_filter(function(rel)
            if semver.compare(rel, "1.0.0") >= 0 then
                return true
            end
            return (semver.compare(rel, "0.17.0") == 0 or semver.compare(rel, "0.17.4") >= 0)
        end, releases),
    }
end

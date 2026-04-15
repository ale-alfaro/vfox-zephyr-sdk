--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions

local cache = {}
local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds
local default_version = { "1.0.0", "0.17.4", "0.17.0" }
---@param fetch_fn? fun():string[]
---@return string[]
local function get_releases(fetch_fn)
    local now = os.time()

    if cache.releases and cache.timestamp and (now - cache.timestamp) < cache_ttl then
        return cache.releases
    end

    local releases = (fetch_fn or function()
        return default_version
    end)()
    cache.releases = Utils.semver.sort(releases)
    cache.timestamp = now

    return releases
end

--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    require("zephyr_sdk")
    if not ZephyrSdk[ctx.tool] then
        return {}
    end
    return { versions = get_releases(ZephyrSdk[ctx.tool].list_versions) }
end

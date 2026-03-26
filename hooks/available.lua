--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook

---@class ZephyrSdkReleaseCache
---@field releases ZephyrSdkRelease[]
---@field timestamp number
local cache = {}
local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds

--- Returns a list of available versions for the tool
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx {args: string[]} Context (args = user arguments)
--- @return table[] List of available versions
function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")
    local semver = require("semver")

    local now = os.time()
    if cache.releases and cache.timestamp and (now - cache.timestamp) < cache_ttl then
        return cache.releases
    end

    --
    -- Example 1: GitHub Tags API (most common)
    -- Replace <GITHUB_USER>/<GITHUB_REPO> with your tool's repository

    -- Example 2: GitHub Releases API (for tools that use GitHub releases)
    -- local repo_url = "https://api.github.com/repos/<GITHUB_USER>/<GITHUB_REPO>/releases"

    -- mise automatically handles GitHub authentication - no manual token setup needed
    local lib = require("zephyr_sdk")
    local resp, err = http.get({
        url = lib.get_repo_url(),
    })

    if err ~= nil then
        error("Failed to fetch versions: " .. err)
    end
    if resp.status_code ~= 200 then
        error("GitHub API returned status " .. resp.status_code .. ": " .. resp.body)
    end

    local tags = json.decode(resp.body)
    local result = {}

    -- Process tags/releases
    for _, tag_info in ipairs(tags) do
        -- local version = tag_info.name

        -- Clean up version string (remove 'v' prefix if present)
        -- version = version:gsub("^v", "")

        -- For releases API, you might want:
        local version = tag_info.tag_name:gsub("^v", "")
        local is_not_official = version:match("-([%w%d]+)$")
        local is_prerelease = tag_info.prerelease or is_not_official
        local note = is_prerelease and "pre-release" or nil
        if is_prerelease == nil and semver.compare(version, lib.MIN_VERSION) >= 0 then
            table.insert(result, {
                version = version,
                note = note, -- Optional: "latest", "lts", "pre-release", etc.
                -- addition = {} -- Optional: additional tools/components
            })
        end
    end

    cache.releases = result
    cache.timestamp = now
    return result
end

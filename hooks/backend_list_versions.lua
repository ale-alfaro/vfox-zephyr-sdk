--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions

---@param ctx BackendListVersionsCtx
---@return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    require("zephyr_sdk")
    if not ZephyrSdk[ctx.tool] or not ZephyrSdk[ctx.tool].list_versions then
        Utils.err("Failed to find tool or list_versions function", { ctx = ctx })
        return { versions = {} }
    end
    local tool = ZephyrSdk[ctx.tool]
    local versions = require("semver").sort(tool.list_versions(ctx))
    -- A `created_at` lets mise apply its minimum_release_age check; undated versions stay plain strings.
    local dates = tool.release_dates and tool.release_dates(ctx) or {}
    Utils.dbg("Release dates", dates)
    for i, version in ipairs(versions) do
        if dates[version] then
            versions[i] = { version = version, created_at = dates[version] }
        end
    end
    return { versions = versions }
end

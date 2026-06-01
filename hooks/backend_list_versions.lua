--- Returns a list of available Zephyr SDK versions
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions

--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    require("zephyr_sdk")
    if not ZephyrSdk[ctx.tool] or not ZephyrSdk[ctx.tool].list_versions then
        Utils.err("Failed to find tool or list_versions function", { ctx = ctx })
        return {}
    end
    local releases = ZephyrSdk[ctx.tool].list_versions()
    local versions = require("semver").sort(releases)
    return { versions = versions }
end

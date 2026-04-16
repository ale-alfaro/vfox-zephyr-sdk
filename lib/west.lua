---@class ZephyrTool
local M = {}
local MIN_VERSION = "1.4.0"
--- Map runtime OS name to Zephyr SDK naming convention
---@return string[] versions
M.list_versions = function()
    local uv_bin_path = Utils.sh.get_mise_tool_prefix("uvx")
    if not uv_bin_path then
        error("UV must be installed")
    end
    local versions_json = Utils.sh.exec(
        string.format(
            [[%s pip index versions west --only-final :all: --python-version 3.12 --json]],
            uv_bin_path .. "uvx"
        )
    )
    if not versions_json then
        error("Versions couldn't be fetched from pypi")
    end
    local json = require("json")
    local ok, decoded = pcall(json.decode, versions_json)

    if not ok or not decoded.versions then
        error("Versions couldn't be decoded:" .. decoded)
    end
    local versions = Utils.list_filter(function(v)
        return Utils.semver.compare(MIN_VERSION, v) <= 0
    end, decoded.versions)
    Utils.inf("Versions :", { versions = versions })

    return versions or {}
end
--- Installs the west shim script into the mise install path.
---@param ctx BackendInstallCtx The mise-provided install path
function M.install(ctx)
    local _, install_path, _ = ctx.version, ctx.install_path, ctx.download_path
    local plugin_path = Utils.sh.safe_exec({ "realpath", RUNTIME.pluginDirPath }, { fail = true })
    local local_west = Utils.fs.join_path(plugin_path, "bin", "west")
    local mise_install_path = Utils.fs.Path({ install_path, "west" })
    if not mise_install_path or not Utils.fs.exists(mise_install_path) then
        local cpcmd = string.format("cp %s %s", local_west, install_path)
        local ret = os.execute(cpcmd)
        if ret ~= 0 then
            Utils.err(
                "Failed to copy west shim err: " .. ret,
                { west_shim = local_west, mise_west = mise_install_path }
            )
        end
        Utils.inf("Copied west shim", { west_shim = local_west, mise_west = mise_install_path })
    end
end

--- Python env vars that must be cleared to avoid ZephyrSDK toolchain Python conflicts.

--- Returns environment variables for the west shim.
--- Clears Python env vars that may leak from ZephyrSDK toolchain activation.
---@param ctx BackendExecEnvCtx
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx) -- luacheck: no unused args
    local install_path = ctx.install_path
    local env_vars = {
        { key = "PATH", value = install_path },
    }

    return env_vars
end

return M

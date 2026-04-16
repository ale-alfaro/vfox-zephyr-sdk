---@class ZephyrTool
local M = {}

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

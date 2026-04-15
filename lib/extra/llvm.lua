---@class ZephyrTool
local M = {}

--- Installs the west shim script into the mise install path.
---@param _version string The mise-provided install path
---@param install_path string The mise-provided install path
---@param _download_path string The mise-provided install path
function M.install(_version, install_path, _download_path)
    local plugin_path = Utils.sh.safe_exec(string.format("realpath %q", RUNTIME.pluginDirPath), { fail = true })
    local local_west = Utils.fs.join_path(plugin_path, "bin", "west")
    local mise_install_path = Utils.fs.Path({ install_path, "west" })
    if not Utils.fs.exists(mise_install_path) then
        Utils.sh.safe_exec(string.format("cp %q %q", local_west, install_path), { fail = true })
        Utils.inf("Copied west shim", { west_shim = local_west, mise_west = mise_install_path })
    end
end

--- Python env vars that must be cleared to avoid ZephyrSDK toolchain Python conflicts.

--- Returns environment variables for the west shim.
--- Clears Python env vars that may leak from ZephyrSDK toolchain activation.
---@param _version string The mise-provided install path
---@param install_path string The mise-provided install path
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(_version, install_path) -- luacheck: no unused args
    local env_vars = {
        { key = "PATH", value = install_path },
    }

    return env_vars
end

return M

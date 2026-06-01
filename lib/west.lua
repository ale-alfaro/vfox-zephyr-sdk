--- Template for the west shim script.
--- Dependencies are populated by `uv add --script -r requirements.in` at install time.
local PYTHON_VERSION = "3.12"
local WEST_SCRIPT_SHEBANG = [[#!/usr/bin/env -S uv run --script]]
local WEST_SCRIPT_MAIN = { "from west.app.main import main", "main()" }

local function edit_west_script(file)
    local edited = { WEST_SCRIPT_SHEBANG }

    for _, line in ipairs(Utils.strings.split(Utils.file.read(file), "\n")) do
        if string.find(line, "^#") then
            edited[#edited + 1] = line
        end
    end
    local content = Utils.strings.join(Utils.list_extend(edited, WEST_SCRIPT_MAIN), "\n")
    local fp = io.open(file, "w")
    if not fp then
        error("Could not open file for writing")
    end
    fp:write(content)
    fp:close()
    Utils.dbg("wrote to west script", { file = file, content = content })
end
---@class ZephyrTool
local M = {}

---@return string[] versions
M.list_versions = function()
    return { "1.5.0" } --- only supporting newest west version
end
--- Generates and installs the west shim script into the mise install path.
--- Uses `uv add --script -r requirements.in` to resolve and inline all
--- Python dependencies (including platform markers) at install time.
---@param ctx BackendInstallCtx The mise-provided install context
function M.install(ctx)
    local install_path = ctx.install_path
    local opts = ctx.options or {} ---@as WestToolOptions
    local plugin_west = Utils.fs.join_path(RUNTIME.pluginDirPath, "bin", "west")
    local requirements = {
        Utils.fs.join_path(RUNTIME.pluginDirPath, "scripts", "requirements.in"),
        unpack(Utils.ensure_list(opts.additional_requirements or {})),
    }
    local cmd = require("cmd")
    if not Utils.fs.exists(plugin_west) then
        local requirement_flags = Utils.strings.join(
            Utils.list_filter(function(req)
                if not Utils.fs.exists(req) then
                    Utils.wrn("Could'nt find requirement ", { req = req })
                    return false
                end
                return true
            end, requirements),
            " -r "
        )

        cmd.exec(Utils.strings.join({
            "uv",
            "init",
            "--script",
            plugin_west,
            "--python",
            PYTHON_VERSION,
        }, " "))
        -- Let uv resolve deps from requirements.in and write them into the inline metadata
        cmd.exec(Utils.strings.join({
            "uv",
            "add",
            "--script",
            plugin_west,
            requirement_flags,
        }, " "))
        edit_west_script(plugin_west)
        cmd.exec(Utils.strings.join({
            "uv",
            "lock",
            "--script",
            plugin_west,
        }, " "))
        cmd.exec(Utils.strings.join({
            "chmod",
            "+x",
            plugin_west,
        }, " "))
        Utils.inf("Created new plugin west shim based on requiements", { plugin_west = plugin_west })
    end
    local installation_west = Utils.fs.join_path(install_path, "west")
    os.rename(plugin_west, installation_west)
    os.rename(plugin_west .. ".lock", installation_west .. ".lock")
    Utils.inf("Copied west shim to installation", { src = plugin_west, dst = installation_west })
end

--- Returns environment variables for the west shim.
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

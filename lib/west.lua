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
local MIN_VERSION = "1.4.0"

--- Resolve uv binary path from the dependency environment.
--- mise injects dependency bin dirs into cmd_env (via PLUGIN.depends = {"uv"}),
--- so uv is on PATH when hooks execute. We resolve the full path once and cache it.
---@return string uv_path Absolute path to the uv binary
---@return string uvx_path Absolute path to the uvx binary
local _uv, _uvx
local function resolve_uv()
    if _uv then
        return _uv, _uvx
    end
    local uv = Utils.sh.which("uv")
    if not uv then
        error(
            'uv not found on PATH. Ensure "uv" is declared in PLUGIN.depends '
                .. "and installed via mise (e.g. mise install uv)"
        )
    end
    _uv = uv
    -- uvx lives next to uv
    _uvx = Utils.fs.join_path(Utils.fs.dirname(uv), "uvx")
    Utils.dbg("Resolved uv dependency", { uv = _uv, uvx = _uvx })
    return _uv, _uvx
end

---@return string[] versions
M.list_versions = function()
    ---We want uvx not uv because we run `pip index` which is not in the `uv pip` interface
    local _, uvx = resolve_uv()
    local versions_json = Utils.sh.exec({
        uvx,
        "pip",
        "index",
        "versions",
        "west",
        "--only-final",
        ":all:",
        "--python-version",
        "3.12",
        "--json",
    })
    if not versions_json then
        Utils.wrn("Versions couldn't be fetched from pypi")
        return { "1.5.0" }
    end
    local json = require("json")
    local ok, decoded = pcall(json.decode, versions_json)

    if not ok or not decoded.versions then
        error("Versions couldn't be decoded:" .. decoded)
    end
    local versions = Utils.list_filter(function(v)
        return Utils.semver.compare(MIN_VERSION, v) <= 0
    end, decoded.versions)
    Utils.dbg("Versions :", { versions = versions })

    return versions or { "1.5.0" }
end
--- Generates and installs the west shim script into the mise install path.
--- Uses `uv add --script -r requirements.in` to resolve and inline all
--- Python dependencies (including platform markers) at install time.
---@param ctx BackendInstallCtx The mise-provided install context
function M.install(ctx)
    local install_path = ctx.install_path
    local opts = ctx.options or {} ---@as WestToolOptions
    local plugin_path = Utils.sh.realpath(RUNTIME.pluginDirPath)
    if not plugin_path then
        error("Could not get plugin path")
    end
    local requirements_txt = Utils.fs.join_path(plugin_path, "scripts", "requirements.txt")
    local west_script = Utils.fs.join_path(install_path, "west")

    local uv, _ = resolve_uv()

    Utils.sh.exec({
        uv,
        "init",
        "--script",
        west_script,
        "--python",
        PYTHON_VERSION,
    }, { fail = true })
    -- Let uv resolve deps from requirements.in and write them into the inline metadata
    local requirements_in = {
        Utils.fs.join_path(plugin_path, "scripts", "requirements.in"),
    }
    if type(opts.additional_requirements) == "table" or type(opts.additional_requirements) == "string" then
        Utils.inf("Adding additional dependencies: ", { reqs = opts.additional_requirements })
        requirements_in = Utils.list_extend(requirements_in, Utils.ensure_list(opts.additional_requirements))
    end
    local requirement_flags = { "-c", requirements_txt }
    for _, req in ipairs(requirements_in) do
        if Utils.fs.exists(req) then
            requirement_flags[#requirement_flags + 1] = "-r"
            requirement_flags[#requirement_flags + 1] = req
        else
            Utils.wrn("Could'nt find requirement ", { req = req })
        end
    end
    Utils.sh.exec({
        uv,
        "add",
        "--script",
        west_script,
        unpack(requirement_flags),
    }, { fail = true })
    Utils.sh.exec({
        uv,
        "lock",
        "--script",
        west_script,
    }, { fail = true })
    edit_west_script(west_script)
    Utils.sh.chmod("+x", west_script)
    Utils.inf("Installed west shim", { script = west_script })
end

--- Returns environment variables for the west shim.
---@param ctx BackendExecEnvCtx
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx) -- luacheck: no unused args
    local install_path = ctx.install_path

    local env_vars = {
        { key = "PATH", value = install_path },
    }
    local west_topdir_check = Utils.sh.exec(
        { Utils.fs.join_path(install_path, "west"), "-qqq", "topdir" },
        { silent = true }
    )
    local west_config_check = Utils.sh.exec(
        { Utils.fs.join_path(install_path, "west"), "-qqq", "config", "zephyr.base", "--local" },
        { silent = true }
    )
    if west_topdir_check and west_config_check then
        local west_config_zephyr_base = Utils.sh.exec(
            { Utils.fs.join_path(install_path, "west"), "config", "zephyr.base", "--local" },
            { fail = true }
        )
        Utils.inf("Setting Zephyr Base")
        Utils.list_extend(env_vars, {
            { key = "ZEPHYR_BASE", value = west_config_zephyr_base },
        })
    end

    return env_vars
end

return M

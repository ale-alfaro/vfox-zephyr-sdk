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
    local uv = Utils.sh.exec({ "which", "uv" })
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
    local _, uvx = resolve_uv()
    local versions_json =
        Utils.sh.execf([[%s pip index versions west --only-final :all: --python-version 3.12 --json]], uvx)
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
    Utils.dbg("Versions :", { versions = versions })

    return versions or {}
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

    local uv = resolve_uv()

    Utils.sh.exec({
        uv,
        "init",
        "--script",
        west_script,
        "--python",
        PYTHON_VERSION,
    }, true)
    -- Let uv resolve deps from requirements.in and write them into the inline metadata
    local requirements_in = {
        Utils.fs.join_path(plugin_path, "scripts", "requirements.in"),
    }
    if opts.ncs then
        requirements_in[#requirements_in + 1] = Utils.fs.join_path(plugin_path, "scripts", "requirements-ncs.in")
    end
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
    }, true)
    edit_west_script(west_script)
    Utils.sh.chmod("+x", west_script)
    Utils.inf("Installed west shim", { script = west_script })
end

--- Returns environment variables for the west shim.
--- Attempts to resolve ZEPHYR_BASE from: env var, west workspace, or directory scan.
---@param ctx BackendExecEnvCtx
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx) -- luacheck: no unused args
    local install_path = ctx.install_path
    local opts = ctx.options or {} ---@as WestToolOptions?

    local env_vars = {
        { key = "PATH", value = install_path },
    }
    local zephyr_base_env = os.getenv("ZEPHYR_BASE")

    if not zephyr_base_env and not opts.freestanding then
        Utils.wrn([[West workspace not detected and no ZEPHYR_BASE is set.
  West wont be able to access most commands unless you set this variable
  If you are in a workspace you should set ZEPHYR_BASE to the path of the zephyr repo in the workspace.
  If you know what you are doing and want to silence this warning set the following option in the mise.toml:
  ```toml
  [tools]
  "zephyr-sdk:west" = { ... , freestanding = true }
                    ```
                  ]])
        return env_vars
    end

    return env_vars
end

return M
